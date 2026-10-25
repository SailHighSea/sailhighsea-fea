import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_input.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/pill_button.dart';

class NewCategory {
  const NewCategory(this.name, this.budgetCents);
  final String name;
  final int? budgetCents;
}

/// "+ New category": a name and, optionally, a monthly budget for it.
Future<NewCategory?> showNewCategorySheet(
  BuildContext context, {
  required MoneyFormatter money,
}) => showAdaptiveSheet<NewCategory>(
  context,
  builder: (context) => _NewCategory(money: money),
);

class _NewCategory extends StatefulWidget {
  const _NewCategory({required this.money});

  final MoneyFormatter money;

  @override
  State<_NewCategory> createState() => _NewCategoryState();
}

class _NewCategoryState extends State<_NewCategory> {
  final _name = TextEditingController();
  final _budget = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }
    int? cents;
    if (_budget.text.trim().isNotEmpty) {
      cents = parseMoneyInput(
        _budget.text,
        widget.money.currency,
        decimal: widget.money.decimalSeparator,
      );
      if (cents == null) {
        setState(() => _error = 'The budget is not a valid amount.');
        return;
      }
    }
    Navigator.of(context).pop(NewCategory(name, cents == 0 ? null : cents));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('new-category'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'New category',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          key: const ValueKey('new-category-name'),
          label: 'Name',
          controller: _name,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        AppTextField(
          key: const ValueKey('new-category-budget'),
          label: 'Monthly budget (optional)',
          controller: _budget,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('new-category-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('new-category-save'),
          label: 'Add category',
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
