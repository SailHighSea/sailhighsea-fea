import 'dart:convert';
import 'dart:math';

/// The two codes of the pairing (docs/phases/phase-8-google-sheets-mode.md). They carry no secret
/// that gives access by itself: sharing only happens after the member confirms, and Google Drive
/// sharing is what controls access.
const inviteCodeLifetime = Duration(hours: 24);

class PairingError implements Exception {
  const PairingError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// From the organiser to the member: "share your expenses with me".
class InviteCode {
  const InviteCode({
    required this.organiserEmail,
    required this.householdSheetId,
    required this.value,
    required this.issuedAt,
  });

  final String organiserEmail;
  final String householdSheetId;

  /// Random value that binds the two codes together; single use.
  final String value;
  final DateTime issuedAt;

  static const _prefix = 'FEH1.';

  String encode() =>
      _prefix +
      _b64({
        'e': organiserEmail,
        's': householdSheetId,
        'r': value,
        't': issuedAt.toUtc().millisecondsSinceEpoch,
      });

  bool isExpired(DateTime now) =>
      now.difference(issuedAt) >= inviteCodeLifetime;

  static InviteCode parse(String text, {required DateTime now}) {
    final j = _unb64(
      text,
      _prefix,
      'That is not an invite code from the organiser.',
    );
    final code = InviteCode(
      organiserEmail: _str(j, 'e'),
      householdSheetId: _str(j, 's'),
      value: _str(j, 'r'),
      issuedAt: DateTime.fromMillisecondsSinceEpoch(_int(j, 't'), isUtc: true),
    );
    if (!_validEmail(code.organiserEmail) || code.value.length < 16) {
      throw const PairingError('That invite code is not valid.');
    }
    if (code.isExpired(now)) {
      throw const PairingError(
        'That invite code has expired. Ask for a new one.',
      );
    }
    return code;
  }
}

/// From the member to the organiser: "my sheet is shared with you".
class MemberCode {
  const MemberCode({
    required this.memberEmail,
    required this.name,
    required this.sheetId,
    required this.value,
    required this.issuedAt,
  });

  final String memberEmail;
  final String name;
  final String sheetId;
  final String value;
  final DateTime issuedAt;

  static const _prefix = 'FEM1.';

  String encode() =>
      _prefix +
      _b64({
        'e': memberEmail,
        'n': name,
        's': sheetId,
        'r': value,
        't': issuedAt.toUtc().millisecondsSinceEpoch,
      });

  static MemberCode parse(String text) {
    final j = _unb64(text, _prefix, 'That is not a code from a family member.');
    final code = MemberCode(
      memberEmail: _str(j, 'e').toLowerCase(),
      name: _str(j, 'n'),
      sheetId: _str(j, 's'),
      value: _str(j, 'r'),
      issuedAt: DateTime.fromMillisecondsSinceEpoch(_int(j, 't'), isUtc: true),
    );
    if (!_validEmail(code.memberEmail) ||
        code.sheetId.isEmpty ||
        code.value.length < 16) {
      throw const PairingError('That code is not valid.');
    }
    return code;
  }
}

/// 32 random characters from an alphabet without lookalikes (no 0 O 1 I l).
String newPairingValue([Random? random]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(32, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))),
  );
}

bool _validEmail(String s) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

String _b64(Map<String, Object?> j) =>
    base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');

Map<String, dynamic> _unb64(String text, String prefix, String wrong) {
  final t = text.trim().replaceAll(RegExp(r'\s'), '');
  if (!t.startsWith(prefix)) throw PairingError(wrong);
  try {
    final j = jsonDecode(
      utf8.decode(
        base64Url.decode(base64Url.normalize(t.substring(prefix.length))),
      ),
    );
    if (j is Map<String, dynamic>) return j;
  } catch (_) {}
  throw PairingError(wrong);
}

String _str(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! String) throw const PairingError('That code is not valid.');
  return v.trim();
}

int _int(Map<String, dynamic> j, String k) {
  final v = j[k];
  if (v is! int) throw const PairingError('That code is not valid.');
  return v;
}
