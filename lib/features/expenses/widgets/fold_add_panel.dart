import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../expense_form_controller.dart';
import '../expense_form_screen.dart' show PrimaryPillButton;
import '../../family/member_providers.dart';
import '../expense_providers.dart';
import 'amount_widgets.dart';
import 'category_picker.dart';

/// The Add form for the area below the hinge on a half-open foldable. It edits the same
/// new-expense draft as the full Add screen and saves through the same code.
class FoldAddPanel extends ConsumerWidget {
  const FoldAddPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final form = ref.watch(expenseFormProvider(null));
    final controller = ref.read(expenseFormProvider(null).notifier);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final money = ref.watch(moneyFormatterProvider);
    final canManageCategories = ref
        .watch(permissionsProvider)
        .canManageCategories;
    final selectedId =
        form.categoryId ?? (categories.isEmpty ? null : categories.first.id);

    Future<void> save() async {
      final saved = await controller.save();
      if (saved) controller.reset();
    }

    return ColoredBox(
      color: t.surface,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Add expense',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AmountDisplay(
                symbol: money.currency.symbol,
                text: form.amount.display(money.decimalSeparator),
                isEmpty: form.amount.isEmpty,
                compact: true,
              ),
              if (form.error != null) ...[
                const SizedBox(height: 4),
                Text(
                  form.error!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.rose,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              CategoryPicker(
                categories: categories,
                selectedId: selectedId,
                onSelect: controller.setCategory,
                onAdd: canManageCategories ? () {} : null,
                scrollable: true,
                tileColor: t.background,
              ),
              const SizedBox(height: 12),
              AmountKeypad(
                onDigit: controller.digit,
                onDecimal: controller.decimal,
                onBackspace: controller.backspace,
                decimalSeparator: money.decimalSeparator,
                allowDecimal: money.currency.minorDigits > 0,
                keyHeight: 44,
              ),
              const SizedBox(height: 12),
              PrimaryPillButton(
                label: 'Save expense',
                busy: form.saving,
                onTap: save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
