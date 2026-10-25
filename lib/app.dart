import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/appearance_provider.dart';
import 'core/theme/color_themes.dart';

class FamilyExpensesApp extends ConsumerStatefulWidget {
  const FamilyExpensesApp({super.key, this.router});

  /// Tests pass their own router; the app builds one by default.
  final GoRouter? router;

  @override
  ConsumerState<FamilyExpensesApp> createState() => _FamilyExpensesAppState();
}

class _FamilyExpensesAppState extends ConsumerState<FamilyExpensesApp> {
  late final GoRouter _router = widget.router ?? buildRouter();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appearanceProvider);
    return MaterialApp.router(
      title: 'Family Expenses',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: buildTheme(settings, ThemeVariant.light),
      darkTheme: buildTheme(settings, darkVariantFor(settings.mode)),
      themeMode: themeModeFor(settings.mode),
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
        return MediaQuery(
          data: media.copyWith(
            textScaler: _MultipliedScaler(media.textScaler, extra),
          ),
          child: child!,
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
