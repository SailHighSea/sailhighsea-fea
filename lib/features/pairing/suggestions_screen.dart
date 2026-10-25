import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/adaptive_sheet.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/currency.dart';
import '../../core/money/money_format.dart';
import '../../core/money/money_input.dart';
import '../../core/money/money_provider.dart';
import '../../core/sheets_sync/sheets_settings.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/time.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/date_field.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../bills/bill_providers.dart';
import '../expenses/data/day_format.dart';
import '../expenses/expense_providers.dart';
import '../goals/goal_providers.dart';
import 'domain/pairing_codes.dart';
import 'sheets_providers.dart';
import '../../core/google/google_auth.dart';

/// Suggestions (Google Sheets mode). The organiser approves or declines; a member proposes and
/// sees the answer.
class SuggestionsScreen extends ConsumerWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final organiser =
        ref.watch(sheetsSettingsProvider.select((s) => s.role)) ==
        SheetsRole.organiser;
    final all =
        ref.watch(suggestionsListProvider).value ?? const <SuggestionRow>[];
    final pending = all.where((s) => s.status == 'pending').toList();
    final decided = all.where((s) => s.status != 'pending').toList();
    final money = ref.watch(moneyFormatterProvider);
    final names = {
      for (final p
          in ref.watch(sheetPairsProvider).value ?? const <SheetPairRow>[])
        p.memberEmail: p.name,
    };

    return AdaptivePage(
      header: PageHeader(
        title: organiser ? 'Suggestions' : 'My suggestions',
        onBack: () => context.canPop() ? context.pop() : context.go('/family'),
      ),
      children: [
        if (!organiser)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PillButton(
              key: const ValueKey('new-suggestion'),
              label: 'Suggest a change',
              onTap: () => showAdaptiveSheet<void>(
                context,
                builder: (_) => const SuggestionForm(),
              ),
            ),
          ),
        if (all.isEmpty)
          SurfaceCard(
            child: Text(
              organiser
                  ? 'No suggestions yet. When a family member suggests a budget, goal or bill, it shows up here.'
                  : 'You have not suggested anything yet. Suggest a budget, goal or bill and the organiser can approve it.',
              style: TextStyle(fontSize: 14, color: t.muted),
            ),
          ),
        for (final s in pending)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SuggestionCard(
              suggestion: s,
              who: organiser ? (names[s.memberEmail] ?? s.memberEmail) : null,
              money: money,
              actions: organiser ? _Decide(id: s.id) : null,
            ),
          ),
        if (decided.isNotEmpty) ...[
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              'Answered',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final s in decided)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SuggestionCard(
                suggestion: s,
                who: organiser ? (names[s.memberEmail] ?? s.memberEmail) : null,
                money: money,
              ),
            ),
        ],
      ],
    );
  }
}

String describeSuggestion(SuggestionRow s, MoneyFormatter money) {
  final p = jsonDecode(s.payloadJson) as Map<String, dynamic>;
  String c(String k) => p[k] is int ? money.format(p[k] as int) : '?';
  switch (s.kind) {
    case 'budget':
      final m = DateTime.tryParse('${p['month']}');
      final month = m == null ? '' : ' for ${_month(m)}';
      return 'Budget ${c('amountCents')}$month';
    case 'goal':
      final verb = s.action == 'add' ? 'New goal' : 'Change goal';
      final parts = [
        if (p['name'] != null) '${p['name']}',
        if (p['targetCents'] != null) 'target ${c('targetCents')}',
        if (p['monthlyCents'] != null) '${c('monthlyCents')} a month',
      ];
      return '$verb: ${parts.join(', ')}';
    default:
      final verb = s.action == 'add' ? 'New bill' : 'Change bill';
      final parts = [
        if (p['name'] != null) '${p['name']}',
        if (p['amountCents'] != null) c('amountCents'),
        if (p['nextDueOn'] != null) 'due ${p['nextDueOn']}',
      ];
      return '$verb: ${parts.join(', ')}';
  }
}

