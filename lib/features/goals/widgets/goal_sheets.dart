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
import '../../expenses/data/day_format.dart';

/// What the goal form returns. [delete] is true when the person chose Delete.
class GoalFormResult {
  const GoalFormResult({
    this.name = '',
    this.targetCents = 0,
    this.savedCents = 0,
    this.monthlyCents = 0,
    this.dueOn,
    this.delete = false,
  });

  final String name;
  final int targetCents;
  final int savedCents;
  final int monthlyCents;
  final DateTime? dueOn;
  final bool delete;
}

/// New goal (when [existing] is null) or edit one. Delete is offered when editing.
Future<GoalFormResult?> showGoalSheet(
  BuildContext context, {
  required MoneyFormatter money,
  required DateTime now,
  GoalRow? existing,
}) => showAdaptiveSheet<GoalFormResult>(
  context,
  builder: (context) => _GoalForm(money: money, now: now, existing: existing),
);

class _GoalForm extends StatefulWidget {
  const _GoalForm({required this.money, required this.now, this.existing});

  final MoneyFormatter money;
  final DateTime now;
  final GoalRow? existing;

  @override
  State<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<_GoalForm> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _saved;
  late final TextEditingController _monthly;
  DateTime? _dueOn;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    String show(int? c) =>
        c == null || c == 0 ? '' : widget.money.formatPlain(c);
    _name = TextEditingController(text: g?.name ?? '');
    _target = TextEditingController(text: show(g?.targetCents));
    _saved = TextEditingController(text: show(g?.savedCents));
    _monthly = TextEditingController(text: show(g?.monthlyCents));
    _dueOn = g?.dueOn == null ? null : parseDay(g!.dueOn!);
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    _monthly.dispose();
    super.dispose();
  }

  int? _cents(TextEditingController c, {bool allowEmpty = false}) {
    if (c.text.trim().isEmpty) return allowEmpty ? 0 : null;
    return parseMoneyInput(
      c.text,
      widget.money.currency,
      decimal: widget.money.decimalSeparator,
    );
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the goal a name.');
      return;
    }
    final target = _cents(_target);
    if (target == null || target <= 0) {
      setState(() => _error = 'Enter the amount you are saving for.');
      return;
    }
    final saved = _cents(_saved, allowEmpty: true);
    final monthly = _cents(_monthly, allowEmpty: true);
    if (saved == null || monthly == null) {
      setState(() => _error = 'An amount is not valid.');
      return;
    }
    Navigator.of(context).pop(
      GoalFormResult(
        name: name,
        targetCents: target,
        savedCents: saved,
        monthlyCents: monthly,
        dueOn: _dueOn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final editing = widget.existing != null;
    return Column(
      key: const ValueKey('goal-form'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            editing ? 'Edit goal' : 'New goal',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          key: const ValueKey('goal-name'),
          label: 'Name',
          controller: _name,
          autofocus: !editing,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 10),
        AmountField(
          key: const ValueKey('goal-target'),
          label: 'Target',
          controller: _target,
        ),
        const SizedBox(height: 10),
        AmountField(
          key: const ValueKey('goal-monthly'),
          label: 'Saved each month (optional)',
          controller: _monthly,
        ),
        const SizedBox(height: 10),
        AmountField(
          key: const ValueKey('goal-saved'),
          label: editing ? 'Starting amount' : 'Already saved (optional)',
          controller: _saved,
        ),
        const SizedBox(height: 10),
        DateField(
          key: const ValueKey('goal-due'),
          label: 'Aim to finish by (optional)',
          value: _dueOn,
          firstDate: DateTime(widget.now.year - 1),
          lastDate: DateTime(widget.now.year + 30),
          onChanged: (d) => setState(() => _dueOn = d),
          onClear: () => setState(() => _dueOn = null),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('goal-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('goal-save'),
          label: editing ? 'Save goal' : 'Add goal',
          onTap: _save,
        ),
        if (editing)
          PillButton(
            key: const ValueKey('goal-delete'),
            label: 'Delete goal',
            style: PillStyle.danger,
            onTap: () =>
                Navigator.of(context).pop(const GoalFormResult(delete: true)),
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

class AddMoneyResult {
  const AddMoneyResult(this.goalId, this.cents);
  final String goalId;
  final int cents;
}

/// "Add money": pick the goal and the amount.
Future<AddMoneyResult?> showAddMoneySheet(
  BuildContext context, {
  required MoneyFormatter money,
  required List<GoalRow> goals,
  String? initialGoalId,
}) => showAdaptiveSheet<AddMoneyResult>(
  context,
  builder: (context) =>
      _AddMoney(money: money, goals: goals, initialGoalId: initialGoalId),
);

class _AddMoney extends StatefulWidget {
  const _AddMoney({
    required this.money,
    required this.goals,
    this.initialGoalId,
  });

  final MoneyFormatter money;
  final List<GoalRow> goals;
  final String? initialGoalId;

  @override
  State<_AddMoney> createState() => _AddMoneyState();
}

class _AddMoneyState extends State<_AddMoney> {
  final _amount = TextEditingController();
  late String _goalId = widget.initialGoalId ?? widget.goals.first.id;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final cents = parseMoneyInput(
      _amount.text,
      widget.money.currency,
      decimal: widget.money.decimalSeparator,
    );
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    Navigator.of(context).pop(AddMoneyResult(_goalId, cents));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      key: const ValueKey('add-money'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Add money',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text('Goal', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final g in widget.goals)
              ChoiceChip(
                key: ValueKey('add-money-goal-${g.id}'),
                label: Text(g.name),
                selected: g.id == _goalId,
                onSelected: (_) => setState(() => _goalId = g.id),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
          ],
        ),
        const SizedBox(height: 14),
        AmountField(
          key: const ValueKey('add-money-amount'),
          label: 'Amount',
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
                key: const ValueKey('add-money-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('add-money-save'),
          label: 'Add money',
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
