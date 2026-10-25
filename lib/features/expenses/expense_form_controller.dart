import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import '../../core/time.dart';
import '../../core/theme/appearance_provider.dart';
import '../auth/auth_providers.dart';
import 'amount_entry.dart';
import 'data/day_format.dart';
import '../family/member_providers.dart';
import '../scan/receipt_services.dart';
import 'expense_providers.dart';

@immutable
class ExpenseFormState {
  const ExpenseFormState({
    required this.amount,
    required this.spentOn,
    this.categoryId,
    this.note = '',
    this.loaded = true,
    this.saving = false,
    this.error,
    this.receiptImagePath,
    this.shareReceipt = false,
  });

  final AmountEntry amount;
  final DateTime spentOn;

  /// Null means "the first category", resolved when saving.
  final String? categoryId;
  final String note;

  /// False while an expense being edited is still loading.
  final bool loaded;
  final bool saving;
  final String? error;

  /// A photo picked in the scan flow, on this device.
  final String? receiptImagePath;

  /// Upload the photo for the household when saving. Off by default: the photo stays on the device.
  final bool shareReceipt;

  ExpenseFormState copyWith({
    AmountEntry? amount,
    DateTime? spentOn,
    String? categoryId,
    String? note,
    bool? loaded,
    bool? saving,
    String? error,
    String? receiptImagePath,
    bool? shareReceipt,
    bool clearError = false,
    bool clearReceipt = false,
  }) {
    return ExpenseFormState(
      amount: amount ?? this.amount,
      spentOn: spentOn ?? this.spentOn,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      loaded: loaded ?? this.loaded,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      receiptImagePath: clearReceipt
          ? null
          : (receiptImagePath ?? this.receiptImagePath),
      shareReceipt: clearReceipt ? false : (shareReceipt ?? this.shareReceipt),
    );
  }
}

/// Draft of an expense being added (`editId == null`) or edited.
class ExpenseFormController extends Notifier<ExpenseFormState> {
  ExpenseFormController(this.editId);

  final String? editId;

  int get _minorDigits =>
      currencyByCode(ref.read(appearanceProvider).currencyCode).minorDigits;

  @override
  ExpenseFormState build() {
    // The new-expense draft lives for the session so folding or unfolding the device
    // (fold panel <-> Add screen) never loses what was typed.
    if (editId == null) ref.keepAlive();
    final today = ref.read(clockProvider)().dateOnly;
    if (editId != null) {
      Future.microtask(_load);
      return ExpenseFormState(
        amount: AmountEntry(minorDigits: _minorDigits),
        spentOn: today,
        loaded: false,
      );
    }
    return ExpenseFormState(
      amount: AmountEntry(minorDigits: _minorDigits),
      spentOn: today,
    );
  }

  Future<void> _load() async {
    final row = await ref.read(expenseRepositoryProvider).getById(editId!);
    if (!ref.mounted) return;
    if (row == null) {
      state = state.copyWith(
        loaded: true,
        error: 'This expense no longer exists',
      );
      return;
    }
    state = ExpenseFormState(
      amount: AmountEntry.fromCents(row.amountCents, minorDigits: _minorDigits),
      spentOn: parseDay(row.spentOn),
      categoryId: row.categoryId,
      note: row.note,
    );
  }

  void digit(String d) =>
      state = state.copyWith(amount: state.amount.digit(d), clearError: true);
  void decimal() =>
      state = state.copyWith(amount: state.amount.decimal(), clearError: true);
  void backspace() => state = state.copyWith(
    amount: state.amount.backspace(),
    clearError: true,
  );
  void setCategory(String id) =>
      state = state.copyWith(categoryId: id, clearError: true);
  void setNote(String note) => state = state.copyWith(note: note);
  void setDate(DateTime date) => state = state.copyWith(spentOn: date.dateOnly);

  /// Fills the draft from a scanned receipt. Only fields that were read are touched, so anything
  /// already typed is kept when the scan found nothing for it.
  void applyReceipt({
    required String imagePath,
    int? cents,
    DateTime? date,
    String? categoryId,
    String? note,
    bool share = false,
  }) {
    state = state.copyWith(
      amount: cents == null
          ? null
          : AmountEntry.fromCents(cents, minorDigits: _minorDigits),
      spentOn: date?.dateOnly,
      categoryId: categoryId,
      note: note,
      receiptImagePath: imagePath,
      shareReceipt: share,
      clearError: true,
    );
  }

  void setShareReceipt(bool share) =>
      state = state.copyWith(shareReceipt: share);
  void clearReceipt() => state = state.copyWith(clearReceipt: true);

  /// Adds a category, selects it, and returns its id.
  Future<String> addCategory(String name) async {
    final row = await ref.read(categoryRepositoryProvider).add(name);
    if (ref.mounted) setCategory(row.id);
    return row.id;
  }

  /// Back to an empty draft (used after saving from the always-open fold panel).
  void reset() => state = build();

  /// Uploads the scanned photo when the person chose to share it. The expense is already saved,
  /// so a failed upload (offline) only means the photo stays on this device.
  Future<void> _shareReceipt(String expenseId, ExpenseFormState s) async {
    final local = s.receiptImagePath;
    final storage = ref.read(receiptStorageProvider);
    if (local == null || !s.shareReceipt || storage == null) return;
    try {
      final path = await storage.upload(
        householdId: ref.read(activeHouseholdIdProvider),
        expenseId: expenseId,
        localPath: local,
      );
      await ref.read(expenseRepositoryProvider).setReceiptPath(expenseId, path);
    } catch (_) {
      // Stays on the device; the expense itself is safe.
    }
  }

  /// Saves the expense. Returns false (and sets [ExpenseFormState.error]) when the amount is zero.
  Future<bool> save() async {
    final s = state;
    if (!s.loaded || s.saving) return false;
    final cents = s.amount.cents;
    if (cents <= 0) {
      state = s.copyWith(error: 'Enter an amount');
      return false;
    }
    state = s.copyWith(saving: true, clearError: true);
    final categories = await ref.read(categoryRepositoryProvider).getAll();
    final CategoryRow? chosen =
        categories.where((c) => c.id == s.categoryId).firstOrNull ??
        categories.firstOrNull;
    final categoryId = chosen?.id ?? otherCategoryId;
    final repo = ref.read(expenseRepositoryProvider);
    if (editId == null) {
      final id = await repo.add(
        amountCents: cents,
        categoryId: categoryId,
        spentOn: s.spentOn,
        note: s.note,
        createdBy: ref.read(currentUserIdProvider) ?? 'You',
      );
      await _shareReceipt(id, s);
    } else {
      await repo.update(
        editId!,
        amountCents: cents,
        categoryId: categoryId,
        spentOn: s.spentOn,
        note: s.note,
      );
    }
    if (ref.mounted) state = state.copyWith(saving: false);
    return true;
  }
}

/// One draft per expense id; `null` is the new-expense draft and is kept for the session. Edit drafts
/// are dropped when nothing watches them.
final expenseFormProvider = NotifierProvider.autoDispose
    .family<ExpenseFormController, ExpenseFormState, String?>(
      ExpenseFormController.new,
    );
