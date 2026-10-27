import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_info.dart';
import '../../core/layout/page_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/surface_card.dart';
import '../privacy/privacy_policy.dart';

/// "1.0.0 (42)", or `null` when the platform cannot say. Tests override it.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber.isEmpty
        ? info.version
        : '${info.version} (${info.buildNumber})';
  } on Object {
    return null;
  }
});

/// What the app does, in the words shown on the About page and in the README.
const aboutFeatures = <(IconData, String, String)>[
  (
    Icons.bolt,
    'Add expenses in seconds',
    'Type an amount, pick a category, done. Scan a receipt, or import a bank or card statement from a sheet, CSV, Excel, PDF or a photo.',
  ),
  (
    Icons.dashboard_outlined,
    'A clear month at a glance',
    'Spent, left, today, this week and a safe amount per day, with charts and a comparison with last month.',
  ),
  (
    Icons.account_balance_wallet_outlined,
    'Budgets, bills and goals',
    'Set a budget for the month and for each category, get bill reminders, and watch savings goals fill up.',
  ),
  (
    Icons.savings_outlined,
    'Income and savings',
    'Enter your monthly income and what you hold in savings to see what is left to save, and whether your goals fit.',
  ),
  (
    Icons.group_outlined,
    'Made for families',
    'Share one household through your own Google Drive or a server. Owners and members have different rights, and each person can see what the owner allows.',
  ),
  (
    Icons.category_outlined,
    'Yours to arrange',
    'Categories with your own icons and colours, ten colour themes, and your own background pictures.',
  ),
  (
    Icons.lock_outline,
    'Private by design',
    'Works offline. Data stays on your device or in your own Google account, with an app lock and password-protected backups. No ads, no tracking.',
  ),
  (
    Icons.devices_outlined,
    'On every screen',
    'Phone, tablet, foldable and desktop (Windows, Mac and Linux), with the same features everywhere.',
  ),
];

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final version = ref.watch(appVersionProvider).value;
    return AdaptivePage(
      header: PageHeader(
        title: 'About',
        onBackWhenCompact: () => context.go('/home'),
      ),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      'assets/icon/icon.png',
                      key: const ValueKey('about-icon'),
                      width: 56,
                      height: 56,
                      semanticLabel: '$kAppShortName icon',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            kAppName,
                            key: const ValueKey('about-name'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: t.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          kAppFullName,
                          key: const ValueKey('about-full-name'),
                          style: TextStyle(fontSize: 14, color: t.text),
                        ),
                        Text(
                          version == null
                              ? 'Version not available'
                              : 'Version $version',
                          key: const ValueKey('about-version'),
                          style: TextStyle(fontSize: 13, color: t.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                kAppTagline,
                key: const ValueKey('about-tagline'),
                style: TextStyle(fontSize: 15, height: 1.4, color: t.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              for (var i = 0; i < aboutFeatures.length; i++)
                Container(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : Border(top: BorderSide(color: t.border)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(aboutFeatures[i].$1, color: t.primary, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aboutFeatures[i].$2,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              aboutFeatures[i].$3,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: t.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              _Link(
                key: const ValueKey('about-privacy'),
                icon: Icons.privacy_tip_outlined,
                label: privacyPolicyTitle,
                onTap: () => context.push('/privacy'),
              ),
              _Link(
                key: const ValueKey('about-source'),
                icon: Icons.code,
                label: 'Source code on GitHub',
                divider: true,
                onTap: () => launchUrl(
                  Uri.parse(kRepositoryUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              _Link(
                key: const ValueKey('about-licences'),
                icon: Icons.description_outlined,
                label: 'Open source licences',
                divider: true,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: kAppName,
                  applicationVersion: version,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            'Made for families who like to know where the money went.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.muted),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.divider = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: t.border)) : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget + 8),
            child: Row(
              children: [
                Icon(icon, size: 22, color: t.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: t.text),
                  ),
                ),
                Icon(Icons.chevron_right, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
