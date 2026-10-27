import 'dart:async';

import 'package:family_expenses/core/theme/app_tokens.dart';
import 'package:family_expenses/core/window/window_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_member.dart';
import '../helpers/test_app.dart';

class _FakeControls implements WindowControls {
  final calls = <String>[];
  bool maximized = false;
  final _changes = StreamController<bool>.broadcast();

  @override
  Stream<bool> get maximizedChanges => _changes.stream;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<void> minimize() async => calls.add('minimize');
  @override
  Future<void> toggleMaximize() async {
    calls.add('maximize');
    maximized = !maximized;
    _changes.add(maximized);
  }

  @override
  Future<void> close() async => calls.add('close');
  @override
  Future<void> startDragging() async => calls.add('drag');
}

Color _barColor(WidgetTester tester) {
  final material = tester.widget<Material>(
    find
        .ancestor(
          of: find.byKey(const ValueKey('title-bar-drag')),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.color!;
}

void main() {
  setUpAll(loadTestFonts);

  group('desktop title bar', () {
    testWidgets('there is none without window controls (phones, tests)', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(1280, 800));
      expect(key('title-bar-drag'), findsNothing);
    });

    testWidgets('minimize, maximize and close reach the window', (
      tester,
    ) async {
      const platform = TargetPlatform.windows;
      final controls = _FakeControls();
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        overrides: [
          windowControlsProvider.overrideWithValue(controls),
          titleBarPlatformProvider.overrideWithValue(platform),
        ],
      );
      expect(find.text('FET'), findsWidgets);
      await tapKey(tester, 'title-minimize');
      await tapKey(tester, 'title-maximize');
      expect(
        find.byIcon(Icons.filter_none),
        findsOneWidget,
        reason: 'Restore icon',
      );
      await tapKey(tester, 'title-close');
      expect(controls.calls, ['minimize', 'maximize', 'close']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('double-clicking the bar maximizes', (tester) async {
      const platform = TargetPlatform.linux;
      final controls = _FakeControls();
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        overrides: [
          windowControlsProvider.overrideWithValue(controls),
          titleBarPlatformProvider.overrideWithValue(platform),
        ],
      );
      final bar = find.byKey(const ValueKey('title-bar-drag'));
      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(bar);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controls.calls, contains('maximize'));
    });

    testWidgets('macOS keeps its own buttons and leaves room for them', (
      tester,
    ) async {
      const platform = TargetPlatform.macOS;
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        overrides: [
          windowControlsProvider.overrideWithValue(_FakeControls()),
          titleBarPlatformProvider.overrideWithValue(platform),
        ],
      );
      expect(key('title-bar-drag'), findsOneWidget);
      expect(key('title-close'), findsNothing);
    });

    for (final mode in ['light', 'dark', 'pure']) {
      testWidgets('is the theme background in $mode mode', (tester) async {
        const platform = TargetPlatform.windows;
        final c = await pumpApp(
          tester,
          size: const Size(1280, 800),
          prefs: {'appearance.mode': mode},
          overrides: [
            windowControlsProvider.overrideWithValue(_FakeControls()),
            titleBarPlatformProvider.overrideWithValue(platform),
          ],
        );
        expect(c, isNotNull);
        final ctx = tester.element(
          find.byKey(const ValueKey('title-bar-drag')),
        );
        expect(_barColor(tester), ctx.tokens.background);
      });
    }

    testWidgets('buttons are at least 44 high', (tester) async {
      const platform = TargetPlatform.windows;
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        overrides: [
          windowControlsProvider.overrideWithValue(_FakeControls()),
          titleBarPlatformProvider.overrideWithValue(platform),
        ],
      );
      for (final k in ['title-minimize', 'title-maximize', 'title-close']) {
        expect(tester.getSize(key(k)).height, greaterThanOrEqualTo(44));
      }
    });
  });
}
