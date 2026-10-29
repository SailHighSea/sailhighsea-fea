import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_info.dart';
import 'core/routing/app_router.dart';
import 'features/auth/app_access.dart';
import 'features/bills/reminders/reminder_providers.dart';
import 'features/family/member_providers.dart';
import 'features/onboarding/onboarding_gate.dart';
import 'features/pairing/sheets_providers.dart';
import 'features/privacy/lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_provider.dart';
import 'core/theme/appearance_settings.dart';
import 'core/theme/color_themes.dart';
import 'core/theme/glass_backdrop.dart';
import 'core/theme/personal_background.dart';
import 'core/widgets/glass.dart';
import 'core/theme/personal_look.dart';
import 'core/window/desktop_title_bar.dart';
import 'core/window/window_controls.dart';

class FamilyExpensesApp extends ConsumerStatefulWidget {
  const FamilyExpensesApp({
    super.key,
    this.router,
    this.initialLocation = '/home',
  });

  /// Where the app opens when it builds its own router.
  final String initialLocation;

  /// Tests pass their own router; the app builds one by default.
  final GoRouter? router;

  @override
  ConsumerState<FamilyExpensesApp> createState() => _FamilyExpensesAppState();
}

class _FamilyExpensesAppState extends ConsumerState<FamilyExpensesApp> {
  late final RouteGate _gate;
  late final GoRouter _router =
      widget.router ??
      buildRouter(initialLocation: widget.initialLocation, gate: _gate);

  @override
  void initState() {
    super.initState();
    _gate = RouteGate(
      ref.read(accessProvider),
      () => ref.read(permissionsProvider),
    );
    // The router re-checks its guards whenever sign-in, household or role changes.
    ref.listenManual(permissionsProvider, (_, _) => _gate.recheck());
    ref.listenManual(accessProvider, (_, next) => _gate.update(next));
    // Keeps bill reminders scheduled for as long as the app runs.
    ref.listenManual(reminderSyncProvider, (_, _) {});
    // Google Sheets mode: keeps pushing and reading sheets while the app is open.
    ref.listenManual(sheetsAutoSyncProvider, (_, _) {});
    // The introduction can send the person straight to Import or to sign-in.
    ref.listenManual(onboardingNextRouteProvider, (_, next) {
      if (next == null) return;
      ref.read(onboardingNextRouteProvider.notifier).set(null);
      _router.go(next);
    });
  }

  @override
  void dispose() {
    _gate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceProvider);
    // A personal background picks the light or dark look that suits it, and lets it show through.
    final page = ref.watch(personalLookProvider).page;
    final forced = !page.active
        ? null
        : page.lightText
        ? darkVariantFor(settings.mode)
        : ThemeVariant.light;
    // Glass look: cards and bars are frosted glass over a backdrop, so the screens must be
    // see-through. A picture of your own is the backdrop when one is set.
    final glassLook = settings.look == AppLook.glass;
    final seeThrough = page.active || glassLook;
    return MaterialApp.router(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: buildTheme(
        settings,
        forced ?? ThemeVariant.light,
        transparentScaffold: seeThrough,
      ),
      darkTheme: buildTheme(
        settings,
        forced ?? darkVariantFor(settings.mode),
        transparentScaffold: seeThrough,
      ),
      themeMode: forced == null
          ? themeModeFor(settings.mode)
          : forced == ThemeVariant.light
          ? ThemeMode.light
          : ThemeMode.dark,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      builder: (context, child) {
        // "Larger text" scales on top of whatever the system text size already is.
        final media = MediaQuery.of(context);
        final extra = settings.largerText ? 1.2 : 1.0;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final variant = !dark
            ? ThemeVariant.light
            : (settings.mode == AppearanceMode.pureBlack
                  ? ThemeVariant.pure
                  : ThemeVariant.dark);
        final app = GlassScope(
          enabled: glassLook,
          lightEffects: settings.lightEffects,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: page.active
                    ? PersonalBackground(
                        style: page,
                        minBlur: glassLook ? 10 : 0,
                      )
                    : glassLook
                    ? GlassBackdrop(
                        theme: settings.colorTheme,
                        variant: variant,
                      )
                    : const SizedBox.shrink(),
              ),
              MediaQuery(
                data: media.copyWith(
                  textScaler: _MultipliedScaler(media.textScaler, extra),
                ),
                child: OnboardingGate(child: LockGate(child: child!)),
              ),
            ],
          ),
        );
        // Desktop: our own title bar in the theme's colours above everything, even the intro.
        final controls = ref.watch(windowControlsProvider);
        if (controls == null) return app;
        return Column(
          children: [
            DesktopTitleBar(
              controls: controls,
              platform: ref.watch(titleBarPlatformProvider),
            ),
            Expanded(child: app),
          ],
        );
      },
    );
  }
}

class _MultipliedScaler extends TextScaler {
  const _MultipliedScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(1);

  @override
  TextScaler clamp({
    double minScaleFactor = 0,
    double maxScaleFactor = double.infinity,
  }) => TextScaler.linear(scale(1).clamp(minScaleFactor, maxScaleFactor));

  @override
  bool operator ==(Object other) =>
      other is _MultipliedScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
