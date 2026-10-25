import '../../features/expenses/data/category_repository.dart';
import '../db/app_database.dart';
import '../db/tables.dart' show localHouseholdId;
import '../google/google_api.dart';
import 'household_sheet.dart';
import 'member_reader.dart';
import 'member_writer.dart';
import 'sheets_settings.dart';
import 'suggestions_sync.dart';

class SheetsSyncReport {
  const SheetsSyncReport({
    this.pushed = 0,
    this.imported = 0,
    this.accessRemoved = const [],
    this.waitingForOrganiser = false,
  });

  final int pushed;
  final int imported;

  /// Members whose sheet is gone or no longer shared.
  final List<String> accessRemoved;

  /// A member who is paired but cannot read the household sheet yet.
  final bool waitingForOrganiser;
}

/// One round of Google Sheets mode, in the order that keeps one writer per sheet:
///   everyone: push own expenses to own sheet;
///   organiser: write the household sheet, then read each paired member's sheet;
///   member: read the household sheet.
class SheetsSyncCoordinator {
  SheetsSyncCoordinator({
    required this.db,
    required this.sheets,
    required this.settings,
    required this.updateSettings,
    required this.myEmail,
    required this.myName,
    required this.currencyCode,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final SheetsApi sheets;
  final SheetsSettings Function() settings;
  final Future<void> Function(SheetsSettings Function(SheetsSettings))
  updateSettings;
  final String Function() myEmail;
  final String Function() myName;
  final String currencyCode;
  final DateTime Function() _clock;

  Future<SheetsSyncReport> syncOnce({bool force = false}) async {
    final role = settings().role;
    if (role == null) return const SheetsSyncReport();

    final writer = MemberWriter(
      db,
      sheets,
      currencyCode: currencyCode,
      householdId: localHouseholdId,
      clock: _clock,
    );
    var ownSheet = settings().ownSheetId;
    if (ownSheet == null) {
      ownSheet = await writer.createSheet(myName());
      await updateSettings((s) => s.copyWith(ownSheetId: ownSheet));
    }
    final suggestions = SuggestionsSync(db, sheets);
    final pushed = await writer.push(
      ownSheet,
      extra: role == SheetsRole.member && settings().isPaired
          ? () => suggestions.pushOwn(ownSheet!, myEmail())
          : null,
    );

    if (role == SheetsRole.organiser) {
      return _organiser(pushed, force, suggestions);
    }
    return _member(pushed, force);
  }

  Future<SheetsSyncReport> _organiser(
    int pushed,
    bool force,
    SuggestionsSync suggestions,
  ) async {
    final household = settings().householdSheetId;
    final reader = MemberReader(
      db,
      sheets,
      CategoryRepository(db, clock: _clock),
      householdId: localHouseholdId,
    );
    var imported = 0;
    final removed = <String>[];
    final pairs = await (db.select(
      db.sheetPairs,
    )..where((p) => p.status.isNotValue('unpaired'))).get();
    for (final pair in pairs) {
      final r = await reader.pull(pair, force: force);
      imported += r.added + r.updated + r.removed;
      if (r.outcome == PullOutcome.accessRemoved) {
        removed.add(pair.memberEmail);
        continue;
      }
      imported += await suggestions.pullFrom(pair.sheetId, pair.memberEmail);
    }
    if (household != null) {
      // After the pull, so approved suggestions and their new budgets go out in the same round.
      final digest = await HouseholdWriter(
        db,
        sheets,
        clock: _clock,
      ).push(household, lastDigest: settings().householdDigest, force: force);
      if (digest != settings().householdDigest) {
        await updateSettings((s) => s.copyWith(householdDigest: digest));
      }
    }
    return SheetsSyncReport(
      pushed: pushed,
      imported: imported,
      accessRemoved: removed,
    );
  }

  Future<SheetsSyncReport> _member(int pushed, bool force) async {
    final s = settings();
    if (!s.isPaired || s.householdSheetId == null) {
      return SheetsSyncReport(pushed: pushed);
    }
    try {
      final revision = await HouseholdReader(db, sheets).pull(
        s.householdSheetId!,
        lastRevision: force ? -1 : s.householdRevision,
      );
      if (revision != s.householdRevision) {
        await updateSettings((s) => s.copyWith(householdRevision: revision));
      }
    } on SheetAccessError {
      return SheetsSyncReport(pushed: pushed, waitingForOrganiser: true);
    }
    return SheetsSyncReport(pushed: pushed);
  }
}
