import 'package:family_expenses/features/family/domain/permissions.dart';
import 'package:family_expenses/features/family/domain/role.dart';
import 'package:family_expenses/features/family/invite_code_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('roles', () {
    test(
      'database values round trip and unknown values get the least access',
      () {
        for (final role in Role.values) {
          expect(Role.fromDb(role.dbValue), role);
        }
        expect(Role.fromDb('superuser'), Role.viewer);
      },
    );

    test('labels match the mockups', () {
      expect(Role.editor.label, 'Can edit');
      expect(Role.viewer.label, 'View only');
    });

    test(
      'owner is never handed out and invites carry only editor or view only',
      () {
        expect(Role.assignable, [Role.admin, Role.editor, Role.viewer]);
        expect(Role.invitable, [Role.editor, Role.viewer]);
      },
    );
  });

  group('permissions mirror the server policies', () {
    final matrix = <Role, Map<String, bool>>{
      Role.owner: {
        'expenses': true,
        'manage': true,
        'invite': true,
        'transfer': true,
      },
      Role.admin: {
        'expenses': true,
        'manage': true,
        'invite': true,
        'transfer': false,
      },
      Role.editor: {
        'expenses': true,
        'manage': false,
        'invite': false,
        'transfer': false,
      },
      Role.viewer: {
        'expenses': false,
        'manage': false,
        'invite': false,
        'transfer': false,
      },
    };

    for (final entry in matrix.entries) {
      test(entry.key.label, () {
        final p = Permissions(entry.key);
        final want = entry.value;
        expect(p.canWriteExpenses, want['expenses']);
        expect(p.canManageCategories, want['manage']);
        expect(p.canManageBudgets, want['manage']);
        expect(p.canManageGoals, want['manage']);
        expect(p.canManageBills, want['manage']);
        expect(p.canManageMembers, want['manage']);
        expect(p.canInvite, want['invite']);
        expect(p.canTransferOwnership, want['transfer']);
        expect(p.canDeleteHousehold, want['transfer']);
      });
    }

    test('only owner and admin change roles or remove, never the owner or themselves', () {
      for (final actor in Role.values) {
        final p = Permissions(actor);
        final manager = actor == Role.owner || actor == Role.admin;
        for (final target in Role.values) {
          final expected = manager && target != Role.owner;
          expect(
            p.canChangeRoleOf(target, isSelf: false),
            expected,
            reason: '${actor.name} changing ${target.name}',
          );
          expect(p.canRemove(target, isSelf: false), expected);
          expect(p.canChangeRoleOf(target, isSelf: true), isFalse);
          expect(p.canRemove(target, isSelf: true), isFalse);
        }
      }
    });

    test('everyone but the owner can leave', () {
      expect(const Permissions(Role.owner).canLeave(isSelf: true), isFalse);
      for (final role in [Role.admin, Role.editor, Role.viewer]) {
        expect(Permissions(role).canLeave(isSelf: true), isTrue);
        expect(Permissions(role).canLeave(isSelf: false), isFalse);
      }
    });

    test('local-only use is the owner', () {
      expect(Permissions.local.canWriteExpenses, isTrue);
      expect(Permissions.local.role, Role.owner);
    });
  });

  group('invite code input', () {
    test('only the 32 safe characters are kept', () {
      expect(inviteCodeAlphabet.length, 32);
      for (final c in '0O1I'.split('')) {
        expect(inviteCodeAlphabet.contains(c), isFalse);
      }
      expect(cleanInviteCode('k7m-4qx9'), 'K7M4QX9');
      expect(cleanInviteCode('0O1I-abcd'), 'ABCD');
    });

    test('at most eight characters, dash after four', () {
      expect(cleanInviteCode('ABCDEFGHJK'), 'ABCDEFGH');
      expect(formatInviteCode('ABCD'), 'ABCD');
      expect(formatInviteCode('ABCDE'), 'ABCD-E');
      expect(formatInviteCode('ABCDEFGH'), 'ABCD-EFGH');
    });

    test('the formatter types the code as you go', () {
      const formatter = InviteCodeFormatter();
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'k7m4qx9x1'),
      );
      expect(result.text, 'K7M4-QX9X');
      expect(result.selection.baseOffset, 9);
    });
  });
}
