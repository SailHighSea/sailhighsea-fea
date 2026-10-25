import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/appearance_provider.dart';

/// How this install is built: `--dart-define=BACKEND=sheets|supabase|local`. Without the define the
/// app behaves as before (Supabase when it is configured, otherwise local only).
enum BackendMode {
  local,
  supabase,
  sheets;

  static BackendMode parse(String value, {required bool supabaseConfigured}) {
    switch (value.toLowerCase()) {
      case 'sheets':
        return BackendMode.sheets;
      case 'supabase':
        return BackendMode.supabase;
      case 'local':
        return BackendMode.local;
    }
    return supabaseConfigured ? BackendMode.supabase : BackendMode.local;
  }
}

/// Which mode the build runs in. `main()` overrides it; tests override it.
final backendModeProvider = Provider<BackendMode>((ref) => BackendMode.local);

enum SheetsRole { organiser, member }

@immutable
class SheetsSettings {
  const SheetsSettings({
    this.role,
    this.displayName = '',
    this.ownSheetId,
    this.householdSheetId,
    this.organiserEmail,
    this.pairValue,
    this.invites = const [],
    this.householdDigest = '',
    this.householdRevision = 0,
  });

  /// Chosen once, on the Family page.
  final SheetsRole? role;
  final String displayName;

  /// The sheet this person's app writes their expenses to.
  final String? ownSheetId;

  /// Organiser: the household sheet they wrote. Member: the organiser's household sheet to read.
  final String? householdSheetId;

  /// Member only: who the member shares their sheet with.
  final String? organiserEmail;

  /// Member only: the pairing value from the invite they accepted.
  final String? pairValue;

  /// Organiser only: invite values issued and not used yet, with when they were issued.
  final List<Invite> invites;

  /// Organiser only: fingerprint of what was last written to the household sheet.
  final String householdDigest;

  /// Member only: the household sheet's revision at the last read.
  final int householdRevision;

  bool get isPaired => role == SheetsRole.member && organiserEmail != null;

  SheetsSettings copyWith({
    SheetsRole? role,
    String? displayName,
    String? ownSheetId,
    String? householdSheetId,
    String? organiserEmail,
    String? pairValue,
    List<Invite>? invites,
    String? householdDigest,
    int? householdRevision,
    bool clearPairing = false,
  }) => SheetsSettings(
    role: role ?? this.role,
    displayName: displayName ?? this.displayName,
    ownSheetId: ownSheetId ?? this.ownSheetId,
    householdSheetId: clearPairing
        ? null
        : (householdSheetId ?? this.householdSheetId),
    organiserEmail: clearPairing
        ? null
        : (organiserEmail ?? this.organiserEmail),
    pairValue: clearPairing ? null : (pairValue ?? this.pairValue),
    invites: invites ?? this.invites,
    householdDigest: householdDigest ?? this.householdDigest,
    householdRevision: clearPairing
        ? 0
        : (householdRevision ?? this.householdRevision),
  );
}

@immutable
class Invite {
  const Invite(this.value, this.issuedAt);
  final String value;
  final DateTime issuedAt;
}

class SheetsSettingsController extends Notifier<SheetsSettings> {
  static const _k = 'sheets.settings';

  @override
  SheetsSettings build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(_k);
    if (raw == null) return const SheetsSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SheetsSettings(
        role: SheetsRole.values.where((r) => r.name == j['role']).firstOrNull,
        displayName: (j['name'] as String?) ?? '',
        ownSheetId: j['own'] as String?,
        householdSheetId: j['household'] as String?,
        organiserEmail: j['organiser'] as String?,
        pairValue: j['value'] as String?,
        invites: [
          for (final i in (j['invites'] as List? ?? const []))
            Invite((i as Map)['v'] as String, DateTime.parse(i['t'] as String)),
        ],
        householdDigest: (j['digest'] as String?) ?? '',
        householdRevision: (j['rev'] as int?) ?? 0,
      );
    } catch (_) {
      return const SheetsSettings();
    }
  }

  Future<void> update(SheetsSettings Function(SheetsSettings s) change) async {
    final s = change(state);
    state = s;
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          _k,
          jsonEncode({
            'role': s.role?.name,
            'name': s.displayName,
            'own': s.ownSheetId,
            'household': s.householdSheetId,
            'organiser': s.organiserEmail,
            'value': s.pairValue,
            'invites': [
              for (final i in s.invites)
                {'v': i.value, 't': i.issuedAt.toUtc().toIso8601String()},
            ],
            'digest': s.householdDigest,
            'rev': s.householdRevision,
          }),
        );
  }
}

final sheetsSettingsProvider =
    NotifierProvider<SheetsSettingsController, SheetsSettings>(
      SheetsSettingsController.new,
    );

/// True in a Sheets-mode build.
final isSheetsModeProvider = Provider<bool>(
  (ref) => ref.watch(backendModeProvider) == BackendMode.sheets,
);
