import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/db/ids.dart';
import '../bills/data/bill_repository.dart';
import '../bills/domain/bill_calculations.dart';
import '../budgets/data/budget_repository.dart';
import '../goals/data/goal_repository.dart';
import 'domain/pairing_codes.dart';

/// A member proposes a budget, goal or bill; the organiser approves or declines it.
class SuggestionService {
  SuggestionService(
    this._db, {
    required this.budgets,
    required this.goals,
    required this.bills,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BudgetRepository budgets;
  final GoalRepository goals;
  final BillRepository bills;
  final DateTime Function() _clock;

  /// Member: records a suggestion locally. The sync pushes it to the member's sheet.
  Future<String> create({
    required String memberEmail,
    required String kind,
    required String action,
    String? targetId,
    required Map<String, Object?> payload,
    String note = '',
  }) async {
    _validate(kind, action, targetId, payload);
    final id = newId();
    final now = _clock();
    await _db
        .into(_db.suggestions)
        .insert(
          SuggestionsCompanion.insert(
            id: id,
            memberEmail: memberEmail,
            kind: kind,
            action: action,
            targetId: Value(targetId),
            payloadJson: jsonEncode(payload),
            note: Value(note.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// A new item needs all its fields; a change needs the item and at least one valid field.
  void _validate(
    String kind,
    String action,
    String? targetId,
    Map<String, Object?> p,
  ) {
    final isChange = action == 'change';
    if (action != 'add' && !isChange) {
      throw const PairingError('Unknown kind of suggestion.');
    }
    if (isChange &&
        kind != 'budget' &&
        (targetId == null || targetId.isEmpty)) {
      throw const PairingError('Choose what to change.');
    }
    void cents(String k) {
      if (!p.containsKey(k) && isChange) return;
      if (p[k] is! int || (p[k]! as int) <= 0) {
        throw const PairingError('Enter an amount above zero.');
      }
    }

    void text(String k) {
      if (!p.containsKey(k) && isChange) return;
      if (p[k] is! String || (p[k]! as String).trim().isEmpty) {
        throw const PairingError('Enter a name.');
      }
    }

    switch (kind) {
      case 'budget':
        // A budget is identified by its month (and category), so adding and changing are the same.
        if (p['amountCents'] is! int || (p['amountCents']! as int) <= 0) {
          throw const PairingError('Enter an amount above zero.');
        }
        final m = p['month'];
        if (m is! String || !RegExp(r'^\d{4}-\d{2}-01$').hasMatch(m)) {
          throw const PairingError('Choose a month.');
        }
      case 'goal':
        text('name');
        cents('targetCents');
        if (isChange && p.isEmpty) {
          throw const PairingError('Change at least one thing.');
        }
      case 'bill':
        text('name');
        cents('amountCents');
        if (!p.containsKey('nextDueOn') && !isChange ||
            p['nextDueOn'] != null && p['nextDueOn'] is! String) {
          throw const PairingError('Choose a due date.');
        }
        if (isChange && p.isEmpty) {
          throw const PairingError('Change at least one thing.');
        }
      default:
        throw const PairingError('Unknown kind of suggestion.');
    }
  }

  /// Organiser: applies the suggestion to the household's data and marks it approved.
  Future<void> approve(String id) async {
    final s = await (_db.select(
      _db.suggestions,
    )..where((x) => x.id.equals(id))).getSingle();
    if (s.status != 'pending') return;
    final p = jsonDecode(s.payloadJson) as Map<String, dynamic>;
    switch (s.kind) {
      case 'budget':
        await budgets.setBudget(
          DateTime.parse(p['month'] as String),
          p['categoryId'] as String?,
          p['amountCents'] as int,
        );
      case 'goal':
        if (s.action == 'add') {
          await goals.add(
            name: p['name'] as String,
            targetCents: p['targetCents'] as int,
            monthlyCents: (p['monthlyCents'] as int?) ?? 0,
            dueOn: p['dueOn'] == null
                ? null
                : DateTime.parse(p['dueOn'] as String),
          );
        } else {
          final g = await (_db.select(
            _db.goals,
          )..where((x) => x.id.equals(s.targetId!))).getSingleOrNull();
          if (g == null) {
            throw const PairingError('That goal no longer exists.');
          }
          await goals.update(
            g.id,
            name: (p['name'] as String?) ?? g.name,
            targetCents: (p['targetCents'] as int?) ?? g.targetCents,
            savedCents: g.savedCents,
            monthlyCents: (p['monthlyCents'] as int?) ?? g.monthlyCents,
            dueOn: p['dueOn'] != null
                ? DateTime.parse(p['dueOn'] as String)
                : (g.dueOn == null ? null : DateTime.parse(g.dueOn!)),
          );
        }
      case 'bill':
        final repeat = BillRepeat.fromDb((p['repeat'] as String?) ?? 'monthly');
        if (s.action == 'add') {
          await bills.add(
            name: p['name'] as String,
            amountCents: p['amountCents'] as int,
            nextDueOn: DateTime.parse(p['nextDueOn'] as String),
            repeat: repeat,
          );
        } else {
          final b = await (_db.select(
            _db.bills,
          )..where((x) => x.id.equals(s.targetId!))).getSingleOrNull();
          if (b == null) {
            throw const PairingError('That bill no longer exists.');
          }
          await bills.update(
            b.id,
            name: (p['name'] as String?) ?? b.name,
            amountCents: (p['amountCents'] as int?) ?? b.amountCents,
            nextDueOn: DateTime.parse(
              (p['nextDueOn'] as String?) ?? b.nextDueOn,
            ),
            repeat: p['repeat'] == null ? BillRepeat.fromDb(b.repeat) : repeat,
          );
        }
    }
    await _decide(id, 'approved');
  }

  Future<void> decline(String id) => _decide(id, 'declined');

  Future<void> _decide(String id, String status) =>
      (_db.update(
        _db.suggestions,
      )..where((x) => x.id.equals(id) & x.status.equals('pending'))).write(
        SuggestionsCompanion(status: Value(status), updatedAt: Value(_clock())),
      );
}
