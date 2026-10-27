import 'dart:io';

import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/picture_store.dart';
import 'package:family_expenses/features/profile/profile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('the header picture opens the profile; name and avatar stick', (
    tester,
  ) async {
    final c = await pumpApp(tester, size: const Size(390, 844));
    await tapKey(tester, 'header-avatar');
    await tester.enterText(key('profile-name'), 'Mina');
    await settle(tester);
    await tapKey(tester, 'avatar-sailor');
    await tapKey(tester, 'profile-save');
    await settle(tester);
    expect(c.read(profileProvider).name, 'Mina');
    expect(c.read(profileProvider).presetId, 'sailor');
    expect(c.read(displayNameProvider), 'Mina');
    final prefs = c.read(sharedPreferencesProvider);
    expect(prefs.getString(kProfileNameKey), 'Mina');
    expect(prefs.getString(kProfileAvatarKey), 'preset:sailor');
    expect(find.text('Mina'), findsWidgets);
  });

  testWidgets('Settings has an Edit profile row on every size', (tester) async {
    for (final w in [390.0, 1280.0]) {
      await pumpApp(tester, size: Size(w, 900), location: '/settings');
      await tapKey(tester, 'settings-profile');
      expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('an uploaded picture is used, and the initial can come back', (
    tester,
  ) async {
    final file = File('${Directory.systemTemp.path}/avatar-test.png')
      ..writeAsBytesSync(List.filled(8, 0));
    final c = await pumpApp(
      tester,
      size: const Size(390, 844),
      location: '/settings',
      overrides: [
        picturePickerProvider.overrideWithValue(
          (source, slot) async => StoredPicture(file.path, 0.5),
        ),
      ],
    );
    await tapKey(tester, 'settings-profile');
    await tapKey(tester, 'avatar-upload');
    await settle(tester);
    expect(c.read(profileProvider).filePath, file.path);
    await tapKey(tester, 'avatar-initial');
    expect(c.read(profileProvider).avatar, '');
  });

  testWidgets('the profile sheet fits and has big enough targets', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(320, 640), location: '/settings');
    await tapKey(tester, 'settings-profile');
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
