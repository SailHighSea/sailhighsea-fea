import 'package:drift/drift.dart';

import '../../core/db/app_database.dart';
import '../../core/db/tables.dart' show localHouseholdId;
import '../../core/google/google_api.dart';
import '../../core/sheets_sync/household_sheet.dart';
import '../../core/sheets_sync/member_reader.dart';
import '../../core/sheets_sync/member_writer.dart';
import '../../core/sheets_sync/sheet_layout.dart';
import '../../core/sheets_sync/sheets_settings.dart';
import 'domain/pairing_codes.dart';

/// The pairing steps of Google Sheets mode (docs/phases/phase-8-google-sheets-mode.md). No server:
/// Google Drive sharing is the access control, and the apps check each other's codes.
class PairingService {
  PairingService({
    required this.db,
    required this.sheets,
    required this.drive,
    required this.settings,
    required this.updateSettings,
    required this.myEmail,
    required this.myName,
    required this.currencyCode,
    DateTime Function()? clock,
    Random32? random,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? newPairingValue;

  final AppDatabase db;
  final SheetsApi sheets;
  final DriveApi drive;
  final SheetsSettings Function() settings;
  final Future<void> Function(SheetsSettings Function(SheetsSettings))
  updateSettings;
  final String Function() myEmail;
  final String Function() myName;
  final String currencyCode;
  final DateTime Function() _clock;
  final Random32 _random;

  // ---- Organiser ----------------------------------------------------------------------------

  /// Step 1: the code the organiser shows. Creates the household sheet the first time.
  Future<String> createInvite() async {
    var s = settings();
    var sheetId = s.householdSheetId;
    sheetId ??= await HouseholdWriter(
      db,
      sheets,
      clock: _clock,
    ).create(myName().isEmpty ? 'family' : myName());
    final now = _clock();
    final value = _random();
    await updateSettings(
      (s) => s.copyWith(
        householdSheetId: sheetId,
        invites: [
          for (final i in s.invites)
            if (now.difference(i.issuedAt) < inviteCodeLifetime) i,
          Invite(value, now),
        ],
      ),
    );
    return InviteCode(
      organiserEmail: myEmail(),
      householdSheetId: sheetId,
      value: value,
      issuedAt: now,
    ).encode();
  }

  /// Step 3: the organiser pastes or scans the member's code.
  Future<SheetPairRow> addMember(String codeText) async {
    final code = MemberCode.parse(codeText);
    final s = settings();
    final now = _clock();
    final invite = s.invites
        .where(
          (i) =>
              i.value == code.value &&
              now.difference(i.issuedAt) < inviteCodeLifetime,
        )
        .firstOrNull;
    if (invite == null) {
      throw const PairingError(
        'This code does not match an invite you made, or the invite expired. Create a new invite.',
      );
    }
    if (code.memberEmail == myEmail().toLowerCase()) {
      throw const PairingError('That is your own code.');
    }
    final List<List<String>> pairing;
    try {
      pairing = await sheets.read(code.sheetId, '${Tabs.pairing}!A2:F2');
    } on SheetAccessError {
      throw PairingError(
        "${code.name.isEmpty ? 'The member' : code.name}'s sheet is not shared with you yet. Ask them to confirm sharing, then try again.",
      );
    }
    final row = pairing.firstOrNull;
    if (row == null ||
        row.length < 5 ||
        row[1].toLowerCase() != myEmail().toLowerCase() ||
        row[2].toLowerCase() != code.memberEmail ||
        row[4] != code.value) {
      throw const PairingError(
        'The sheet does not match this code. Ask the member to join again.',
      );
    }
    final household = s.householdSheetId;
    if (household == null) throw const PairingError('Create an invite first.');
    await drive.shareReadOnly(household, code.memberEmail);
    await db
        .into(db.sheetPairs)
        .insertOnConflictUpdate(
          SheetPairsCompanion.insert(
            memberEmail: code.memberEmail,
            name: code.name.isEmpty ? code.memberEmail : code.name,
            sheetId: code.sheetId,
            pairedAt: now,
          ),
        );
    await db
        .into(db.members)
        .insertOnConflictUpdate(
          MembersCompanion.insert(
            householdId: localHouseholdId,
            userId: memberUserId(code.memberEmail),
            role: 'editor',
            displayName: code.name.isEmpty ? code.memberEmail : code.name,
            joinedAt: now,
          ),
        );
    // Single use.
    await updateSettings(
      (s) => s.copyWith(
        invites: [
          for (final i in s.invites)
            if (i.value != code.value) i,
        ],
      ),
    );
    return (db.select(
      db.sheetPairs,
    )..where((p) => p.memberEmail.equals(code.memberEmail))).getSingle();
  }

  /// Removes the member's access to the household sheet and stops reading their sheet. Expenses
  /// already imported stay.
  Future<void> unpairMember(String email) async {
    final household = settings().householdSheetId;
    if (household != null) {
      try {
        await drive.unshare(household, email);
      } on SheetAccessError {
        // Already gone.
      }
    }
    await (db.update(db.sheetPairs)..where((p) => p.memberEmail.equals(email)))
        .write(const SheetPairsCompanion(status: Value('unpaired')));
  }

  // ---- Member -------------------------------------------------------------------------------

  /// Step 2a: what the member is asked to confirm.
  InviteCode previewInvite(String text) =>
      InviteCode.parse(text, now: _clock());

  /// Step 2b: the member said yes. Shares their sheet read-only with the organiser, writes the
  /// `Pairing` tab and returns the member's own code.
  Future<String> joinWithInvite(String text) async {
    final invite = previewInvite(text);
    if (settings().isPaired) {
      throw const PairingError(
        'You are already paired with a household. Unpair first.',
      );
    }
    if (invite.organiserEmail.toLowerCase() == myEmail().toLowerCase()) {
      throw const PairingError('That is your own invite.');
    }
    var sheetId = settings().ownSheetId;
    sheetId ??= await MemberWriter(
      db,
      sheets,
      currencyCode: currencyCode,
      householdId: localHouseholdId,
      clock: _clock,
    ).createSheet(myName());
    await drive.shareReadOnly(sheetId, invite.organiserEmail);
    final now = _clock();
    await sheets.clear(sheetId, '${Tabs.pairing}!A2:F2');
    await sheets.writeRanges(sheetId, {
      '${Tabs.pairing}!A2:F2': [
        [
          invite.householdSheetId,
          invite.organiserEmail,
          myEmail(),
          myName(),
          invite.value,
          now.toUtc().toIso8601String(),
        ],
      ],
    });
    await updateSettings(
      (s) => s.copyWith(
        ownSheetId: sheetId,
        householdSheetId: invite.householdSheetId,
        organiserEmail: invite.organiserEmail,
        pairValue: invite.value,
      ),
    );
    return MemberCode(
      memberEmail: myEmail(),
      name: myName(),
      sheetId: sheetId,
      value: invite.value,
      issuedAt: now,
    ).encode();
  }

  /// The member's own code again (to show the QR once more).
  String? currentMemberCode() {
    final s = settings();
    if (!s.isPaired || s.ownSheetId == null || s.pairValue == null) return null;
    return MemberCode(
      memberEmail: myEmail(),
      name: myName(),
      sheetId: s.ownSheetId!,
      value: s.pairValue!,
      issuedAt: _clock(),
    ).encode();
  }

  /// The member stops sharing: the organiser loses access to the member's sheet.
  Future<void> leave() async {
    final s = settings();
    if (s.ownSheetId != null && s.organiserEmail != null) {
      try {
        await drive.unshare(s.ownSheetId!, s.organiserEmail!);
        await sheets.clear(s.ownSheetId!, '${Tabs.pairing}!A2:F2');
      } on SheetAccessError {
        // The sheet was already removed.
      }
    }
    await updateSettings((s) => s.copyWith(clearPairing: true));
  }
}

typedef Random32 = String Function();
