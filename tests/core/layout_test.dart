import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:family_expenses/core/layout/destinations.dart';
import 'package:family_expenses/core/layout/hinge.dart';
import 'package:family_expenses/core/layout/window_class.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// Widths from docs/SPEC.md section 4.
const _matrix = [360.0, 600.0, 840.0, 1024.0, 1280.0, 1920.0];

void main() {
  setUpAll(loadTestFonts);

  group('window classes', () {
    test('breakpoints', () {
      expect(WindowClass.forWidth(359), WindowClass.compact);
      expect(WindowClass.forWidth(599.9), WindowClass.compact);
      expect(WindowClass.forWidth(600), WindowClass.medium);
      expect(WindowClass.forWidth(1199.9), WindowClass.medium);
      expect(WindowClass.forWidth(1200), WindowClass.expanded);
      expect(WindowClass.forWidth(1920), WindowClass.expanded);
    });

    test('metrics', () {
      expect(LayoutMetrics.of(WindowClass.compact).railWidth, 0);
      expect(LayoutMetrics.of(WindowClass.medium).railWidth, 96);
      expect(LayoutMetrics.of(WindowClass.expanded).railWidth, 240);
    });
  });

  group('navigation shell by width', () {
    for (final width in _matrix) {
      testWidgets('width $width shows the right navigation and no overflow', (
        tester,
      ) async {
        final height = width < 600 ? 800.0 : 800.0;
        await pumpApp(tester, size: Size(width, height));
        final windowClass = WindowClass.forWidth(width);

        // Home content is the same everywhere.
        expect(find.text('Spent this month'), findsOneWidget);
        expect(find.text('Top categories'), findsOneWidget);

        switch (windowClass) {
          case WindowClass.compact:
            for (final d in AppDestination.tabs) {
              expect(
                find.text(d.label),
                findsWidgets,
                reason: '${d.label} tab',
              );
            }
            expect(
              find.text('Goals'),
              findsNothing,
              reason: 'Goals is on the Settings page on the phone',
            );
            expect(find.text('Expenses'), findsNothing);
          case WindowClass.medium:
            final rail = find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 96,
            );
            expect(rail, findsOneWidget);
            for (final d in AppDestination.main) {
              expect(
                find.text(d.label),
                findsWidgets,
                reason: '${d.label} in rail',
              );
            }
            expect(find.text('Settings'), findsOneWidget);
          case WindowClass.expanded:
            final sidebar = find.byWidgetPredicate(
              (w) => w is Container && w.constraints?.maxWidth == 240,
            );
            expect(sidebar, findsOneWidget);
            for (final d in AppDestination.main) {
              expect(
                find.text(d.label),
                findsWidgets,
                reason: '${d.label} in sidebar',
              );
            }
            expect(find.text('Appearance'), findsOneWidget);
            expect(find.text('3 members'), findsOneWidget);
        }
      });
    }

    testWidgets('large system text does not overflow at 360 and 1024', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(360, 800), textScale: 2);
      expect(tester.takeException(), isNull);
      await pumpApp(tester, size: const Size(1024, 720), textScale: 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('larger text setting also fits', (tester) async {
      await pumpApp(
        tester,
        size: const Size(360, 800),
        prefs: {'appearance.largerText': true},
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('every destination is reachable on every size', () {
    for (final width in [390.0, 840.0, 1280.0]) {
      testWidgets('width $width', (tester) async {
        await pumpApp(tester, size: Size(width, 900));
        final compact = WindowClass.forWidth(width) == WindowClass.compact;

        for (final d in AppDestination.values) {
          if (d == AppDestination.home) continue;
          // The Settings tab exists on the phone only; larger windows list its items directly.
          if (d == AppDestination.settings && !compact) continue;
          if (compact && !d.isTab) {
            // The phone reaches these from the Settings tab.
            await tester.tap(find.text('Settings').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text(d.label).first);
          } else {
            await tester.tap(
              find
                  .text(
                    compact || d != AppDestination.appearance
                        ? d.label
                        : _navLabel(width, d),
                  )
                  .first,
            );
          }
          await tester.pumpAndSettle();
          // The pages are titled like the mockups, which differ from the nav labels for two.
          final title = switch (d) {
            AppDestination.appearance => 'Appearance',
            AppDestination.goals => 'Savings goals',
            AppDestination.bills => 'Upcoming bills',
            _ => d.label,
          };
          expect(find.text(title), findsWidgets, reason: d.label);
          expect(tester.takeException(), isNull);

          // Back to Home for the next destination.
          if (compact && !d.isTab) {
            await tester.tap(find.bySemanticsLabel('Back'));
          } else {
            await tester.tap(find.text('Home').first);
          }
          await tester.pumpAndSettle();
          expect(find.text('Spent this month'), findsOneWidget);
        }
      });
    }
  });

  group('hinge', () {
    MediaQueryData media(List<DisplayFeature> features) =>
        MediaQueryData(size: const Size(800, 1000), displayFeatures: features);

    test('half-open horizontal hinge is detected', () {
      final hinge = media(const [
        DisplayFeature(
          bounds: Rect.fromLTWH(0, 490, 800, 20),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ]);
      expect(horizontalHingeOf(hinge), const Rect.fromLTWH(0, 490, 800, 20));
    });

    test('flat, vertical and absent hinges are ignored', () {
      expect(horizontalHingeOf(media(const [])), isNull);
      expect(
        horizontalHingeOf(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 490, 800, 20),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureFlat,
            ),
          ]),
        ),
        isNull,
      );
      expect(
        horizontalHingeOf(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(390, 0, 20, 1000),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ]),
        ),
        isNull,
      );
      expect(
        horizontalHingeOf(
          media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 490, 800, 20),
              type: DisplayFeatureType.cutout,
              state: DisplayFeatureState.unknown,
            ),
          ]),
        ),
        isNull,
      );
    });

    testWidgets('HingeSplit puts content above the hinge and the form below', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(800, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const split = HingeSplit(
        bottom: ColoredBox(key: Key('below'), color: Colors.blue),
        child: ColoredBox(key: Key('above'), color: Colors.red),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: media(const [
            DisplayFeature(
              bounds: Rect.fromLTWH(0, 490, 800, 20),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ]),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: split,
          ),
        ),
      );
      expect(
        tester.getRect(find.byKey(const Key('above'))),
        const Rect.fromLTWH(0, 0, 800, 490),
      );
      expect(
        tester.getRect(find.byKey(const Key('below'))),
        const Rect.fromLTWH(0, 510, 800, 490),
      );
    });

    testWidgets('without a hinge only the content is shown', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: media(const []),
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: HingeSplit(
              bottom: ColoredBox(key: Key('below'), color: Colors.blue),
              child: ColoredBox(key: Key('above'), color: Colors.red),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('above')), findsOneWidget);
      expect(find.byKey(const Key('below')), findsNothing);
    });
  });
}

/// The rail labels the Appearance destination "Settings".
String _navLabel(double width, AppDestination d) =>
    WindowClass.forWidth(width) == WindowClass.medium ? d.railLabel : d.label;
