import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/money/currency.dart';
import '../../core/time.dart';
import '../../core/theme/appearance_provider.dart';
import '../auth/auth_providers.dart';
import 'amount_entry.dart';
import 'data/day_format.dart';
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

  ExpenseFormState copyWith({
    AmountEntry? amount,
    DateTime? spentOn,
    String? categoryId,
    String? note,
    bool? loaded,
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return ExpenseFormState(
      amount: amount ?? this.amount,
      spentOn: spentOn ?? this.spentOn,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      loaded: loaded ?? this.loaded,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
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

  /// Adds a category, selects it, and returns its id.
  Future<String> addCategory(String name) async {
    final row = await ref.read(categoryRepositoryProvider).add(name);
    if (ref.mounted) setCategory(row.id);
    return row.id;
  }

  /// Back to an empty draft (used after saving from the always-open fold panel).
  void reset() => state = build();

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
      await repo.add(
        amountCents: cents,
        categoryId: categoryId,
        spentOn: s.spentOn,
        note: s.note,
        createdBy: ref.read(currentUserIdProvider) ?? 'You',
      );
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

/// One draft per expense id; `null` is the new-expense draft. Dropped when nothing watches it.
final expenseFormProvider = NotifierProvider.autoDispose
    .family<ExpenseFormController, ExpenseFormState, String?>(
      ExpenseFormController.new,
    );
