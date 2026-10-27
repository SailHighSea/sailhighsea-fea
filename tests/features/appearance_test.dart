import 'package:family_expenses/core/theme/app_tokens.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/theme/appearance_settings.dart';
import 'package:family_expenses/core/theme/color_themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

AppTokens _tokens(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(Scaffold).first))
        .extension<AppTokens>()!;

void main() {
  setUpAll(loadTestFonts);

  testWidgets('switching mode restyles the app live and persists', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      size: const Size(1024, 720),
      location: '/appearance',
    );

    expect(
      _tokens(tester).background,
      const Color(0xFFF4F6F5),
      reason: 'System in a light test env',
    );

    await tester.tap(find.text('Dark').first);
    await tester.pumpAndSettle();
    expect(_tokens(tester).background, const Color(0xFF0E1512));
    expect(container.read(appearanceProvider).mode, AppearanceMode.dark);

    await tester.tap(find.text('Pure black'));
    await tester.pumpAndSettle();
    expect(_tokens(tester).background, const Color(0xFF000000));

    await tester.tap(find.text('Light').first);
    await tester.pumpAndSettle();
    expect(_tokens(tester).background, const Color(0xFFF4F6F5));
  });

  testWidgets('colour theme changes the hero and tints the surfaces too', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(1024, 720), location: '/appearance');
    final forest = _tokens(tester);

    await tester.tap(find.text('Ocean'));
    await tester.pumpAndSettle();
    final ocean = _tokens(tester);

    expect(ocean.hero, isNot(forest.hero));
    expect(ocean.hero, previewFor(ColorThemeId.ocean).hero);
    // Light cards stay white; the page and the edges take the theme's hue.
    expect(ocean.border, isNot(forest.border));
    expect(ocean.background, isNot(forest.background));
  });

  testWidgets('preview buttons use the real theme switch', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(1280, 800),
      location: '/appearance',
    );
    await tester.tap(find.text('Preview in dark mode'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).mode, AppearanceMode.dark);

    await tester.tap(find.text('Preview in pure black'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).mode, AppearanceMode.pureBlack);
    expect(_tokens(tester).background, const Color(0xFF000000));
  });

  testWidgets('phone layout pins the preview button under the settings', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      size: const Size(390, 844),
      location: '/appearance',
    );
    expect(find.text('Preview in dark mode'), findsOneWidget);
    expect(find.text('Preview in pure black'), findsNothing);
    await tester.tap(find.text('Preview in dark mode'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).mode, AppearanceMode.dark);
  });

  testWidgets('larger text and colour-blind switches work', (tester) async {
    final container = await pumpApp(
      tester,
      size: const Size(1024, 720),
      location: '/appearance',
    );
    expect(container.read(appearanceProvider).largerText, isFalse);

    await tester.ensureVisible(find.text('Larger text'));
    await tester.tap(find.text('Larger text'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).largerText, isTrue);
    final scale = MediaQuery.textScalerOf(
      tester.element(find.byType(Scaffold).first),
    ).scale(10);
    expect(scale, closeTo(12, 0.01));

    await tester.ensureVisible(find.text('Colour-blind friendly charts'));
    await tester.tap(find.text('Colour-blind friendly charts'));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).colorBlindCharts, isTrue);
  });

  testWidgets('currency change updates the money format everywhere', (
    tester,
  ) async {
    final container = await pumpApp(
      tester,
      size: const Size(1024, 720),
      location: '/appearance',
    );
    await tester.ensureVisible(find.textContaining('Singapore dollar'));
    await tester.tap(find.textContaining('Singapore dollar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('currency-EUR')));
    await tester.pumpAndSettle();
    expect(container.read(appearanceProvider).currencyCode, 'EUR');
    expect(find.textContaining('€'), findsWidgets);
  });

  testWidgets('saved settings are applied on launch', (tester) async {
    await pumpApp(
      tester,
      size: const Size(1024, 720),
      prefs: {
        'appearance.mode': 'pureBlack',
        'appearance.colorTheme': 'graphite',
      },
    );
    final t = _tokens(tester);
    expect(t.background, const Color(0xFF000000));
    expect(t.hero, tokensFor(ColorThemeId.graphite, ThemeVariant.pure).hero);
  });

  group('Home looks the same in every theme', () {
    Future<List<String>> homeTexts(
      WidgetTester tester,
      Size size,
      String mode,
      String theme,
    ) async {
      await pumpApp(
        tester,
        size: size,
        prefs: {'appearance.mode': mode, 'appearance.colorTheme': theme},
      );
      return tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .toList();
    }

    for (final size in const [
      Size(390, 844),
      Size(1024, 720),
      Size(1280, 800),
    ]) {
      testWidgets(
        'same content at ${size.width.toInt()} across modes and colour themes',
        (tester) async {
          final reference = await homeTexts(tester, size, 'light', 'forest');
          for (final mode in ['dark', 'pureBlack']) {
            for (final theme in ColorThemeId.values.map((t) => t.name)) {
              expect(
                await homeTexts(tester, size, mode, theme),
                reference,
                reason: '$mode / $theme',
              );
            }
          }
        },
      );
    }
  });
}
