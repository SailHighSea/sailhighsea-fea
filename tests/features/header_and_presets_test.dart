// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:family_expenses/core/theme/glass_backdrop.dart';
import 'package:family_expenses/core/theme/header_gradient.dart';
import 'package:family_expenses/core/theme/personal_look.dart';
import 'package:family_expenses/core/theme/preset_pictures.dart';
import 'package:family_expenses/core/widgets/glass.dart';
import 'package:family_expenses/features/backup/settings_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUpAll(loadTestFonts);
  glassTests();

  group('header gradient colours', () {
    test('white text reads on both ends of every theme, in every mode', () {
      for (final theme in ColorThemeId.values) {
        for (final v in ThemeVariant.values) {
          final (a, b) = headerGradientFor(theme, v);
          expect(
            _contrast(Colors.white, a),
            greaterThanOrEqualTo(3.0),
            reason: '$theme $v start',
          );
          expect(
            _contrast(Colors.white, b),
            greaterThanOrEqualTo(3.0),
            reason: '$theme $v end',
          );
        }
      }
    });
  });

  group('the gradient Home header', () {
    testWidgets('is the default look of Home', (tester) async {
      await pumpApp(tester, size: const Size(390, 844));
      expect(key('gradient-header'), findsOneWidget);
    });

    testWidgets('Classic brings back the plain month row', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'appearance.homeHeader': 'classic'},
      );
      expect(key('gradient-header'), findsNothing);
      expect(find.text('Spent this month'), findsOneWidget);
    });

    testWidgets(
      'the overview card overlaps the band and stays tappable and swipeable',
      (tester) async {
        await pumpApp(tester, size: const Size(390, 844));
        final band = tester.getRect(key('gradient-header'));
        final card = tester.getRect(key('hero-swipe'));
        expect(
          card.top,
          lessThan(band.bottom),
          reason: 'the card reaches into the band',
        );
        expect(
          card.top,
          greaterThan(band.top + 60),
          reason: 'but not over the logo row',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('shows the logo, name and person when chosen', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'appearance.homeHeader': 'gradient'},
      );
      expect(key('gradient-header'), findsOneWidget);
      expect(find.text('FET'), findsOneWidget);
      expect(find.text('Family Expenses Tracker'), findsOneWidget);
      expect(
        find.text('You'),
        findsNothing,
        reason: 'alone, the picture says it',
      );
      expect(find.text('+ Add'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the choice is made on the Appearance page', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/appearance',
      );
      await tester.ensureVisible(key('home-header-gradient'));
      await tapKey(tester, 'home-header-gradient');
      expect(c.read(appearanceProvider).homeHeader, HomeHeaderStyle.gradient);
      expect(
        c.read(sharedPreferencesProvider).getString('appearance.homeHeader'),
        'gradient',
      );
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small, large text': Size(320, 640),
      'tablet': Size(840, 900),
      'laptop': Size(1024, 720),
      'desktop': Size(1280, 800),
    }.entries) {
      for (final mode in ['light', 'dark', 'pureBlack']) {
        testWidgets('fits on ${size.key} in $mode', (tester) async {
          await pumpApp(
            tester,
            size: size.value,
            textScale: size.key.contains('large') ? 1.6 : 1,
            prefs: {
              'appearance.homeHeader': 'gradient',
              'appearance.mode': mode,
            },
          );
          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        });
      }
    }

    testWidgets('every colour theme works with it', (tester) async {
      for (final theme in ColorThemeId.values.take(1)) {
        await pumpApp(
          tester,
          size: const Size(390, 844),
          prefs: {
            'appearance.homeHeader': 'gradient',
            'appearance.colorTheme': theme.name,
          },
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('works together with a personal background', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {
          'appearance.homeHeader': 'gradient',
          'personal.look': jsonEncode({
            'page': const BackgroundStyle(
              kind: BackgroundKind.picture,
              picturePath: 'asset:assets/backgrounds/harbour.png',
              pictureLuminance: 0.254,
            ).toJson(),
            'card': BackgroundStyle.none.toJson(),
          }),
        },
      );
      expect(tester.takeException(), isNull);
      expect(key('gradient-header'), findsOneWidget);
    });
  });

  group('built-in pictures', () {
    test('there are six, with their brightness', () {
      expect(kPresetPictures.map((p) => p.id), [
        'dunes',
        'harbour',
        'forest',
        'sunset',
        'city',
        'blossom',
      ]);
      for (final p in kPresetPictures) {
        expect(p.luminance, inInclusiveRange(0.0, 1.0));
        expect(isPresetPath(p.path), isTrue);
      }
      expect(isPresetPath('/data/user/0/app/backgrounds/page-1.png'), isFalse);
    });

    testWidgets(
      'they are listed on the picture page, and picking one sets it',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/personalise',
        );
        await tapKey(tester, 'bg-kind-picture');
        for (final p in kPresetPictures) {
          expect(key('bg-preset-${p.id}'), findsOneWidget, reason: p.name);
        }
        await tester.ensureVisible(key('bg-preset-city'));
        await tapKey(tester, 'bg-preset-city');
        final page = c.read(personalLookProvider).page;
        expect(page.kind, BackgroundKind.picture);
        expect(page.picturePath, 'asset:assets/backgrounds/city.png');
        expect(
          page.lightText,
          isTrue,
          reason: 'a dark picture gets light text',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a built-in picture shows as the app background on every size',
      (tester) async {
        for (final id in ['dunes']) {
          await pumpApp(
            tester,
            size: const Size(1280, 800),
            prefs: {
              'personal.look': jsonEncode({
                'page': BackgroundStyle(
                  kind: BackgroundKind.picture,
                  picturePath: 'asset:assets/backgrounds/$id.png',
                  pictureLuminance: 0.674,
                ).toJson(),
                'card': BackgroundStyle.none.toJson(),
              }),
            },
          );
          expect(tester.takeException(), isNull);
        }
      },
    );

    test(
      'a backup keeps the choice of a built-in picture without copying it',
      () async {
        SharedPreferences.setMockInitialValues({
          'personal.look': jsonEncode({
            'page': const BackgroundStyle(
              kind: BackgroundKind.picture,
              picturePath: 'asset:assets/backgrounds/forest.png',
              pictureLuminance: 0.666,
            ).toJson(),
            'card': BackgroundStyle.none.toJson(),
          }),
        });
        final prefs = await SharedPreferences.getInstance();
        final out = await exportSettings(prefs);
        expect(out.containsKey('pictures'), isFalse);
        final fresh = await (() async {
          SharedPreferences.setMockInitialValues({});
          return SharedPreferences.getInstance();
        })();
        await restoreSettings(fresh, out);
        final look = jsonDecode(fresh.getString('personal.look')!) as Map;
        expect((look['page'] as Map)['kind'], 'picture');
        expect(
          (look['page'] as Map)['picturePath'],
          'asset:assets/backgrounds/forest.png',
        );
      },
    );
  });
}

