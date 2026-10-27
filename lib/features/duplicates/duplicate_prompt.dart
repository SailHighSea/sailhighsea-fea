import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/app_database.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../expenses/data/day_format.dart';
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'duplicate_finder.dart';
import 'duplicate_providers.dart';

/// Watches for entries that two people probably both added (typically after the family's data
/// arrives from the sheet or server) and asks, one pair at a time, whether they are the same
/// expense. Wraps the app's pages; draws nothing itself.
class DuplicatePrompt extends ConsumerStatefulWidget {
  const DuplicatePrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DuplicatePrompt> createState() => _DuplicatePromptState();
}

class _DuplicatePromptState extends ConsumerState<DuplicatePrompt> {
  bool _showing = false;

  void _maybeAsk() {
    if (_showing || !mounted) return;
    final later = ref.read(duplicatesLaterProvider);
    final pairs = [
      for (final p in ref.read(duplicatePairsProvider))
        if (!later.contains(p.key)) p,
    ];
    if (pairs.isEmpty) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _showing = false;
        return;
      }
      await _ask(pairs.first);
      _showing = false;
      // The next pair, if any.
      if (mounted) _maybeAsk();
    });
  }

  Future<void> _ask(DuplicatePair pair) async {
    final answer = await showDialog<_Answer>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DuplicateDialog(pair: pair),
    );
    if (!mounted) return;
    switch (answer) {
      case _Answer.same:
        await _removeOne(pair);
        await ref.read(duplicateDecisionsProvider.notifier).resolve(pair);
      case _Answer.different:
        await ref.read(duplicateDecisionsProvider.notifier).resolve(pair);
      case _Answer.later || null:
        ref.read(duplicatesLaterProvider.notifier).add(pair.key);
    }
  }

  /// Removes the copy this person may remove: the newer one when both are theirs to change.
  Future<void> _removeOne(DuplicatePair pair) async {
    final canEdit = ref.read(canEditExpenseProvider);
    final candidates = [
      pair.second,
      pair.first,
    ].where((e) => canEdit(e.createdBy)).toList();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (candidates.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'You cannot remove either entry. The person who added it can.',
          ),
        ),
      );
      return;
    }
    final repo = ref.read(expenseRepositoryProvider);
    final gone = candidates.first;
    await repo.softDelete(gone.id);
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Duplicate removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restore(gone.id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(duplicatePairsProvider, (_, _) => _maybeAsk());
    ref.listen(duplicatesLaterProvider, (_, _) {});
    // Also check once when the app opens with pairs already waiting.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
    return widget.child;
  }
}

enum _Answer { same, different, later }

class _DuplicateDialog extends ConsumerWidget {
  const _DuplicateDialog({required this.pair});

  final DuplicatePair pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final money = ref.watch(moneyFormatterProvider);
    final label = ref.watch(addedByLabelProvider);
    Widget entry(ExpenseRow e) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.note.trim().isEmpty ? 'No description' : e.note.trim(),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${money.format(e.amountCents)} · '
            '${DateFormat('MMM d', 'en_US').format(parseDay(e.spentOn))} · '
            'added by ${label(e.createdBy)}',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ],
      ),
    );
    return AlertDialog(
      key: const ValueKey('duplicate-dialog'),
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text('Is this a duplicate?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Two people added what looks like the same expense. ${duplicateWhy(pair.first, pair.second)}',
              style: TextStyle(fontSize: 14, color: t.muted),
            ),
            const SizedBox(height: 12),
            entry(pair.first),
            const SizedBox(height: 8),
            entry(pair.second),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('duplicate-later'),
          onPressed: () => Navigator.pop(context, _Answer.later),
          child: const Text('Ask me later'),
        ),
        TextButton(
          key: const ValueKey('duplicate-different'),
          onPressed: () => Navigator.pop(context, _Answer.different),
          child: const Text('Different, keep both'),
        ),
        FilledButton(
          key: const ValueKey('duplicate-same'),
          onPressed: () => Navigator.pop(context, _Answer.same),
          child: const Text('Same, remove one'),
        ),
      ],
    );
  }
}