String _month(DateTime d) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][d.month - 1];

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.money,
    this.who,
    this.actions,
  });
  final SuggestionRow suggestion;
  final MoneyFormatter money;
  final String? who;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final status = switch (suggestion.status) {
      'approved' => ('Approved', t.primary),
      'declined' => ('Declined', t.rose),
      _ => ('Waiting for the organiser', t.muted),
    };
    return SurfaceCard(
      key: ValueKey('suggestion-${suggestion.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (who != null)
            Text(who!, style: TextStyle(fontSize: 13, color: t.muted)),
          Text(
            describeSuggestion(suggestion, money),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          if (suggestion.note.isNotEmpty)
            Text(
              suggestion.note,
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          const SizedBox(height: 4),
          Text(
            status.$1,
            key: ValueKey('status-${suggestion.id}'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: status.$2,
            ),
          ),
          if (actions != null) ...[const SizedBox(height: 8), actions!],
        ],
      ),
    );
  }
}

class _Decide extends ConsumerWidget {
  const _Decide({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        unawaited(ref.read(sheetsSyncProvider.notifier).syncNow());
      } on PairingError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }

    final service = ref.read(suggestionServiceProvider);
    return Row(
      children: [
        Expanded(
          child: PillButton(
            key: ValueKey('approve-$id'),
            label: 'Approve',
            height: 44,
            onTap: () => run(() => service.approve(id)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PillButton(
            key: ValueKey('decline-$id'),
            label: 'Decline',
            height: 44,
            style: PillStyle.outlined,
            onTap: () => run(() => service.decline(id)),
          ),
        ),
      ],
    );
  }
}

/// "Suggest a change": a budget, goal or bill, new or changed.
class SuggestionForm extends ConsumerStatefulWidget {
  const SuggestionForm({super.key});

  @override
  ConsumerState<SuggestionForm> createState() => _SuggestionFormState();
}

class _SuggestionFormState extends ConsumerState<SuggestionForm> {
  String _kind = 'budget';
  String _action = 'add';
  String? _targetId;
  String? _categoryId;
  DateTime? _due;
  String _repeat = 'monthly';
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _monthly = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _monthly.dispose();
    _note.dispose();
    super.dispose();
  }

  int? _cents(TextEditingController c, CurrencyInfo cur, String decimal) =>
      c.text.trim().isEmpty
      ? null
      : parseMoneyInput(c.text, cur, decimal: decimal);