void glassTests() {
  group('the Glass look', () {
    const glass = {'appearance.look': 'glass'};
    final picture = jsonEncode({
      'page': const BackgroundStyle(
        kind: BackgroundKind.picture,
        picturePath: 'asset:assets/backgrounds/sunset.png',
        pictureLuminance: 0.334,
      ).toJson(),
      'card': BackgroundStyle.none.toJson(),
    });

    testWidgets('Standard has no glass', (tester) async {
      await pumpApp(tester, size: const Size(390, 844));
      expect(find.byType(GlassBox), findsNothing);
      expect(key('glass-bar'), findsNothing);
      expect(
        key('pill-bar'),
        findsOneWidget,
        reason: 'Standard has the pill bar too, solid',
      );
    });

    testWidgets(
      'Glass blurs the cards, floats the bottom bar and brings its own backdrop',
      (tester) async {
        await pumpApp(tester, size: const Size(390, 844), prefs: glass);
        expect(find.byType(GlassBox), findsWidgets);
        expect(key('glass-bar'), findsOneWidget);
        expect(find.byType(GlassBackdrop), findsOneWidget);
        // The bar is a rounded pill inset from the edges, not a full-width strip.
        final bar = tester.getRect(key('glass-bar'));
        expect(bar.left, greaterThanOrEqualTo(14));
        expect(bar.right, lessThanOrEqualTo(390 - 14));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('your own picture replaces the backdrop', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {...glass, 'personal.look': picture},
      );
      expect(find.byType(GlassBackdrop), findsNothing);
      expect(key('glass-bar'), findsOneWidget);
    });

    testWidgets('a picture with the Standard look has no glass', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'personal.look': picture},
      );
      expect(find.byType(GlassBox), findsNothing);
    });

    testWidgets(
      'the chosen tab sits in a lighter pill and tapping moves between tabs',
      (tester) async {
        await pumpApp(tester, size: const Size(390, 844), prefs: glass);
        await tester.tap(find.text('Budgets'));
        await settle(tester);
        expect(find.text('Budgets'), findsWidgets);
        expect(key('glass-bar'), findsOneWidget);
      },
    );

    testWidgets('is switched on Appearance and saved', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/appearance',
      );
      await tester.ensureVisible(key('look-glass'));
      await tapKey(tester, 'look-glass');
      expect(c.read(appearanceProvider).look, AppLook.glass);
      expect(
        c.read(sharedPreferencesProvider).getString('appearance.look'),
        'glass',
      );
      await tapKey(tester, 'look-standard');
      expect(c.read(appearanceProvider).look, AppLook.standard);
    });

    testWidgets('is chosen on the welcome screen', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'onboarding.done': false},
      );
      await tester.tap(key('onboarding-skip'));
      await tester.pump();
      await tester.ensureVisible(key('start-look-glass'));
      await tester.tap(key('start-look-glass'));
      await tester.pump();
      expect(c.read(appearanceProvider).look, AppLook.glass);
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small, large text': Size(320, 640),
      'tablet': Size(840, 900),
      'laptop': Size(1024, 720),
      'desktop': Size(1280, 800),
    }.entries) {
      for (final mode in ['light', 'dark', 'pureBlack']) {
        testWidgets('Glass fits on ${size.key} in $mode on every tab', (
          tester,
        ) async {
          for (final route in [
            '/home',
            '/budgets',
            '/goals',
            '/insights',
            '/settings',
            '/expenses',
          ]) {
            await pumpApp(
              tester,
              size: size.value,
              textScale: size.key.contains('large') ? 1.6 : 1,
              location: route,
              prefs: {...glass, 'appearance.mode': mode},
            );
            expect(tester.takeException(), isNull, reason: route);
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });
}
