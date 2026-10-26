import 'dart:convert';
import 'dart:io';

import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/app_tokens.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:family_expenses/core/theme/personal_background.dart';
import 'package:family_expenses/core/theme/personal_look.dart';
import 'package:family_expenses/core/theme/picture_store.dart';
import 'package:family_expenses/features/home/widgets/personal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

String _look({BackgroundStyle? page, BackgroundStyle? card}) => jsonEncode({
  'page': (page ?? BackgroundStyle.none).toJson(),
  'card': (card ?? BackgroundStyle.none).toJson(),
});

const _dark = BackgroundStyle(kind: BackgroundKind.solid, color: 0xFF2E2058);
const _light = BackgroundStyle(kind: BackgroundKind.solid, color: 0xFFF9E0E8);

void main() {
  setUpAll(loadTestFonts);

  group('the model', () {
    test('survives JSON and ignores junk', () {
      const s = BackgroundStyle(
        kind: BackgroundKind.picture,
        picturePath: '/x/y.png',
        pictureLuminance: 0.2,
        blur: 8,
        dim: 50,
        tone: TextTone.light,
        angle: 90,
        gradient: 3,
        color: 0xFF123456,
      );
      expect(BackgroundStyle.fromJson(s.toJson()), s);
      final junk = BackgroundStyle.fromJson({
        'kind': 'weird',
        'blur': 9999,
        'dim': -5,
        'gradient': 77,
        'tone': 3,
      });
      expect(junk.kind, BackgroundKind.none);
      expect(junk.blur, 24);
      expect(junk.dim, 0);
      expect(junk.gradient, kBackgroundGradients.length - 1);
    });

    test('a picture counts only once it has a file', () {
      expect(
        const BackgroundStyle(kind: BackgroundKind.picture).active,
        isFalse,
      );
      expect(const BackgroundStyle().active, isFalse);
      expect(_dark.active, isTrue);
    });

    test('text is light on dark and dark on light, unless forced', () {
      expect(_dark.lightText, isTrue);
      expect(_light.lightText, isFalse);
      expect(_light.copyWith(tone: TextTone.light).lightText, isTrue);
      expect(_dark.copyWith(tone: TextTone.dark).lightText, isFalse);
    });

    test(
      'dimming a picture darkens it and improves contrast for light text',
      () {
        const bright = BackgroundStyle(
          kind: BackgroundKind.picture,
          picturePath: '/p.png',
          pictureLuminance: 0.8,
          dim: 0,
          tone: TextTone.light,
        );
        expect(bright.contrast, lessThan(4.5));
        expect(bright.copyWith(dim: 70).contrast, greaterThan(4.5));
      },
    );

    test('contrast of black on white is about 21 to 1', () {
      const white = BackgroundStyle(
        kind: BackgroundKind.solid,
        color: 0xFFFFFFFF,
      );
      expect(white.contrast, closeTo(21, 0.1));
    });
  });

  group('in the app', () {
    testWidgets(
      'no background: nothing is painted and the theme is as chosen',
      (tester) async {
        await pumpApp(tester, size: const Size(390, 844));
        expect(find.byType(PersonalBackground), findsOneWidget);
        expect(
          tester
              .widget<PersonalBackground>(find.byType(PersonalBackground))
              .style
              .active,
          isFalse,
        );
        expect(find.byType(PersonalHero), findsOneWidget);
      },
    );

    testWidgets('a dark background switches the app to its dark look', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {
          'appearance.mode': 'light',
          'personal.look': _look(page: _dark),
        },
      );
      final ctx = tester.element(find.text('Spent this month'));
      final dark = tokensFor(ColorThemeId.forest, ThemeVariant.dark);
      expect(ctx.tokens.text, dark.text);
      expect(Theme.of(ctx).scaffoldBackgroundColor.a, 0);
    });

    testWidgets('a light background switches the app to its light look', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {
          'appearance.mode': 'dark',
          'personal.look': _look(page: _light),
        },
      );
      final ctx = tester.element(find.text('Spent this month'));
      expect(
        ctx.tokens.text,
        tokensFor(ColorThemeId.forest, ThemeVariant.light).text,
      );
    });

    testWidgets('the Home hero card takes its own background and text colour', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'personal.look': _look(card: _light)},
      );
      final text = tester.widget<Text>(find.text('Spent this month'));
      expect(
        text.style!.color!.computeLuminance(),
        lessThan(0.5),
        reason: 'dark text on a light card',
      );
      await pumpApp(
        tester,
        size: const Size(390, 844),
        prefs: {'personal.look': _look(card: _dark)},
      ).then((_) {});
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small, large text': Size(320, 640),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('Home fits with a background on ${size.key}', (tester) async {
        await pumpApp(
          tester,
          size: size.value,
          textScale: size.key.contains('large') ? 1.6 : 1,
          prefs: {'personal.look': _look(page: _dark, card: _light)},
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the settings page', () {
    testWidgets(
      'picking a colour, a gradient and a text colour changes the app at once',
      (tester) async {
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/personalise',
        );
        await tester.ensureVisible(key('bg-color-11'));
        await tapKey(tester, 'bg-color-11');
        expect(c.read(personalLookProvider).page.kind, BackgroundKind.solid);
        expect(c.read(personalLookProvider).page.color, kBackgroundColors[11]);

        await tapKey(tester, 'bg-kind-gradient');
        await tester.ensureVisible(key('bg-gradient-3'));
        await tapKey(tester, 'bg-gradient-3');
        expect(c.read(personalLookProvider).page.kind, BackgroundKind.gradient);
        expect(c.read(personalLookProvider).page.gradient, 3);

        await tester.ensureVisible(key('bg-tone-dark'));
        await tapKey(tester, 'bg-tone-dark');
        expect(c.read(personalLookProvider).page.tone, TextTone.dark);
        expect(find.byKey(const ValueKey('bg-contrast')), findsOneWidget);
      },
    );

    testWidgets('the Home card has its own style', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/personalise',
      );
      await tapKey(tester, 'bg-target-card');
      await tester.ensureVisible(key('bg-color-3'));
      await tapKey(tester, 'bg-color-3');
      expect(c.read(personalLookProvider).card.kind, BackgroundKind.solid);
      expect(c.read(personalLookProvider).page.kind, BackgroundKind.none);
    });

    testWidgets(
      'a picture from the gallery is kept with its brightness and can be dimmed',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('bgtest');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/pic.png')..writeAsBytesSync(const [0]);
        final c = await pumpApp(
          tester,
          size: const Size(390, 844),
          location: '/personalise',
          overrides: [
            picturePickerProvider.overrideWithValue(
              (source, slot) async => StoredPicture(file.path, 0.25),
            ),
          ],
        );
        await tapKey(tester, 'bg-kind-picture');
        await tapKey(tester, 'bg-gallery');
        await settle(tester);
        final page = c.read(personalLookProvider).page;
        expect(page.kind, BackgroundKind.picture);
        expect(page.picturePath, file.path);
        expect(page.pictureLuminance, 0.25);
        expect(key('bg-dim'), findsOneWidget);
        expect(key('bg-blur'), findsOneWidget);
      },
    );

    testWidgets('a file that is not a picture shows a message', (tester) async {
      await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/personalise',
        overrides: [
          picturePickerProvider.overrideWithValue(
            (source, slot) async =>
                throw const FormatException('That file is not a picture.'),
          ),
        ],
      );
      await tapKey(tester, 'bg-kind-picture');
      await tapKey(tester, 'bg-gallery');
      expect(find.text('That file is not a picture.'), findsOneWidget);
    });

    testWidgets('reset puts the theme back', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/personalise',
        prefs: {'personal.look': _look(page: _dark, card: _light)},
      );
      await tester.ensureVisible(key('bg-reset-this'));
      await tapKey(tester, 'bg-reset-this');
      expect(c.read(personalLookProvider).page.active, isFalse);
      expect(c.read(personalLookProvider).card.active, isTrue);
      await tester.ensureVisible(key('bg-reset-all'));
      await tapKey(tester, 'bg-reset-all');
      expect(c.read(personalLookProvider).card.active, isFalse);
    });

    testWidgets('the choice is saved and read back', (tester) async {
      final c = await pumpApp(
        tester,
        size: const Size(390, 844),
        location: '/personalise',
      );
      await tester.ensureVisible(key('bg-color-1'));
      await tapKey(tester, 'bg-color-1');
      final raw = c.read(sharedPreferencesProvider).getString('personal.look');
      expect(raw, isNotNull);
      expect(
        BackgroundStyle.fromJson(
          ((jsonDecode(raw!) as Map)['page'] as Map).cast<String, Object?>(),
        ).color,
        kBackgroundColors[1],
      );
    });

    testWidgets('reachable from Appearance, on every size', (tester) async {
      for (final w in [390.0, 1280.0]) {
        await pumpApp(tester, size: Size(w, 900), location: '/appearance');
        await tester.ensureVisible(key('open-personalise'));
        await tapKey(tester, 'open-personalise');
        expect(
          find.text('Backgrounds and pictures'),
          findsWidgets,
          reason: '$w',
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    for (final size in const {
      'phone': Size(390, 844),
      'phone small': Size(320, 640),
      'tablet': Size(840, 900),
      'desktop': Size(1280, 800),
    }.entries) {
      testWidgets('fits on ${size.key}', (tester) async {
        await pumpApp(tester, size: size.value, location: '/personalise');
        await tapKey(tester, 'bg-kind-picture');
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });
}
