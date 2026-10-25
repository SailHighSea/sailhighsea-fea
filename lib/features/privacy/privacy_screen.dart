import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/db_providers.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/currency.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/widgets/surface_card.dart';
import '../family/member_providers.dart';
import '../onboarding/onboarding_gate.dart';
import 'app_lock.dart';
import 'csv_export.dart';
import 'csv_share.dart';
import 'privacy_policy.dart';

/// "Privacy and data" card on the Appearance page: app lock, CSV export, the introduction and the
/// privacy policy.
class PrivacyCard extends ConsumerWidget {
  const PrivacyCard({super.key});

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final db = ref.read(databaseProvider);
    final rows =
        await (db.select(db.expenses)
              ..where((e) => e.deletedAt.isNull())
              ..orderBy([(e) => OrderingTerm.desc(e.spentOn)]))
            .get();
    final categories = {
      for (final c in await db.select(db.categories).get()) c.id: c.name,
    };
    final label = ref.read(addedByLabelProvider);
    final currency = currencyByCode(ref.read(appearanceProvider).currencyCode);
    final csv = buildExpensesCsv([
      for (final e in rows)
        CsvExpense(
          date: e.spentOn,
          cents: e.amountCents,
          category: categories[e.categoryId] ?? 'Other',
          note: e.note,
          addedBy: label(e.createdBy),
        ),
    ], currency);
    await ref
        .read(fileSharerProvider)
        .shareText('family-expenses.csv', csv, 'text/csv');
    messenger?.showSnackBar(
      SnackBar(content: Text('Exported ${rows.length} expenses')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final lock = ref.watch(appLockProvider);
    final supported = ref.watch(appLockSupportedProvider).value ?? false;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          if (supported)
            SwitchListTile(
              key: const ValueKey('app-lock'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Lock the app',
                style: TextStyle(fontSize: 15, color: t.text),
              ),
              subtitle: Text(
                'Ask for your fingerprint, face or PIN when opening',
                style: TextStyle(fontSize: 13, color: t.muted),
              ),
              value: lock.enabled,
              onChanged: (on) {
                final c = ref.read(appLockProvider.notifier);
                on ? c.enable() : c.disable();
              },
            ),
          _Row(
            key: const ValueKey('export-csv'),
            icon: Icons.file_download_outlined,
            label: 'Export expenses (CSV)',
            onTap: () => _export(context, ref),
          ),
          _Row(
            key: const ValueKey('show-intro'),
            icon: Icons.slideshow_outlined,
            label: 'Show the introduction again',
            onTap: () => ref.read(onboardedProvider.notifier).reset(),
          ),
          _Row(
            key: const ValueKey('privacy-policy'),
            icon: Icons.privacy_tip_outlined,
            label: privacyPolicyTitle,
            onTap: () => context.push('/privacy'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            children: [
              Icon(icon, size: 20, color: t.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15, color: t.text),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdaptivePage(
      header: PageHeader(
        title: privacyPolicyTitle,
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      children: [
        for (final (title, body) in privacyPolicySections) ...[
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: TextStyle(fontSize: 15, height: 1.4, color: t.text),
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
