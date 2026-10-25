import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/form_layout.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import 'expense_form_controller.dart';
import 'expense_providers.dart';
import 'widgets/amount_widgets.dart';
import 'widgets/category_picker.dart';
import 'widgets/details_card.dart';

/// Add (`editId == null`) or edit an expense. Same screen and fields on every size.
class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key, this.editId});

  final String? editId;

  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _noteController = TextEditingController();
  final _focus = FocusNode(debugLabel: 'expense-form');

  @override
  void dispose() {
    _noteController.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.editId == null ? '/home' : '/expenses');
    }
  }

  Future<void> _save() async {
    final saved = await ref
        .read(expenseFormProvider(widget.editId).notifier)
        .save();
    if (saved && mounted) _close();
  }

  Future<void> _pickDate() async {
    final state = ref.read(expenseFormProvider(widget.editId));
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: state.spentOn,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      ref.read(expenseFormProvider(widget.editId).notifier).setDate(picked);
    }
  }

  /// Digits, decimal point and backspace from a hardware keyboard, unless the note field has focus.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final controller = ref.read(expenseFormProvider(widget.editId).notifier);
    final key = event.logicalKey;
    final character = event.character;
    if (character != null &&
        character.length == 1 &&
        '0123456789'.contains(character)) {
      controller.digit(character);
      return KeyEventResult.handled;
    }
    if (character == '.' || character == ',') {
      controller.decimal();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      controller.backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(expenseFormProvider(widget.editId));
    final controller = ref.read(expenseFormProvider(widget.editId).notifier);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final money = ref.watch(moneyFormatterProvider);
    final currency = money.currency;
    final now = ref.watch(clockProvider)();
    final t = context.tokens;
    final selectedId =
        form.categoryId ?? (categories.isEmpty ? null : categories.first.id);
    final editing = widget.editId != null;

    // Keep the text field in step when an expense finishes loading for editing.
    if (_noteController.text != form.note && !_focusInNote) {
      _noteController.text = form.note;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: AdaptiveFormLayout(
          header: PageHeader(
            title: editing ? 'Edit expense' : 'Add expense',
            trailing: _CloseButton(onTap: _close),
          ),
          amount: AmountDisplay(
            symbol: currency.symbol,
            text: form.amount.display(money.decimalSeparator),
            isEmpty: form.amount.isEmpty,
            error: form.error,
          ),
          categories: CategoryPicker(
            categories: categories,
            selectedId: selectedId,
            onSelect: controller.setCategory,
            onAdd: () => _addCategory(context),
          ),
          details: DetailsCard(
            note: form.note,
            noteController: _noteController,
            onNoteChanged: controller.setNote,
            date: form.spentOn,
            now: now,
            onPickDate: _pickDate,
          ),
          keypad: AmountKeypad(
            onDigit: controller.digit,
            onDecimal: controller.decimal,
            onBackspace: controller.backspace,
            decimalSeparator: money.decimalSeparator,
            allowDecimal: currency.minorDigits > 0,
          ),
          tip: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: t.navActiveBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              'Tip: press Ctrl or Cmd + N anywhere to add an expense, and Ctrl or Cmd + Enter to save.',
              style: TextStyle(fontSize: 13, color: t.navActiveText),
            ),
          ),
          actions: PrimaryPillButton(
            label: editing ? 'Save changes' : 'Save expense',
            busy: form.saving || !form.loaded,
            onTap: _save,
          ),
        ),
      ),
    );
  }

  bool get _focusInNote =>
      FocusScope.of(context).focusedChild?.context?.widget is EditableText;

  Future<void> _addCategory(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref
          .read(expenseFormProvider(widget.editId).notifier)
          .addCategory(name);
    }
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        shape: CircleBorder(side: BorderSide(color: t.chipBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: kMinTapTarget,
            height: kMinTapTarget,
            child: Icon(Icons.close, size: 22, color: t.text),
          ),
        ),
      ),
    );
  }
}

/// Large green pill button.
class PrimaryPillButton extends StatelessWidget {
  const PrimaryPillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      enabled: !busy,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: t.primary,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text('New category'),
      content: TextField(
        key: const Key('new-category-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'For example Pets'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
