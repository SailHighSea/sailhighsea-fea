import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_input.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/pill_button.dart';

/// What the income sheet returns. A `null` amount means that field was left as it was.
class IncomeSheetResult {
  const IncomeSheetResult({this.incomeCents, this.from, this.totalCents});

  final int? incomeCents;

  /// The month the income applies from.
  final DateTime? from;
  final int? totalCents;
}

/// "Monthly income" and "Total savings today", in one sheet.
Future<IncomeSheetResult?> showIncomeSheet(
  BuildContext context, {
  required MoneyFormatter money,
  required DateTime month,
  int? incomeCents,
  int? totalCents,
}) => showAdaptiveSheet<IncomeSheetResult>(
  context,
  builder: (context) => _IncomeForm(
    money: money,
    month: month,
    incomeCents: incomeCents,
    totalCents: totalCents,
  ),
);

class _IncomeForm extends StatefulWidget {
  const _IncomeForm({
    required this.money,
    required this.month,
    this.incomeCents,
    this.totalCents,
  });

  final MoneyFormatter money;
  final DateTime month;
  final int? incomeCents;
  final int? totalCents;

  @override
  State<_IncomeForm> createState() => _IncomeFormState();
}

class _IncomeFormState extends State<_IncomeForm> {
  late final TextEditingController _income;
  late final TextEditingController _total;
  bool _fromNext = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    String show(int? c) =>
        c == null || c == 0 ? '' : widget.money.formatPlain(c);
    _income = TextEditingController(text: show(widget.incomeCents));
    _total = TextEditingController(text: show(widget.totalCents));
  }

  @override
  void dispose() {
    _income.dispose();
    _total.dispose();
    super.dispose();
  }

  int? _cents(TextEditingController c) => parseMoneyInput(
    c.text,
    widget.money.currency,
    decimal: widget.money.decimalSeparator,
  );

  void _save() {
    int? income;
    int? total;
    if (_income.text.trim().isNotEmpty) {
      income = _cents(_income);
      if (income == null) {
        setState(() => _error = 'The income is not a valid amount.');
        return;
      }
    }
    if (_total.text.trim().isNotEmpty) {
      total = _cents(_total);
      if (total == null) {
        setState(() => _error = 'The total savings is not a valid amount.');
        return;
      }
    }
    if (income == null && total == null) {
      setState(
        () => _error = 'Enter your income, your total savings, or both.',
      );
      return;
    }
    Navigator.of(context).pop(
      IncomeSheetResult(
        incomeCents: income,
        from: _fromNext
            ? DateTime(widget.month.year, widget.month.month + 1)
            : DateTime(widget.month.year, widget.month.month),
        totalCents: total,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fmt = DateFormat('MMMM', 'en_US');
    return Column(
      key: const ValueKey('income-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Income and savings',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AmountField(
          key: const ValueKey('income-amount'),
          label: 'Monthly income, after tax',
          controller: _income,
          autofocus: true,
        ),
        const SizedBox(height: 10),
        Text('Applies from', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('income-from-this'),
              label: Text(fmt.format(widget.month)),
              selected: !_fromNext,
              onSelected: (_) => setState(() => _fromNext = false),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
            ChoiceChip(
              key: const ValueKey('income-from-next'),
              label: Text(
                fmt.format(DateTime(widget.month.year, widget.month.month + 1)),
              ),
              selected: _fromNext,
              onSelected: (_) => setState(() => _fromNext = true),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ),
        const SizedBox(height: 14),
        AmountField(
          key: const ValueKey('income-total'),
          label: 'Total savings today (bank and cash)',
          controller: _total,
        ),
        const SizedBox(height: 8),
        Text(
          'Both stay on this device and are only seen by you. They are in your backup file.',
          style: TextStyle(fontSize: 13, color: t.muted),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('income-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('income-save'),
          label: 'Save',
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
