import 'package:flutter/services.dart';

/// Characters an invite code can contain: no 0, O, 1 or I (docs/SPEC.md section 7).
const inviteCodeAlphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
const inviteCodeLength = 8;

/// "k7m4 qx9x" becomes "K7M4QX9X": upper case, only valid characters, at most 8.
String cleanInviteCode(String input) {
  final out = StringBuffer();
  for (final c in input.toUpperCase().split('')) {
    if (inviteCodeAlphabet.contains(c)) out.write(c);
    if (out.length == inviteCodeLength) break;
  }
  return out.toString();
}

/// "K7M4QX9X" becomes "K7M4-QX9X".
String formatInviteCode(String clean) => clean.length <= 4
    ? clean
    : '${clean.substring(0, 4)}-${clean.substring(4)}';

/// Types the code as "ABCD-EFGH": capitals only, the dash added for you.
class InviteCodeFormatter extends TextInputFormatter {
  const InviteCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = formatInviteCode(cleanInviteCode(newValue.text));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
