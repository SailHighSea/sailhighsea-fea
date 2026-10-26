import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:family_expenses/core/app_info.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/personal_look.dart';
import 'package:family_expenses/features/about/about_screen.dart';
import 'package:family_expenses/features/backup/backup_service.dart';
import 'package:family_expenses/features/backup/settings_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

// ignore_for_file: invalid_use_of_visible_for_testing_member

class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _Paths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

Future<SharedPreferences> _prefs(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  setUpAll(loadTestFonts);

  group('settings in a backup', () {
    test('only the allowed settings are exported', () async {
      final prefs = await _prefs({
        'appearance.mode': 'dark',
        'appearance.colorTheme': 'rose',
        'appearance.largerText': true,
        'appearance.currency': 'QAR',
        'bills.reminderLeadDays': 5,
        'privacy.appLock': true,
        'google.tokens': 'secret',
        'sheets.settings': '{}',
        'onboarding.done': true,
      });
      final out = await exportSettings(prefs);
      final values = out['values']! as Map<String, Object?>;
      expect(values.keys.toSet(), {
        'appearance.mode',
        'appearance.colorTheme',
        'appearance.largerText',
        'appearance.currency',
        'bills.reminderLeadDays',
      });
      expect(jsonEncode(out), isNot(contains('secret')));
    });

    test(
      'restoring writes them back, ignores unknown keys and wrong types',
      () async {
        final prefs = await _prefs({});
        await restoreSettings(prefs, {
          'values': {
            'appearance.mode': 'pureBlack',
            'appearance.colorTheme': 'lagoon',
            'appearance.largerText': true,
            'bills.reminderLeadDays': 2,
            'google.tokens': 'evil',
            'privacy.appLock': true,
          },
        });
        expect(prefs.getString('appearance.mode'), 'pureBlack');
        expect(prefs.getString('appearance.colorTheme'), 'lagoon');
        expect(prefs.getBool('appearance.largerText'), isTrue);
        expect(prefs.getInt('bills.reminderLeadDays'), 2);
        expect(prefs.getString('google.tokens'), isNull);
        expect(prefs.getBool('privacy.appLock'), isNull);
      },
    );

    test('a background picture travels with the backup and the look points at the new file', () async {
      final dir = Directory.systemTemp.createTempSync('bk');
      addTearDown(() => dir.deleteSync(recursive: true));
      PathProviderPlatform.instance = _Paths(dir.path);
      final pic = File('${dir.path}/old.png')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);
      final style = BackgroundStyle(
        kind: BackgroundKind.picture,
        picturePath: pic.path,
        pictureLuminance: 0.3,
      );
      final source = await _prefs({
        'personal.look': jsonEncode({
          'page': style.toJson(),
          'card': BackgroundStyle.none.toJson(),
        }),
      });
      final out = await exportSettings(source);
      expect((out['pictures']! as Map).keys, ['page']);

      final fresh = await _prefs({});
      await restoreSettings(fresh, out);
      final look = jsonDecode(fresh.getString('personal.look')!) as Map;
      final page = BackgroundStyle.fromJson(
        (look['page'] as Map).cast<String, Object?>(),
      );
      expect(page.kind, BackgroundKind.picture);
      expect(page.picturePath, isNot(pic.path));
      expect(File(page.picturePath!).readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('a picture missing from the backup falls back to the theme', () async {
      final prefs = await _prefs({});
      await restoreSettings(prefs, {
        'values': {
          'personal.look': jsonEncode({
            'page': const BackgroundStyle(
              kind: BackgroundKind.picture,
              picturePath: '/gone.png',
            ).toJson(),
            'card': BackgroundStyle.none.toJson(),
          }),
        },
      });
      final look = jsonDecode(prefs.getString('personal.look')!) as Map;
      expect((look['page'] as Map)['kind'], 'none');
    });

    test('the backup file holds them, and they can be read back', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = BackupService(db, currencyCode: 'SGD');
      final text = await service.export(
        settings: {
          'values': {'appearance.colorTheme': 'rose'},
        },
      );
      expect(service.inspect(text).hasSettings, isTrue);
      expect(
        (service.settingsIn(text)!['values'] as Map)['appearance.colorTheme'],
        'rose',
      );
      final plain = await service.export();
      expect(service.inspect(plain).hasSettings, isFalse);
      expect(service.settingsIn(plain), isNull);
    });

    test('encrypted backups keep settings secret too', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = BackupService(db, currencyCode: 'SGD', kdfRounds: 1000);
      final enc = await service.export(
        password: 'pw1234',
        settings: {
          'values': {'appearance.currency': 'QAR'},
        },
      );
      expect(enc, isNot(contains('QAR')));
      final plain = await BackupService.decryptBackup(enc, 'pw1234');
      expect(plain, contains('QAR'));
    });

    testWidgets('restoring a backup brings the theme back on screen', (
      tester,
    ) async {
      final src = AppDatabase(NativeDatabase.memory());
      final text = (await tester.runAsync(() async {
        final t = await BackupService(src, currencyCode: 'SGD').export(
          settings: {
            'values': {
              'appearance.colorTheme': 'rose',
              'appearance.currency': 'QAR',
            },
          },
        );
        await src.close();
        return t;
      }))!;
      final c = await pumpApp(
        tester,
        size: const Size(1280, 800),
        location: '/data',
        overrides: [
          backupFilePickerProvider.overrideWithValue(() async => text),
        ],
      );
      expect(c.read(appearanceProvider).colorTheme, ColorThemeId.forest);
      await tester.ensureVisible(key('restore-file'));
      await tapKey(tester, 'restore-file');
      expect(find.textContaining('your theme and settings'), findsOneWidget);
      await tapKey(tester, 'confirm-restore');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await settle(tester);
      expect(c.read(appearanceProvider).colorTheme, ColorThemeId.rose);
      expect(c.read(appearanceProvider).currencyCode, 'QAR');
    });
  });

  group('About page', () {
    testWidgets('shows the name, version, description and features', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/about',
        overrides: [
          appVersionProvider.overrideWith((ref) async => '1.2.3 (45)'),
        ],
      );
      await settle(tester);
      expect(find.text(kAppName), findsOneWidget);
      expect(key('about-icon'), findsOneWidget);
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
      expect(find.text(kAppTagline), findsOneWidget);
      for (final f in aboutFeatures) {
        await tester.ensureVisible(find.text(f.$2));
        expect(find.text(f.$2), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('says so when the version is not available', (tester) async {
      await pumpApp(tester, size: const Size(390, 844), location: '/about');
      await settle(tester);
      expect(find.text('Version not available'), findsOneWidget);
    });

    testWidgets('the privacy policy opens from it', (tester) async {
      await pumpApp(tester, size: const Size(390, 844), location: '/about');
      await tester.ensureVisible(key('about-privacy'));
      await tapKey(tester, 'about-privacy');
      expect(find.text('What this app is'), findsOneWidget);
    });

    testWidgets('is reached from the Settings tab on the phone', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(390, 844));
      await tester.tap(find.text('Settings').first);
      await settle(tester);
      await tester.ensureVisible(key('settings-about'));
      await tapKey(tester, 'settings-about');
      expect(find.text(kAppName), findsOneWidget);
    });

    testWidgets('is reached from Appearance on a desktop', (tester) async {
      await pumpApp(
        tester,
        size: const Size(1280, 900),
        location: '/appearance',
      );
      await tester.ensureVisible(key('open-about'));
      await tapKey(tester, 'open-about');
      expect(find.text(kAppName), findsOneWidget);
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small, large text': Size(320, 640),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('fits on ${size.key}', (tester) async {
        await pumpApp(
          tester,
          size: size.value,
          textScale: size.key.contains('large') ? 1.6 : 1,
          location: '/about',
        );
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  test('the app is called FET Family Expenses Tracker', () {
    expect(kAppName, 'FET Family Expenses Tracker');
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="FET Family Expenses Tracker"'),
    );
    expect(
      File('windows/runner/main.cpp').readAsStringSync(),
      contains('FET Family Expenses Tracker'),
    );
    expect(
      File('linux/runner/my_application.cc').readAsStringSync(),
      contains('FET Family Expenses Tracker'),
    );
  });
}
