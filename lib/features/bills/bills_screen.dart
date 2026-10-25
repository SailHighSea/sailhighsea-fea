import 'package:flutter/material.dart';

import '../../core/widgets/async_placeholder.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/adaptive_grid.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/hero_panel.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../family/member_providers.dart';
import 'bill_providers.dart';
import 'domain/bill_calculations.dart';
import 'widgets/bill_tile.dart';
import 'widgets/bill_sheet.dart';

/// Upcoming bills (Bills, TabBills, DeskBills mockups). Owner and admin add, edit and mark
/// bills paid; everyone sees what is due.
class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(upcomingBillsProvider);
    final bills = async.value;
    final t = context.tokens;
    if (bills == null) {
      return AsyncPlaceholder(
        what: 'bills',
        error: async.hasError ? async.error : null,
        onRetry: () => ref.invalidate(upcomingBillsProvider),
      );
    }
    final money = ref.watch(moneyFormatterProvider);
    final permissions = ref.watch(permissionsProvider);
    final now = ref.watch(clockProvider)();
    final repo = ref.read(billRepositoryProvider);
    final reminders = ref.watch(reminderSettingsProvider);

    Future<void> add() async {
      final r = await showBillSheet(context, money: money, now: now);
      if (r == null || r.delete) return;
      await repo.add(
        name: r.name,
        amountCents: r.amountCents,
        nextDueOn: r.nextDueOn!,
        repeat: r.repeat,
      );
    }

    Future<void> edit(BillRow bill) async {
      final r = await showBillSheet(
        context,
        money: money,
        now: now,
        existing: bill,
      );
      if (r == null) return;
      if (r.delete) {
        await repo.softDelete(bill.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text('Deleted ${bill.name}'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repo.restore(bill.id),
                ),
              ),
            );
        }
        return;
      }
      await repo.update(
        bill.id,
        name: r.name,
        amountCents: r.amountCents,
        nextDueOn: r.nextDueOn!,
        repeat: r.repeat,
      );
    }

    Future<void> markPaid(BillView view) async {
      final before = view.bill;
      await repo.markPaid(before.id);
      if (!context.mounted) return;
      final next = markPaidResult(before, now).nextDueOn;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              before.repeat == 'once'
                  ? '${before.name} marked paid'
                  : '${before.name} marked paid. Next due ${dayMonthLabel(next)}',
            ),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => repo.setDates(
                before.id,
                nextDueOn: before.nextDueOn,
                lastPaidOn: before.lastPaidOn,
              ),
            ),
          ),
        );
    }

    final due = dueBy(bills);
    final list = SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: bills.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                permissions.canManageBills
                    ? 'No bills yet. Tap Add bill to keep track of what is due.'
                    : 'No bills yet. The owner or an admin can add them.',
                key: const ValueKey('bills-empty'),
                style: TextStyle(fontSize: 15, height: 1.35, color: t.muted),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < bills.length; i++) ...[
                  if (i > 0) Divider(color: t.border, height: 1),
                  BillTile(
                    bill: bills[i],
                    money: money,
                    onMarkPaid: permissions.canManageBills
                        ? () => markPaid(bills[i])
                        : null,
                    onTap: permissions.canManageBills
                        ? () => edit(bills[i].bill)
                        : null,
                  ),
                ],
              ],
            ),
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HeroPanel(
          label: due == null ? 'Nothing due' : 'Due by ${dayMonthLabel(due)}',
          value: money.format(totalDue(bills)),
          caption:
              '${bills.length} recurring ${bills.length == 1 ? 'bill' : 'bills'}',
        ),
        const SizedBox(height: 14),
        _ReminderCard(
          enabled: reminders.enabled,
          leadDays: reminders.leadDays,
          onChanged: ref.read(reminderSettingsProvider.notifier).setEnabled,
        ),
      ],
    );

    return AdaptivePage(
      header: PageHeader(
        title: 'Upcoming bills',
        onBackWhenCompact: () => context.go('/home'),
        trailing: permissions.canManageBills
            ? PillButton(
                key: const ValueKey('add-bill-button'),
                label: '+ Add bill',
                height: 44,
                onTap: add,
              )
            : null,
      ),
      children: [
        PrimarySideLayout(
          primary: list,
          side: side,
          sideFirstWhenStacked: true,
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.enabled,
    required this.leadDays,
    required this.onChanged,
  });

  final bool enabled;
  final int leadDays;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: MergeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Remind everyone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      '$leadDays days before each due date',
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('reminders-switch'),
                value: enabled,
                onChanged: onChanged,
                activeTrackColor: t.primary,
                activeThumbColor: t.onPrimary,
                inactiveTrackColor: t.toggleOff,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
