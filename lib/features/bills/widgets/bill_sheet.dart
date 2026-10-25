import 'package:flutter/material.dart';

import '../../../core/db/app_database.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money_input.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/amount_field.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/date_field.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/segmented_pills.dart';
import '../../expenses/data/day_format.dart';
import '../domain/bill_calculations.dart';

class BillFormResult {
  const BillFormResult({
    this.name = '',
    this.amountCents = 0,
    this.nextDueOn,
    this.repeat = BillRepeat.monthly,
    this.delete = false,
  });

  final String name;
  final int amountCents;
  final DateTime? nextDueOn;
  final BillRepeat repeat;
  final bool delete;
}

/// New bill (when [existing] is null) or edit one, with Delete when editing.
Future<BillFormResult?> showBillSheet(
  BuildContext context, {
  required MoneyFormatter money,
  required DateTime now,
  BillRow? existing,
}) => showAdaptiveSheet<BillFormResult>(
  context,
  builder: (context) => _BillForm(money: money, now: now, existing: existing),
);

class _BillForm extends StatefulWidget {
  const _BillForm({required this.money, required this.now, this.existing});

  final MoneyFormatter money;
  final DateTime now;
  final BillRow? existing;

  @override
  State<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends State<_BillForm> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late DateTime _due;
  late BillRepeat _repeat;
  String? _error;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _name = TextEditingController(text: b?.name ?? '');
    _amount = TextEditingController(
      text: b == null ? '' : widget.money.formatPlain(b.amountCents),
    );
    _due = b == null ? widget.now : parseDay(b.nextDueOn);
    _repeat = b == null ? BillRepeat.monthly : BillRepeat.fromDb(b.repeat);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the bill a name.');
      return;
    }
    final cents = parseMoneyInput(
      _amount.text,
      widget.money.currency,
      decimal: widget.money.decimalSeparator,
    );
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Enter the amount of the bill.');
      return;
    }
    Navigator.of(context).pop(
      BillFormResult(
        name: name,
        amountCents: cents,
        nextDueOn: DateTime(_due.year, _due.month, _due.day),
        repeat: _repeat,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final editing = widget.existing != null;
    const repeats = BillRepeat.values;
    return Column(
      key: const ValueKey('bill-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            editing ? 'Edit bill' : 'Add bill',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          key: const ValueKey('bill-name'),
          label: 'Name',
          controller: _name,
          autofocus: !editing,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        AmountField(
          key: const ValueKey('bill-amount'),
          label: 'Amount',
          controller: _amount,
        ),
        const SizedBox(height: 10),
        DateField(
          key: const ValueKey('bill-due'),
          label: 'Next due',
          value: _due,
          firstDate: DateTime(widget.now.year - 1),
          lastDate: DateTime(widget.now.year + 5),
          onChanged: (d) => setState(() => _due = d),
        ),
        const SizedBox(height: 12),
        Text('Repeats', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 6),
        SegmentedPills(
          labels: [for (final r in repeats) r.label.replaceFirst('Every ', '')],
          selected: repeats.indexOf(_repeat),
          onChanged: (i) => setState(() => _repeat = repeats[i]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('bill-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('bill-save'),
          label: editing ? 'Save bill' : 'Add bill',
          onTap: _save,
        ),
        if (editing)
          PillButton(
            key: const ValueKey('bill-delete'),
            label: 'Delete bill',
            style: PillStyle.danger,
            onTap: () =>
                Navigator.of(context).pop(const BillFormResult(delete: true)),
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