  Future<void> _submit() async {
    final email = ref.read(googleAccountProvider).value?.email;
    if (email == null) {
      setState(() => _error = 'Sign in with Google first.');
      return;
    }
    final money = ref.read(moneyFormatterProvider);
    final cur = money.currency;
    final amount = _cents(_amount, cur, money.decimalSeparator);
    final monthly = _cents(_monthly, cur, money.decimalSeparator);
    if (_amount.text.trim().isNotEmpty && amount == null) {
      setState(() => _error = 'Enter an amount like 12.50.');
      return;
    }
    final now = ref.read(clockProvider)();
    final payload = <String, Object?>{};
    switch (_kind) {
      case 'budget':
        payload['month'] = formatDay(DateTime(now.year, now.month));
        if (_categoryId != null) payload['categoryId'] = _categoryId;
        if (amount != null) payload['amountCents'] = amount;
      case 'goal':
        if (_name.text.trim().isNotEmpty) payload['name'] = _name.text.trim();
        if (amount != null) payload['targetCents'] = amount;
        if (monthly != null) payload['monthlyCents'] = monthly;
      case 'bill':
        if (_name.text.trim().isNotEmpty) payload['name'] = _name.text.trim();
        if (amount != null) payload['amountCents'] = amount;
        if (_due != null) payload['nextDueOn'] = formatDay(_due!);
        if (_action == 'add') payload['repeat'] = _repeat;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(suggestionServiceProvider)
          .create(
            memberEmail: email,
            kind: _kind,
            action: _kind == 'budget' ? 'add' : _action,
            targetId: _action == 'change' ? _targetId : null,
            payload: payload,
            note: _note.text,
          );
      unawaited(ref.read(sheetsSyncProvider.notifier).syncNow());
      if (mounted) Navigator.of(context).pop();
    } on PairingError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final categories =
        ref.watch(categoriesProvider).value ?? const <CategoryRow>[];
    final goals = (ref.watch(goalRowsProvider).value ?? const <GoalRow>[])
        .where((g) => g.deletedAt == null)
        .toList();
    final bills = (ref.watch(billRowsProvider).value ?? const <BillRow>[])
        .where((b) => b.deletedAt == null)
        .toList();
    final change = _action == 'change' && _kind != 'budget';
    final now = ref.watch(clockProvider)();
    ref.watch(appearanceProvider);

    Widget chips(
      List<(String, String)> items,
      String value,
      ValueChanged<String> onPick,
      String prefix,
    ) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (id, label) in items)
          ChoiceChip(
            key: ValueKey('$prefix-$id'),
            label: Text(label),
            selected: value == id,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onPick(id),
          ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'Suggest a change',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
            chips(
              const [('budget', 'Budget'), ('goal', 'Goal'), ('bill', 'Bill')],
              _kind,
              (v) => setState(() {
                _kind = v;
                _targetId = null;
                if (v == 'budget') _action = 'add';
              }),
              'kind',
            ),
            if (_kind != 'budget') ...[
              const SizedBox(height: 8),
              chips(
                const [('add', 'New'), ('change', 'Change an existing one')],
                _action,
                (v) => setState(() {
                  _action = v;
                  _targetId = null;
                }),
                'action',
              ),
            ],
            const SizedBox(height: 12),
            if (change)
              DropdownButtonFormField<String>(
                key: const ValueKey('target'),
                initialValue: _targetId,
                decoration: InputDecoration(
                  labelText: _kind == 'goal' ? 'Which goal' : 'Which bill',
                ),
                items: [
                  if (_kind == 'goal')
                    for (final g in goals)
                      DropdownMenuItem(value: g.id, child: Text(g.name)),
                  if (_kind == 'bill')
                    for (final b in bills)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => _targetId = v),
              ),
            if (_kind == 'budget')
              DropdownButtonFormField<String?>(
                key: const ValueKey('budget-category'),
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Budget for'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Everything (overall)'),
                  ),
                  for (final c in categories)
                    DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            if (_kind != 'budget') ...[
              const SizedBox(height: 8),
              AppTextField(
                label: change ? 'New name (optional)' : 'Name',
                controller: _name,
              ),
            ],
            const SizedBox(height: 8),
            AmountField(
              label: switch (_kind) {
                'budget' => 'Monthly amount',
                'goal' => change ? 'New target (optional)' : 'Target',
                _ => change ? 'New amount (optional)' : 'Amount',
              },
              controller: _amount,
            ),
            if (_kind == 'goal') ...[
              const SizedBox(height: 8),
              AmountField(
                label: 'Saved per month (optional)',
                controller: _monthly,
              ),
            ],
            if (_kind == 'bill') ...[
              const SizedBox(height: 8),
              DateField(
                label: change ? 'New due date (optional)' : 'Next due date',
                value: _due,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
                onChanged: (d) => setState(() => _due = d),
              ),
              if (!change) ...[
                const SizedBox(height: 8),
                chips(
                  const [
                    ('monthly', 'Every month'),
                    ('weekly', 'Every week'),
                    ('yearly', 'Every year'),
                    ('once', 'Once'),
                  ],
                  _repeat,
                  (v) => setState(() => _repeat = v),
                  'repeat',
                ),
              ],
            ],
            const SizedBox(height: 8),
            AppTextField(label: 'Why? (optional)', controller: _note),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('suggestion-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ],
            const SizedBox(height: 12),
            PillButton(
              key: const ValueKey('send-suggestion'),
              label: 'Send suggestion',
              busy: _busy,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
