import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/sheets_sync/sheets_settings.dart';
import 'package:family_expenses/features/pairing/domain/pairing_codes.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/sheets_device.dart';

void main() {
  late FakeGoogleWorld world;
  late Device dad;
  late Device maya;
  var now = DateTime.utc(2026, 10, 23, 12);

  setUp(() {
    world = FakeGoogleWorld();
    now = DateTime.utc(2026, 10, 23, 12);
    dad = Device(
      world,
      'dad@family.test',
      'Dad',
      SheetsRole.organiser,
      clock: () => now,
    );
    maya = Device(
      world,
      'maya@family.test',
      'Maya',
      SheetsRole.member,
      clock: () => now,
    );
  });

  group('codes', () {
    test('an invite round-trips and expires after 24 hours', () {
      final code = InviteCode(
        organiserEmail: 'dad@family.test',
        householdSheetId: 'sheet-1',
        value: newPairingValue(),
        issuedAt: now,
      );
      final parsed = InviteCode.parse(
        code.encode(),
        now: now.add(const Duration(hours: 23)),
      );
      expect(parsed.organiserEmail, 'dad@family.test');
      expect(parsed.householdSheetId, 'sheet-1');
      expect(
        () => InviteCode.parse(
          code.encode(),
          now: now.add(const Duration(hours: 24)),
        ),
        throwsA(
          isA<PairingError>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('garbage, the wrong kind of code and tampering are refused', () {
      for (final bad in ['', 'hello', 'FEH1.', 'FEH1.%%%%', 'FEM1.abc']) {
        expect(
          () => InviteCode.parse(bad, now: now),
          throwsA(isA<PairingError>()),
          reason: bad,
        );
      }
      final member = MemberCode(
        memberEmail: 'm@x.test',
        name: 'M',
        sheetId: 's',
        value: newPairingValue(),
        issuedAt: now,
      );
      expect(
        () => InviteCode.parse(member.encode(), now: now),
        throwsA(isA<PairingError>()),
      );
      expect(() => MemberCode.parse('FEH1.abc'), throwsA(isA<PairingError>()));
      // A short value is not accepted.
      final weak = InviteCode(
        organiserEmail: 'd@x.test',
        householdSheetId: 's',
        value: 'short',
        issuedAt: now,
      );
      expect(
        () => InviteCode.parse(weak.encode(), now: now),
        throwsA(isA<PairingError>()),
      );
    });

    test(
      'values use 32 characters without 0 O 1 I and are different each time',
      () {
        final a = newPairingValue(), b = newPairingValue();
        expect(a.length, 32);
        expect(a, isNot(b));
        expect(RegExp(r'[01OIl]').hasMatch(a), isFalse);
      },
    );

    test('whitespace and line breaks from a copied code are tolerated', () {
      final code = MemberCode(
        memberEmail: 'M@X.test',
        name: 'M',
        sheetId: 's',
        value: newPairingValue(),
        issuedAt: now,
      ).encode();
      final spaced = '  ${code.substring(0, 20)}\n${code.substring(20)}  ';
      expect(MemberCode.parse(spaced).memberEmail, 'm@x.test');
    });
  });

  group('the three steps', () {
    test('happy path: invite, join, add member', () async {
      final invite = await dad.pairing.createInvite();
      expect(
        world.sheets.values.where(
          (s) => s.title.startsWith('Family Household'),
        ),
        hasLength(1),
      );

      final preview = maya.pairing.previewInvite(invite);
      expect(preview.organiserEmail, 'dad@family.test');
      expect(
        world.sheets.values.where((s) => s.owner == 'maya@family.test'),
        isEmpty,
        reason: 'nothing is created or shared until the member confirms',
      );

      final code = await maya.pairing.joinWithInvite(invite);
      final mayaSheet = world.sheets[maya.settings.ownSheetId!]!;
      expect(mayaSheet.readers, {
        'dad@family.test',
      }, reason: 'shared read-only with the organiser only');
      expect(mayaSheet.tabs_['Pairing']![1][2], 'maya@family.test');
      expect(maya.settings.isPaired, isTrue);

      final pair = await dad.pairing.addMember(code);
      expect(pair.memberEmail, 'maya@family.test');
      expect(pair.name, 'Maya');
      expect(pair.status, 'active');
      final household = world.sheets[dad.settings.householdSheetId!]!;
      expect(household.readers, {
        'maya@family.test',
      }, reason: 'the household sheet is shared read-only with the member');
      final members = await dad.db.select(dad.db.members).get();
      expect(members.single.userId, 'g:maya@family.test');
      expect(members.single.displayName, 'Maya');
    });

    test('a member cannot write to the organiser\'s sheet, or the organiser to the member\'s', () async {
      await Device.pair(dad, maya);
      final household = dad.settings.householdSheetId!;
      expect(
        () => maya.google.writeRanges(household, {
          'Budgets!A2:C2': [
            ['x', 'y', 'z'],
          ],
        }),
        throwsA(isA<SheetAccessError>()),
      );
      expect(
        () => dad.google.writeRanges(maya.settings.ownSheetId!, {
          'Expenses!A2:A2': [
            ['x'],
          ],
        }),
        throwsA(isA<SheetAccessError>()),
      );
    });

    test('an expired invite is refused and nothing is shared', () async {
      final invite = await dad.pairing.createInvite();
      now = now.add(const Duration(hours: 25));
      await expectLater(
        maya.pairing.joinWithInvite(invite),
        throwsA(isA<PairingError>()),
      );
      expect(
        world.sheets.values.where((s) => s.owner == 'maya@family.test'),
        isEmpty,
      );
    });

    test(
      'the member code must match an invite the organiser made, and works once',
      () async {
        final invite = await dad.pairing.createInvite();
        final code = await maya.pairing.joinWithInvite(invite);
        await dad.pairing.addMember(code);
        // Used: the same code again is not accepted.
        await expectLater(
          dad.pairing.addMember(code),
          throwsA(isA<PairingError>()),
        );

        // A code for an invite the organiser never made.
        final other = Device(
          world,
          'sam@family.test',
          'Sam',
          SheetsRole.member,
          clock: () => now,
        );
        final strangerInvite = InviteCode(
          organiserEmail: 'dad@family.test',
          householdSheetId: dad.settings.householdSheetId!,
          value: newPairingValue(),
          issuedAt: now,
        ).encode();
        final strangerCode = await other.pairing.joinWithInvite(strangerInvite);
        await expectLater(
          dad.pairing.addMember(strangerCode),
          throwsA(isA<PairingError>()),
        );
      },
    );

    test('an invite is also single use across members', () async {
      final invite = await dad.pairing.createInvite();
      await dad.pairing.addMember(await maya.pairing.joinWithInvite(invite));
      final sam = Device(
        world,
        'sam@family.test',
        'Sam',
        SheetsRole.member,
        clock: () => now,
      );
      final samCode = await sam.pairing.joinWithInvite(invite);
      await expectLater(
        dad.pairing.addMember(samCode),
        throwsA(isA<PairingError>()),
      );
    });

    test(
      'the organiser is told when the member has not confirmed sharing yet',
      () async {
        final invite = await dad.pairing.createInvite();
        final code = await maya.pairing.joinWithInvite(invite);
        // The member unshares before the organiser pastes the code.
        await maya.google.unshare(maya.settings.ownSheetId!, 'dad@family.test');
        await expectLater(
          dad.pairing.addMember(code),
          throwsA(
            isA<PairingError>().having(
              (e) => e.message,
              'message',
              contains('not shared'),
            ),
          ),
        );
        expect(await dad.db.select(dad.db.sheetPairs).get(), isEmpty);
      },
    );

    test(
      'a sheet whose Pairing tab does not match the code is refused',
      () async {
        final invite = await dad.pairing.createInvite();
        final code = await maya.pairing.joinWithInvite(invite);
        // Someone swaps the value in the sheet.
        world.sheets[maya.settings.ownSheetId!]!.tabs_['Pairing']![1][4] =
            'SOMETHINGELSE';
        await expectLater(
          dad.pairing.addMember(code),
          throwsA(isA<PairingError>()),
        );
      },
    );

    test('own invite, own code and double pairing are refused', () async {
      final invite = await dad.pairing.createInvite();
      await expectLater(
        dad.pairing.joinWithInvite(invite),
        throwsA(isA<PairingError>()),
      );
      await Device.pair(dad, maya);
      final second = await dad.pairing.createInvite();
      await expectLater(
        maya.pairing.joinWithInvite(second),
        throwsA(isA<PairingError>()),
        reason: 'unpair first',
      );
    });
  });

  group('unpairing', () {
    test(
      'the member can stop sharing; the organiser then sees "access removed"',
      () async {
        await Device.pair(dad, maya);
        await maya.addExpense(1200, note: 'Lunch');
        await maya.sync.syncOnce();
        await dad.sync.syncOnce();
        expect((await dad.allExpenses()).single.note, 'Lunch');

        await maya.pairing.leave();
        expect(maya.settings.isPaired, isFalse);
        expect(world.sheets[maya.settings.ownSheetId!]!.readers, isEmpty);

        final report = await dad.sync.syncOnce(force: true);
        expect(report.accessRemoved, ['maya@family.test']);
        final pair = (await dad.db.select(dad.db.sheetPairs).get()).single;
        expect(pair.status, 'accessRemoved');
        expect(
          (await dad.allExpenses()).single.note,
          'Lunch',
          reason: 'past expenses stay',
        );
      },
    );

    test(
      'the organiser can unpair a member; they lose the household sheet',
      () async {
        await Device.pair(dad, maya);
        await dad.pairing.unpairMember('maya@family.test');
        expect(world.sheets[dad.settings.householdSheetId!]!.readers, isEmpty);
        expect(
          (await dad.db.select(dad.db.sheetPairs).get()).single.status,
          'unpaired',
        );
        await maya.addExpense(500);
        await maya.sync.syncOnce();
        final report = await maya.sync.syncOnce(force: true);
        expect(report.waitingForOrganiser, isTrue);
        await dad.sync.syncOnce(force: true);
        expect(
          await dad.allExpenses(),
          isEmpty,
          reason: 'an unpaired member is not read any more',
        );
      },
    );

    test('a member can join again after leaving', () async {
      await Device.pair(dad, maya);
      await maya.pairing.leave();
      await Device.pair(dad, maya);
      expect(maya.settings.isPaired, isTrue);
      expect(
        (await dad.db.select(dad.db.sheetPairs).get()).single.status,
        'active',
      );
    });
  });
}
