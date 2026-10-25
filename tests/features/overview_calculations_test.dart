import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/features/budgets/domain/budget_calculations.dart';
import 'package:family_expenses/features/family/domain/visibility.dart';
import 'package:family_expenses/features/family/domain/permissions.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/overview/domain/overview_calculations.dart';
import 'package:family_expenses/features/overview/overview_providers.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 23, 12);

ExpenseRow _e(
  String day,
  int cents,
  String by, {
  String category = 'default-food',
  DateTime? deleted,
}) => ExpenseRow(
  id: '$day-$cents-$by-$category',
  householdId: 'h',
  amountCents: cents,
  categoryId: category,
  note: '',
  spentOn: day,
  createdBy: by == 'null' ? null : by,
  receiptPath: null,
  updatedAt: DateTime(2026, 10, 1),
  deletedAt: deleted,
  dirty: false,
);

MemberRow _m(String id, String name, String role, {int day = 1}) => MemberRow(
  householdId: 'h',
  userId: id,
  role: role,
  displayName: name,
  joinedAt: DateTime(2026, 9, day),
  visibility: 'household',
);

CategoryRow _c(String id, String name) => CategoryRow(
  id: id,
  householdId: 'h',
  name: name,
  color: id.replaceFirst('default-', ''),
  icon: null,
  sort: 0,
  updatedAt: DateTime(2026),
  deletedAt: null,
  dirty: false,
);

final _members = [
  _m('u-you', 'Olivia', 'owner'),
  _m('u-maya', 'Maya', 'admin', day: 2),
  _m('u-sam', 'Sam', 'viewer', day: 3),
];
final _categories = [
  _c('default-food', 'Food'),
  _c('default-fun', 'Fun'),
  _c('default-other', 'Other'),
];

OverviewData _build(
  List<ExpenseRow> expenses, {
  List<MemberRow>? members,
  String? me = 'u-you',
  DateTime? month,
  DateTime? now,
  int budget = 250000,
  Map<String, int> allowances = const {},
}) => buildOverview(
  month: month ?? DateTime(2026, 10),
  now: now ?? _now,
  expenses: expenses,
  categories: _categories,
  members: members ?? _members,
  currentUserId: me,
  budgetCents: budget,
  allowances: allowances,
);

