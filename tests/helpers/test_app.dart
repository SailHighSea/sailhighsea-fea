// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'dart:ui' show DisplayFeature;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:family_expenses/app.dart';
import 'package:family_expenses/core/db/app_database.dart';
import 'package:family_expenses/core/db/db_providers.dart';
import 'package:family_expenses/features/family/member_providers.dart';
import 'package:family_expenses/features/home/home_providers.dart';
import 'package:family_expenses/features/home/home_sample.dart';
import 'package:family_expenses/core/routing/app_router.dart';
import 'package:family_expenses/core/theme/appearance_provider.dart';
import 'package:family_expenses/core/time.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fixed "now" so charts, labels and goldens never depend on the real date.
final kTestNow = DateTime(2026, 10, 23, 12);

/// Loads DM Sans and Material Icons so goldens draw real glyphs instead of test boxes.
Future<void> loadTestFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en_US');

  final dmSans = FontLoader('DM Sans')
    ..addFont(rootBundle.load('assets/fonts/DMSans.ttf'));
  await dmSans.load();

  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ?? _flutterRootFromExecutable();
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

String _flutterRootFromExecutable() {
  // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    if (Directory('${dir.path}/bin/cache').existsSync()) return dir.path;
    dir = dir.parent;
  }
  return 'C:/src/flutter';
}

/// Pumps the whole app at [size] (logical px, devicePixelRatio 1) with saved appearance
/// [prefs], an empty in-memory database (only the default categories) and the router
/// starting at [location]. Pass [sampleHome] to show the mockups' fixed Home numbers.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required Size size,
  Map<String, Object> prefs = const {},
  String location = '/home',
  double textScale = 1,
  bool sampleHome = false,
  bool sampleMembers = true,
  void Function(AppDatabase db)? seed,
  List<DisplayFeature> displayFeatures = const [],

  /// Extra provider overrides (fake auth, fake server).
  List<Override> overrides = const [],

  /// Runs against the opened database before the app starts (real async allowed).
  Future<void> Function(AppDatabase db)? seedAsync,

  /// Use the real router with its sign-in, household and role guards.
  bool gated = false,
}) async {
  // The first-run introduction is covered by its own test; everything else starts past it.
  SharedPreferences.setMockInitialValues({'onboarding.done': true, ...prefs});
  final sp = await SharedPreferences.getInstance();
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1
    ..displayFeatures = displayFeatures;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  // Tests open several in-memory databases on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final db = AppDatabase(NativeDatabase.memory(), clock: () => kTestNow);
  // Open the database and run its migration on the real event loop (widget tests run in
  // fake async, where the first connection would never finish).
  await tester.runAsync(() => db.select(db.categories).get());
  seed?.call(db);
  if (seedAsync != null) await tester.runAsync(() => seedAsync(db));
  addTearDown(() async {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      clockProvider.overrideWithValue(() => kTestNow),
      databaseProvider.overrideWithValue(db),
      // The mockups show three members in the sidebar footer; real members are tested in family_test.
      if (sampleMembers)
        memberInitialsProvider.overrideWithValue(const ['Y', 'M', 'S']),
      if (sampleHome)
        homeSummaryProvider.overrideWithValue(
          AsyncData(sampleHomeSummary(DateTime(2026, 10))),
        ),
      ...overrides,
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: gated
          ? FamilyExpensesApp(initialLocation: location)
          : FamilyExpensesApp(router: buildRouter(initialLocation: location)),
    ),
  );
  if (gated) {
    // Sign-in and household checks use the real event loop, and the starting page's spinner
    // never settles, so step time by hand.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  } else {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }
  // Drift closes its stream queries on a zero-length timer; let it run before the test ends.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });
  return container;
}
