import 'package:flutter/material.dart';

import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_input.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/pill_button.dart';

/// The amount typed: cents, or `0` to remove the allowance.
Future<int?> showAllowanceSheet(
  BuildContext context, {
  required MoneyFormatter money,
  required String name,
  required int? current,
}) => showAdaptiveSheet<int>(
  context,
  builder: (context) =>
      _AllowanceForm(money: money, name: name, current: current),
);

class _AllowanceForm extends StatefulWidget {
  const _AllowanceForm({
    required this.money,
    required this.name,
    required this.current,
  });

  final MoneyFormatter money;
  final String name;
  final int? current;

  @override
  State<_AllowanceForm> createState() => _AllowanceFormState();
}

class _AllowanceFormState extends State<_AllowanceForm> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.current == null
        ? ''
        : widget.money.formatPlain(widget.current!),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final cents = _amount.text.trim().isEmpty
        ? 0
        : parseMoneyInput(
            _amount.text,
            widget.money.currency,
            decimal: widget.money.decimalSeparator,
          );
    if (cents == null) {
      setState(() => _error = 'That is not a valid amount.');
      return;
    }
    Navigator.of(context).pop(cents);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('allowance-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Monthly allowance for ${widget.name}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'From this month on. Leave it empty for no allowance.',
          style: TextStyle(fontSize: 13, color: t.muted),
        ),
        const SizedBox(height: 14),
        AmountField(
          key: const ValueKey('allowance-amount'),
          label: 'Allowance per month',
          controller: _amount,
          autofocus: true,
          onSubmitted: (_) => _save(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('allowance-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('allowance-save'),
          label: 'Save allowance',
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