void main() {
  group('shares', () {
    test('always add up to 100', () {
      for (final amounts in [
        [1, 1, 1],
        [1, 1, 1, 1, 1, 1, 1],
        [3333, 3333, 3334],
        [61200, 49400, 21600],
        [1, 0, 0],
        [2, 1],
        [999, 1],
      ]) {
        expect(
          sharePercents(amounts).fold<int>(0, (a, b) => a + b),
          100,
          reason: '$amounts',
        );
      }
    });
    test(
      'thirds: 34, 33, 33 and the biggest remainder wins the extra point',
      () {
        expect(sharePercents([1, 1, 1]), [34, 33, 33]);
        expect(sharePercents([61200, 49400, 21600]), [46, 38, 16]);
        expect(sharePercents([1, 0, 0]), [100, 0, 0]);
      },
    );
    test('nothing spent is zeros, not a division by zero', () {
      expect(sharePercents([0, 0]), [0, 0]);
      expect(sharePercents(const []), isEmpty);
    });
  });

  group('per person', () {
    test('totals, shares and order for the month', () {
      final d = _build([
        _e('2026-10-03', 61200, 'u-you'),
        _e('2026-10-05', 28400, 'u-maya', category: 'default-fun'),
        _e('2026-10-12', 21000, 'u-maya'),
        _e('2026-10-20', 21600, 'u-sam', category: 'default-other'),
        _e('2026-09-30', 99999, 'u-sam'),
        _e('2026-11-01', 99999, 'u-sam'),
        _e('2026-10-21', 5000, 'u-sam', deleted: DateTime(2026, 10, 22)),
      ]);
      expect(d.totalCents, 61200 + 28400 + 21000 + 21600);
      expect(d.people.map((p) => p.name), ['You', 'Maya', 'Sam']);
      expect(d.people.map((p) => p.spentCents), [61200, 49400, 21600]);
      expect(
        d.people.map((p) => p.sharePercent).fold<int>(0, (a, b) => a + b),
        100,
      );
      expect(d.people.map((p) => p.sharePercent), [46, 38, 16]);
      expect(
        d.people.first.isYou,
        isTrue,
        reason: 'the signed-in person reads "You"',
      );
      expect(d.people.last.expenseCount, 1);
    });

    test('top category, today and this week', () {
      final d = _build([
        _e('2026-10-23', 1000, 'u-maya', category: 'default-fun'),
        _e('2026-10-22', 500, 'u-maya', category: 'default-food'),
        _e('2026-10-10', 300, 'u-maya', category: 'default-food'),
        _e('2026-10-17', 200, 'u-maya', category: 'default-food'),
        _e('2026-10-16', 900, 'u-maya', category: 'default-food'),
      ]);
      final maya = d.people.firstWhere((p) => p.name == 'Maya');
      expect(maya.topCategoryName, 'Food');
      expect(maya.todayCents, 1000);
      expect(maya.weekCents, 1000 + 500 + 200, reason: 'Oct 17 to 23');
      expect(maya.spentCents, 2900);
    });

    test('the week reaches into the month before', () {
      final d = _build(
        [_e('2026-10-30', 100, 'u-sam'), _e('2026-11-02', 300, 'u-sam')],
        month: DateTime(2026, 11),
        now: DateTime(2026, 11, 3),
      );
      final sam = d.people.firstWhere((p) => p.name == 'Sam');
      expect(sam.spentCents, 300, reason: 'October is not in November');
      expect(sam.weekCents, 400, reason: 'Oct 28 to Nov 3 counts both');
      expect(
        overviewRangeStart(DateTime(2026, 11), DateTime(2026, 11, 3)),
        DateTime(2026, 10, 28),
      );
    });

    test('a past month measures today and the week to its last day', () {
      final d = _build([
        _e('2026-09-30', 700, 'u-sam'),
        _e('2026-09-10', 100, 'u-sam'),
      ], month: DateTime(2026, 9));
      final sam = d.people.firstWhere((p) => p.name == 'Sam');
      expect(sam.todayCents, 700);
      expect(sam.weekCents, 700);
    });

    test('everyone is listed, even with nothing spent', () {
      final d = _build([_e('2026-10-03', 100, 'u-you')]);
      expect(d.people.map((p) => p.name), containsAll(['You', 'Maya', 'Sam']));
      expect(d.people.firstWhere((p) => p.name == 'Sam').spentCents, 0);
      expect(
        d.people.firstWhere((p) => p.name == 'Sam').topCategoryName,
        isNull,
      );
    });

    test('ties are ordered by name', () {
      final d = _build(
        [_e('2026-10-03', 100, 'u-sam'), _e('2026-10-03', 100, 'u-maya')],
        members: [_members[1], _members[2]],
        me: 'u-you',
      );
      expect(d.people.map((p) => p.name), ['Maya', 'Sam']);
    });

    test('no expenses: all zero, shares zero', () {
      final d = _build(const []);
      expect(d.totalCents, 0);
      expect(
        d.people.every((p) => p.sharePercent == 0 && p.spentCents == 0),
        isTrue,
      );
      expect(d.percentUsed, 0);
    });

    test('a household of one shows only that person', () {
      final d = _build(
        [_e('2026-10-03', 500, 'u-you')],
        members: [_members.first],
      );
      expect(d.people, hasLength(1));
      expect(d.people.single.sharePercent, 100);
    });

    test('entries made before accounts belong to the signed-in person', () {
      final d = _build([
        _e('2026-10-03', 500, 'You'),
        _e('2026-10-04', 300, 'null'),
      ]);
      expect(d.people.first.name, 'You');
      expect(d.people.first.spentCents, 800);
      expect(d.people.where((p) => p.name == 'Former member (left)'), isEmpty);
    });

    test('someone who left keeps their past spending, labelled', () {
      final d = _build([
        _e('2026-10-03', 900, 'u-gone'),
        _e('2026-10-04', 100, 'u-you'),
      ]);
      final gone = d.people.firstWhere((p) => p.hasLeft);
      expect(gone.name, 'Former member (left)');
      expect(gone.spentCents, 900);
      expect(gone.role, isNull);
      expect(d.people.first, gone, reason: 'biggest spender first');
      expect(d.totalCents, 1000);
    });

    test('someone who left with nothing this month is not listed', () {
      final d = _build([
        _e('2026-09-03', 900, 'u-gone'),
      ], month: DateTime(2026, 10));
      expect(d.people.where((p) => p.hasLeft), isEmpty);
    });
  });

  group('allowances and the family total', () {
    test('left, over and fractions', () {
      final d = _build(
        [_e('2026-10-03', 15000, 'u-sam'), _e('2026-10-04', 5000, 'u-maya')],
        allowances: {'u-sam': 10000, 'u-maya': 20000},
      );
      final sam = d.people.firstWhere((p) => p.name == 'Sam');
      expect(sam.overAllowance, isTrue);
      expect(sam.allowanceLeftCents, -5000);
      expect(sam.allowanceFraction, 1.0);
      final maya = d.people.firstWhere((p) => p.name == 'Maya');
      expect(maya.overAllowance, isFalse);
      expect(maya.allowanceLeftCents, 15000);
      expect(maya.allowanceFraction, 0.25);
      expect(
        d.people.firstWhere((p) => p.name == 'You').allowanceCents,
        isNull,
      );
    });

    test('family budget, left and percent', () {
      final d = _build([_e('2026-10-03', 184200, 'u-you')]);
      expect(d.leftCents, 65800);
      expect(d.percentUsed, 74);
      expect(d.isOver, isFalse);
      expect(_build([_e('2026-10-03', 300000, 'u-you')]).isOver, isTrue);
    });

    BudgetRow row(
      String id,
      String month,
      String? user,
      int cents, {
      DateTime? deleted,
    }) => BudgetRow(
      id: id,
      householdId: 'h',
      month: month,
      categoryId: null,
      userId: user,
      amountCents: cents,
      updatedAt: DateTime(2026, 1, 1),
      deletedAt: deleted,
      dirty: false,
    );

    test('allowances carry over from earlier months and are kept apart from budgets', () {
      final rows = [
        row('a', '2026-08-01', 'u-sam', 10000),
        row('b', '2026-09-01', 'u-sam', 15000),
        row('c', '2026-10-01', 'u-maya', 30000, deleted: DateTime(2026, 10, 2)),
        row('d', '2026-08-01', 'u-maya', 30000),
        row('e', '2026-10-01', null, 250000),
        row('f', '2026-11-01', 'u-sam', 99999),
      ];
      final oct = effectiveAllowances(rows, DateTime(2026, 10));
      expect(oct, {
        'u-sam': 15000,
      }, reason: 'Maya\'s was deleted from October on');
      expect(effectiveBudgets(rows, DateTime(2026, 10)), {
        null: 250000,
      }, reason: 'allowances never count as the household budget');
      expect(
        allowanceId(DateTime(2026, 10, 9), 'u-sam'),
        'b:2026-10:user:u-sam',
      );
    });
  });

  group('who is shown', () {
    final alone = ExpenseRow(
      id: 'x',
      householdId: 'h',
      amountCents: 1,
      categoryId: 'c',
      note: '',
      spentOn: '2026-10-01',
      createdBy: 'You',
      receiptPath: null,
      updatedAt: DateTime(2026),
      deletedAt: null,
      dirty: false,
    );

    test(
      'addedBy maps entries from before accounts to the signed-in person',
      () {
        expect(addedBy(alone, 'u-you', 'u-you'), isTrue);
        expect(addedBy(alone, 'u-maya', 'u-you'), isFalse);
        expect(addedBy(alone, 'u-you', null), isFalse);
        expect(
          addedBy(_e('2026-10-01', 1, 'u-maya'), 'u-maya', 'u-you'),
          isTrue,
        );
      },
    );
    test('forMember narrows a list, null keeps everything', () {
      final all = [
        _e('2026-10-01', 1, 'u-you'),
        _e('2026-10-01', 2, 'u-maya'),
        alone,
      ];
      expect(forMember(all, null, 'u-you'), all);
      expect(forMember(all, 'u-maya', 'u-you').map((e) => e.amountCents), [2]);
      expect(forMember(all, 'u-you', 'u-you').map((e) => e.amountCents), [
        1,
        1,
      ]);
    });
  });

  group('permissions', () {
    test(
      'only owner and admin choose what a member sees, never for themselves',
      () {
        const owner = Permissions(Role.owner);
        const admin = Permissions(Role.admin);
        const editor = Permissions(Role.editor);
        const viewer = Permissions(Role.viewer);
        expect(owner.canSetVisibility(Role.viewer, isSelf: false), isTrue);
        expect(owner.canSetVisibility(Role.editor, isSelf: false), isTrue);
        expect(admin.canSetVisibility(Role.viewer, isSelf: false), isTrue);
        expect(
          owner.canSetVisibility(Role.admin, isSelf: false),
          isFalse,
          reason: 'admins always see everything',
        );
        expect(owner.canSetVisibility(Role.owner, isSelf: true), isFalse);
        expect(owner.canSetVisibility(Role.viewer, isSelf: true), isFalse);
        expect(editor.canSetVisibility(Role.viewer, isSelf: false), isFalse);
        expect(viewer.canSetVisibility(Role.editor, isSelf: false), isFalse);
      },
    );

    test('the overview is for owner and admin, and for others only with household visibility', () {
      for (final role in [Role.owner, Role.admin]) {
        final p = Permissions(role);
        expect(p.canSeeEveryone(MemberVisibility.household), isTrue);
        expect(
          p.canSeeEveryone(MemberVisibility.own),
          isTrue,
          reason: 'never hidden from managers',
        );
      }
      for (final role in [Role.editor, Role.viewer]) {
        final p = Permissions(role);
        expect(p.canSeeEveryone(MemberVisibility.household), isTrue);
        expect(p.canSeeEveryone(MemberVisibility.own), isFalse);
      }
    });

    test('allowances are set by owner and admin only', () {
      expect(const Permissions(Role.owner).canSetAllowances, isTrue);
      expect(const Permissions(Role.admin).canSetAllowances, isTrue);
      expect(const Permissions(Role.editor).canSetAllowances, isFalse);
      expect(const Permissions(Role.viewer).canSetAllowances, isFalse);
    });

    test('unknown visibility from a newer server falls back to household', () {
      expect(MemberVisibility.fromDb('something'), MemberVisibility.household);
      expect(MemberVisibility.fromDb(null), MemberVisibility.household);
      expect(MemberVisibility.fromDb('own'), MemberVisibility.own);
    });
  });
}
