import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/db/app_database.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_input.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/pill_button.dart';

/// What the person typed in "Edit budgets": the overall amount and one per category. `null`
/// means "no budget".
class BudgetEdits {
  const BudgetEdits({required this.overall, required this.byCategory});

  final int? overall;
  final Map<String, int?> byCategory;
}

Future<BudgetEdits?> showEditBudgetsSheet(
  BuildContext context, {
  required MoneyFormatter money,
  required String monthLabel,
  required int? overallCents,
  required List<CategoryRow> categories,
  required Map<String, int> categoryBudgets,
}) {
  return showAdaptiveSheet<BudgetEdits>(
    context,
    builder: (context) => _EditBudgets(
      money: money,
      monthLabel: monthLabel,
      overallCents: overallCents,
      categories: categories,
      categoryBudgets: categoryBudgets,
    ),
  );
}

class _EditBudgets extends StatefulWidget {
  const _EditBudgets({
    required this.money,
    required this.monthLabel,
    required this.overallCents,
    required this.categories,
    required this.categoryBudgets,
  });

  final MoneyFormatter money;
  final String monthLabel;
  final int? overallCents;
  final List<CategoryRow> categories;
  final Map<String, int> categoryBudgets;

  @override
  State<_EditBudgets> createState() => _EditBudgetsState();
}

class _EditBudgetsState extends State<_EditBudgets> {
  late final TextEditingController _overall;
  late final Map<String, TextEditingController> _byCategory;
  String? _error;

  @override
  void initState() {
    super.initState();
    String show(int? cents) =>
        cents == null ? '' : widget.money.formatPlain(cents);
    _overall = TextEditingController(text: show(widget.overallCents));
    _byCategory = {
      for (final c in widget.categories)
        c.id: TextEditingController(text: show(widget.categoryBudgets[c.id])),
    };
  }

  @override
  void dispose() {
    _overall.dispose();
    for (final c in _byCategory.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// `(ok, value)`: blank is "no budget", something unreadable is an error.
  (bool, int?) _read(TextEditingController c) {
    final text = c.text.trim();
    if (text.isEmpty) return (true, null);
    final cents = parseMoneyInput(
      text,
      widget.money.currency,
      decimal: widget.money.decimalSeparator,
    );
    if (cents == null) return (false, null);
    return (true, cents == 0 ? null : cents);
  }

  void _save() {
    final overall = _read(_overall);
    if (!overall.$1) {
      setState(() => _error = 'The overall budget is not a valid amount.');
      return;
    }
    final byCategory = <String, int?>{};
    for (final c in widget.categories) {
      final r = _read(_byCategory[c.id]!);
      if (!r.$1) {
        setState(() => _error = '${c.name} is not a valid amount.');
        return;
      }
      byCategory[c.id] = r.$2;
    }
    Navigator.of(context)
        .pop(BudgetEdits(overall: overall.$2, byCategory: byCategory));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    const keyboard = TextInputType.numberWithOptions(decimal: true);
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Column(
      key: const ValueKey('edit-budgets'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Edit budgets',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'From ${widget.monthLabel} on. Earlier months keep their own. Leave a box empty for no budget.',
          style: TextStyle(fontSize: 13, height: 1.35, color: t.muted),
        ),
        const SizedBox(height: 14),
        AppTextField(
          key: const ValueKey('budget-overall'),
          label: 'Overall monthly budget',
          controller: _overall,
          keyboardType: keyboard,
          inputFormatters: formatters,
        ),
        const SizedBox(height: 14),
        Text(
          'By category',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        for (final c in widget.categories) ...[
          AppTextField(
            key: ValueKey('budget-${c.id}'),
            label: c.name,
            controller: _byCategory[c.id]!,
            keyboardType: keyboard,
            inputFormatters: formatters,
          ),
          const SizedBox(height: 8),
        ],
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const ValueKey('budget-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        PillButton(
          key: const ValueKey('budget-save'),
          label: 'Save budgets',
          onTap: _save,
        ),
        PillButton(
          label: 'Cancel',
          style: PillStyle.text,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
