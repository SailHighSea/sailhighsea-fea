import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sheets_sync/sheets_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart' show TextLinkButton;
import '../expenses/expense_form_screen.dart' show PrimaryPillButton;
import '../privacy/privacy_policy.dart' show dataNote;

const _kOnboarded = 'onboarding.done';

class OnboardedController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_kOnboarded) ?? false;

  /// Closes the introduction. [next] is a page to open straight away (the import page, or the
  /// Family page to sign in).
  Future<void> finish({String? next}) async {
    ref.read(onboardingNextRouteProvider.notifier).set(next);
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

/// Where to go once the introduction closes; the app picks this up and navigates.
class OnboardingNextRoute extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? route) => state = route;
}

final onboardingNextRouteProvider =
    NotifierProvider<OnboardingNextRoute, String?>(OnboardingNextRoute.new);

/// Shows the introduction once, on the first run, over the whole app.
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

const _cards = [
  (
    icon: Icons.add_circle_outline,
    title: 'Add an expense in seconds',
    body: 'Type the amount, pick a category and save. Or scan a receipt, or import a bank statement, and check what we read.',
  ),
  (
    icon: Icons.pie_chart_outline,
    title: 'See where the money goes',
    body: 'Budgets, charts and goals show how the month is going, for you and your family.',
  ),
];

/// Cards, then the last page where the person chooses where their data lives.
const _lastPage = 2;

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mode = ref.watch(backendModeProvider);
    final choose = _page == _lastPage;
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
                          child: choose
                              ? const SizedBox(height: kMinTapTarget)
                              : TextButton(
                                  key: const ValueKey('onboarding-skip'),
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      kMinTapTarget,
                                      kMinTapTarget,
                                    ),
                                  ),
                                  onPressed: () =>
                                      setState(() => _page = _lastPage),
                                  child: Text(
                                    'Skip',
                                    style: TextStyle(color: t.muted),
                                  ),
                                ),
                        ),
                        const Spacer(),
                        if (!choose) ...[
                          Icon(_cards[_page].icon, size: 72, color: t.primary),
                          const SizedBox(height: 24),
                          Semantics(
                            header: true,
                            child: Text(
                              _cards[_page].title,
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
                            _cards[_page].body,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: t.muted),
                          ),
                        ] else ...[
                          Icon(Icons.lock_outline, size: 56, color: t.primary),
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: Text(
                              'Where should your data live?',
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
                            dataNote,
                            key: const ValueKey('onboarding-note'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: t.muted),
                          ),
                        ],
                        const Spacer(),
                        Semantics(
                          label: 'Step ${_page + 1} of 3',
                          excludeSemantics: true,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < 3; i++)
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
                        if (!choose)
                          SizedBox(
                            width: double.infinity,
                            child: PrimaryPillButton(
                              key: const ValueKey('onboarding-next'),
                              label: 'Next',
                              onTap: () => setState(() => _page++),
                            ),
                          )
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            child: PrimaryPillButton(
                              key: const ValueKey('start-local'),
                              label: 'Sync locally, on this device',
                              onTap: () => finish(),
                            ),
                          ),
                          if (mode != BackendMode.local) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: PillButton(
                                key: const ValueKey('start-google'),
                                label: mode == BackendMode.sheets
                                    ? 'Sign in to Google Drive'
                                    : 'Sign in to share with your family',
                                style: PillStyle.outlined,
                                onTap: () => finish(next: '/family'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          TextLinkButton(
                            key: const ValueKey('start-import'),
                            label: 'Import expenses from a file first',
                            onTap: () => finish(next: '/import'),
                          ),
                        ],
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
