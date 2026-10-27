import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/personal_look.dart';
import '../../core/theme/picture_store.dart';
import '../../core/theme/preset_pictures.dart';

/// The settings a backup carries: theme, mode, text size, chart colours, currency, the personal
/// background and the bill reminder choices. Device-only things (app lock, Google sign-in, which
/// sheet is paired) are left out on purpose: they belong to this device or to this person.
const backedUpSettingKeys = <String>{
  'appearance.mode',
  'appearance.colorTheme',
  'appearance.largerText',
  'appearance.colorBlindCharts',
  'appearance.currency',
  'appearance.homeHeader',
  'appearance.look',
  'personal.look',
  'profile.name',
  'profile.avatar',
  'bills.remindersOn',
  'bills.reminderLeadDays',
};

/// A background picture bigger than this is left out of the backup (the choice itself is kept).
const _maxPictureBytes = 6 * 1024 * 1024;

/// What a backup file stores under `settings`.
Future<Map<String, Object?>> exportSettings(SharedPreferences prefs) async {
  final values = <String, Object?>{};
  for (final k in backedUpSettingKeys) {
    final v = prefs.get(k);
    if (v != null) values[k] = v;
  }
  final pictures = <String, String>{};
  final raw = prefs.getString('personal.look');
  if (raw != null) {
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      for (final slot in ['page', 'card']) {
        final style = BackgroundStyle.fromJson(
          (j[slot] as Map?)?.cast<String, Object?>() ?? const {},
        );
        final path = style.picturePath;
        if (style.kind == BackgroundKind.picture &&
            path != null &&
            !isPresetPath(path)) {
          final f = File(path);
          if (f.existsSync() && f.lengthSync() <= _maxPictureBytes) {
            pictures[slot] = base64.encode(f.readAsBytesSync());
          }
        }
      }
    } on Object {
      // A damaged look setting: the rest is still backed up.
    }
  }
  final avatar = prefs.getString('profile.avatar');
  if (avatar != null && avatar.startsWith('file:')) {
    final f = File(avatar.substring(5));
    if (f.existsSync() && f.lengthSync() <= _maxPictureBytes) {
      pictures['avatar'] = base64.encode(f.readAsBytesSync());
    }
  }
  return {'values': values, if (pictures.isNotEmpty) 'pictures': pictures};
}

/// Applies the `settings` of a backup to [prefs]. Unknown keys and wrong types are ignored, so a
/// damaged or newer file can never write anything it should not.
Future<void> restoreSettings(
  SharedPreferences prefs,
  Map<String, dynamic> settings,
) async {
  final values = (settings['values'] as Map?)?.cast<String, Object?>() ?? {};
  for (final e in values.entries) {
    if (!backedUpSettingKeys.contains(e.key)) continue;
    final v = e.value;
    if (v is bool) {
      await prefs.setBool(e.key, v);
    } else if (v is int) {
      await prefs.setInt(e.key, v);
    } else if (v is double) {
      await prefs.setDouble(e.key, v);
    } else if (v is String) {
      await prefs.setString(e.key, v);
    }
  }
  // Pictures go back into the app's folder, and the look points at the new files.
  final pictures =
      (settings['pictures'] as Map?)?.cast<String, Object?>() ?? {};
  final avatar = prefs.getString('profile.avatar');
  if (avatar != null && avatar.startsWith('file:')) {
    final data = pictures['avatar'];
    if (data is String) {
      try {
        final path = await storePictureBytes(base64.decode(data), 'avatar');
        await prefs.setString('profile.avatar', 'file:$path');
      } on Object {
        await prefs.remove('profile.avatar');
      }
    } else {
      await prefs.remove('profile.avatar');
    }
  }
  final raw = prefs.getString('personal.look');
  if (raw == null) return;
  try {
    final look = jsonDecode(raw) as Map<String, Object?>;
    for (final slot in ['page', 'card']) {
      final style = (look[slot] as Map?)?.cast<String, Object?>();
      if (style == null || style['kind'] != 'picture') continue;
      if (isPresetPath(style['picturePath'] as String?)) continue;
      final data = pictures[slot];
      if (data is String) {
        style['picturePath'] = await storePictureBytes(
          base64.decode(data),
          slot,
        );
      } else {
        // The picture did not come with the backup: fall back to the theme.
        style['kind'] = 'none';
        style['picturePath'] = null;
      }
    }
    await prefs.setString('personal.look', jsonEncode(look));
  } on Object {
    await prefs.remove('personal.look');
  }
}
