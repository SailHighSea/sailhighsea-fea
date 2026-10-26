import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/db_providers.dart';
import '../../core/layout/page_layout.dart';
import '../../core/layout/window_class.dart';
import '../../core/money/currency.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/widgets/surface_card.dart';
import '../family/member_providers.dart';
import '../onboarding/onboarding_gate.dart';
import '../../core/time.dart';
import '../backup/backup_service.dart';
import 'app_lock.dart';
import 'csv_export.dart';
import 'csv_share.dart';
import 'privacy_policy.dart';

/// The "Privacy and data" card: app lock, CSV export, the introduction and the
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

  BackupService _backupService(WidgetRef ref) => BackupService(
    ref.read(databaseProvider),
    currencyCode: ref.read(appearanceProvider).currencyCode,
    clock: ref.read(clockProvider),
    kdfRounds: ref.read(backupKdfRoundsProvider),
  );

  /// Saves everything on this device to one file the person keeps wherever they like, with an
  /// optional password that encrypts it.
  Future<void> _backup(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final choice = await showDialog<_PasswordChoice>(
      context: context,
      builder: (_) => const _ProtectDialog(),
    );
    if (choice == null) return;
    final service = _backupService(ref);
    final text = await service.export(password: choice.password);
    final d = ref.read(clockProvider)();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'family-expenses-backup-${d.year}-${two(d.month)}-${two(d.day)}${choice.password == null ? '' : '-encrypted'}.json';
    final saved = await ref.read(backupSaverProvider)(
      name,
      Uint8List.fromList(utf8.encode(text)),
    );
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? (choice.password == null
                    ? 'Backup saved'
                    : 'Encrypted backup saved. Keep the password: it cannot be recovered.')
              : 'Backup not saved',
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) =>
      restoreFromBackup(context, ref);

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
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              dataNote,
              key: const ValueKey('data-note'),
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ),
          _Row(
            key: const ValueKey('backup-file'),
            icon: Icons.save_alt_outlined,
            label: 'Back up to a file',
            onTap: () => _backup(context, ref),
          ),
          _Row(
            key: const ValueKey('restore-file'),
            icon: Icons.settings_backup_restore,
            label: 'Restore from a backup',
            onTap: () => _restore(context, ref),
          ),
          _Row(
            key: const ValueKey('import-expenses'),
            icon: Icons.file_upload_outlined,
            label: 'Import from a sheet or CSV',
            onTap: () => context.push('/import'),
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

BackupService _serviceFor(WidgetRef ref) => BackupService(
  ref.read(databaseProvider),
  currencyCode: ref.read(appearanceProvider).currencyCode,
  clock: ref.read(clockProvider),
  kdfRounds: ref.read(backupKdfRoundsProvider),
);

/// Choose a backup file, enter its password if it has one, check what is inside, ask, restore.
Future<void> restoreFromBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var text = await ref.read(backupFilePickerProvider)();
  if (text == null || !context.mounted) return;
  final service = _serviceFor(ref);
  if (BackupService.isEncrypted(text)) {
    String? plain;
    var wrong = false;
    while (plain == null) {
      if (!context.mounted) return;
      final password = await showDialog<String>(
        context: context,
        builder: (_) => _AskPasswordDialog(wrong: wrong),
      );
      if (password == null || !context.mounted) return;
      try {
        plain = await BackupService.decryptBackup(text, password);
      } on BackupFailure {
        wrong = true;
      }
    }
    text = plain;
  }
  final BackupCounts counts;
  try {
    counts = service.inspect(text);
  } on BackupFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  if (!context.mounted) return;
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Restore this backup?'),
      content: Text(
        'It has ${counts.expenses} expenses, ${counts.categories} categories, ${counts.budgets} budgets, ${counts.goals} goals and ${counts.bills} bills. Anything on this device that is newer is kept, and nothing is deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('confirm-restore'),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Restore'),
        ),
      ],
    ),
  );
  if (yes != true) return;
  try {
    final done = await service.restore(text);
    messenger?.showSnackBar(
      SnackBar(content: Text('Restored ${done.expenses} expenses')),
    );
  } on BackupFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// What the person chose when making a backup: no password (`null`) or a password.
class _PasswordChoice {
  const _PasswordChoice(this.password);
  final String? password;
}

class _ProtectDialog extends StatefulWidget {
  const _ProtectDialog();

  @override
  State<_ProtectDialog> createState() => _ProtectDialogState();
}

class _ProtectDialogState extends State<_ProtectDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  void _ok() {
    if (_password.text.isEmpty) {
      Navigator.pop(context, const _PasswordChoice(null));
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Use at least 6 characters.');
      return;
    }
    if (_password.text != _again.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    Navigator.pop(context, _PasswordChoice(_password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Protect with a password?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A password encrypts the file, so nobody can read it without the password. Leave it empty for a plain backup. If you forget the password the backup cannot be opened.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('backup-password'),
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('backup-password-confirm'),
              controller: _again,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password again'),
              onSubmitted: (_) => _ok(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('backup-password-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('backup-protect-ok'),
          onPressed: _ok,
          child: const Text('Save backup'),
        ),
      ],
    );
  }
}

class _AskPasswordDialog extends StatefulWidget {
  const _AskPasswordDialog({required this.wrong});
  final bool wrong;

  @override
  State<_AskPasswordDialog> createState() => _AskPasswordDialogState();
}

class _AskPasswordDialogState extends State<_AskPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('This backup is password protected'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('restore-password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (widget.wrong) ...[
            const SizedBox(height: 8),
            Text(
              'That password did not open the backup. Try again.',
              key: const ValueKey('restore-password-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('restore-password-ok'),
          onPressed: () => Navigator.pop(context, _password.text),
          child: const Text('Open'),
        ),
      ],
    );
  }
}

/// Its own page: Settings → Privacy and data.
class PrivacyDataScreen extends ConsumerStatefulWidget {
  const PrivacyDataScreen({super.key, this.restoreOnOpen = false});

  /// Start choosing a backup file as soon as the page opens (from the welcome page).
  final bool restoreOnOpen;

  @override
  ConsumerState<PrivacyDataScreen> createState() => _PrivacyDataScreenState();
}

class _PrivacyDataScreenState extends ConsumerState<PrivacyDataScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.restoreOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) restoreFromBackup(context, ref);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      header: PageHeader(
        title: 'Privacy and data',
        onBack: context.layout.isCompact ? () => context.go('/home') : null,
      ),
      children: const [PrivacyCard()],
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
