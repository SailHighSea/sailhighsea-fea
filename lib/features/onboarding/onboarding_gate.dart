import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../expenses/expense_form_screen.dart' show PrimaryPillButton;

const _kOnboarded = 'onboarding.done';

class OnboardedController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kOnboarded) ?? false;

  Future<void> finish() async {
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_kOnboarded, true);
  }

  /// "Show the introduction again" in Appearance.
  Future<void> reset() async {
    state = false;
    await ref.read(sharedPreferencesProvider).setBool(_kOnboarded, false);
  }
}

final onboardedProvider = NotifierProvider<OnboardedController, bool>(
  OnboardedController.new,
);

/// Shows the three-card introduction once, on the first run, over the whole app.
class OnboardingGate extends ConsumerWidget {
  const OnboardingGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(onboardedProvider)) return child;
    return const OnboardingScreen();
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

const _pages = [
  (
    icon: Icons.add_circle_outline,
    title: 'Add an expense in seconds',
    body: 'Type the amount, pick a category and save. Or scan a receipt and check what we read.',
  ),
  (
    icon: Icons.pie_chart_outline,
    title: 'See where the money goes',
    body: 'Budgets, charts and goals show how the month is going, for you and your family.',
  ),
  (
    icon: Icons.lock_outline,
    title: 'Yours, on your device',
    body: 'Everything is stored on this device first and works offline. You choose what to share and who sees it.',
  ),
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final last = _page == _pages.length - 1;
    final p = _pages[_page];
    final finish = ref.read(onboardedProvider.notifier).finish;
    return Material(
      color: t.background,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight - 48),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: last
                              ? const SizedBox(height: kMinTapTarget)
                              : TextButton(
                                  key: const ValueKey('onboarding-skip'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      kMinTapTarget,
                                      kMinTapTarget,
                                    ),
                                  ),
                                  onPressed: finish,
                                  child: Text(
                                    'Skip',
                                    style: TextStyle(color: t.muted),
                                  ),
                                ),
                        ),
                        const Spacer(),
                        Icon(p.icon, size: 72, color: t.primary),
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: Text(
                            p.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          p.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: t.muted),
                        ),
                        const Spacer(),
                        Semantics(
                          label: 'Step ${_page + 1} of ${_pages.length}',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _pages.length; i++)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: i == _page ? t.primary : t.border,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: PrimaryPillButton(
                            key: const ValueKey('onboarding-next'),
                            label: last ? 'Get started' : 'Next',
                            onTap: last
                                ? finish
                                : () => setState(() => _page++),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
