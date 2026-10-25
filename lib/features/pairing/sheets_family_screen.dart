import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/db/app_database.dart';
import '../../core/google/google_auth.dart';
import '../../core/layout/page_layout.dart';
import '../../core/sheets_sync/sheets_settings.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import 'domain/pairing_codes.dart';
import 'qr_scanner.dart';
import 'sheets_providers.dart';

/// The Family page in Google Sheets mode: sign in, pair with a code, see who is paired. The
/// Supabase Family page (roles, invite codes on a server) is not used in this mode.
class SheetsFamilyScreen extends ConsumerWidget {
  const SheetsFamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(googleAccountProvider);
    final settings = ref.watch(sheetsSettingsProvider);
    final sync = ref.watch(sheetsSyncProvider);
    final t = context.tokens;

    final children = <Widget>[];
    if (account.isLoading) {
      children.add(
        const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    } else if (account.value == null) {
      children.add(_SignInCard(reconnect: settings.role != null));
    } else if (settings.role == null) {
      children.add(const _RoleChoice());
    } else {
      if (sync.needsReconnect) children.add(const _SignInCard(reconnect: true));
      children.add(
        settings.role == SheetsRole.organiser
            ? const _OrganiserView()
            : const _MemberView(),
      );
      children.add(const SizedBox(height: 16));
      children.add(_SyncFooter(state: sync, account: account.value!.email));
    }
    children.add(const SizedBox(height: 12));
    children.add(
      Text(
        'Updates reach the organiser after the next sync, a few minutes, not live. Nothing stops a family member from changing their own sheet by hand; the app overwrites such edits on its next sync. Google limits how often an app may read and write; the app stays far below that for a family.',
        style: TextStyle(fontSize: 12, color: t.muted),
      ),
    );

    return AdaptivePage(
      header: PageHeader(
        title: 'Family',
        onBackWhenCompact: () => context.go('/home'),
      ),
      children: children,
    );
  }
}

class _SignInCard extends ConsumerStatefulWidget {
  const _SignInCard({required this.reconnect});
  final bool reconnect;

  @override
  ConsumerState<_SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<_SignInCard> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    final auth = ref.read(googleAuthProvider);
    if (auth == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.signIn();
      if (widget.reconnect) {
        unawaited(ref.read(sheetsSyncProvider.notifier).syncNow());
      }
    } on GoogleAuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Google sign-in did not work. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.reconnect ? 'Reconnect to Google' : 'Sign in with Google',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.reconnect
                  ? 'Google access was removed or expired, so syncing stopped. Your expenses on this device are safe.'
                  : 'Your expenses are kept in a Google Sheet in your own Google account. Sign in to start. The app only asks for the sheets it creates and the sheets family members share with you.',
              style: TextStyle(fontSize: 14, color: t.muted),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('sign-in-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ],
            const SizedBox(height: 12),
            PillButton(
              key: const ValueKey('google-sign-in'),
              label: widget.reconnect ? 'Reconnect' : 'Sign in with Google',
              busy: _busy,
              onTap: _signIn,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChoice extends ConsumerWidget {
  const _RoleChoice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    void choose(SheetsRole role) => ref
        .read(sheetsSettingsProvider.notifier)
        .update((s) => s.copyWith(role: role));
    Widget option(Key key, String title, String body, SheetsRole role) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SurfaceCard(
            onTap: () => choose(role),
            semanticLabel: '$title. $body',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                key: key,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(fontSize: 14, color: t.muted)),
                ],
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How will you use the app?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 12),
        option(
          const ValueKey('role-organiser'),
          'I run the household',
          'See every family member\'s spending, set budgets, goals and bills, and approve suggestions.',
          SheetsRole.organiser,
        ),
        option(
          const ValueKey('role-member'),
          'I am a family member',
          'Keep my own expenses, share them with the person who runs the household, and suggest changes.',
          SheetsRole.member,
        ),
      ],
    );
  }
}

// ---- Organiser ---------------------------------------------------------------------------------

class _OrganiserView extends ConsumerStatefulWidget {
  const _OrganiserView();

  @override
  ConsumerState<_OrganiserView> createState() => _OrganiserViewState();
}

class _OrganiserViewState extends ConsumerState<_OrganiserView> {
  String? _invite;
  String? _inviteError;
  String? _addError;
  bool _busy = false;

  Future<void> _createInvite() async {
    final service = ref.read(pairingServiceProvider);
    if (service == null) return;
    setState(() {
      _busy = true;
      _inviteError = null;
    });
    try {
      final code = await service.createInvite();
      if (mounted) setState(() => _invite = code);
    } on Object {
      if (mounted) {
        setState(
          () => _inviteError = 'Could not create the invite. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addMember(String code) async {
    final service = ref.read(pairingServiceProvider);
    if (service == null) return;
    setState(() => _addError = null);
    try {
      final pair = await service.addMember(code);
      if (mounted) {
        setState(() => _invite = null);
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('${pair.name} is paired')));
        unawaited(ref.read(sheetsSyncProvider.notifier).syncNow());
      }
    } on PairingError catch (e) {
      if (mounted) setState(() => _addError = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _addError =
              'Could not pair. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pairs = ref.watch(sheetPairsProvider).value ?? const <SheetPairRow>[];
    final pending = ref.watch(pendingSuggestionCountProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Family members'),
        if (pairs.isEmpty)
          SurfaceCard(
            child: Text(
              'Nobody is paired yet. Create an invite and send the code to a family member.',
              style: TextStyle(fontSize: 14, color: t.muted),
            ),
          )
        else
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [for (final p in pairs) _PairTile(pair: p)],
            ),
          ),
        const SizedBox(height: 16),
        const _SectionTitle('Invite a family member'),
        if (_invite == null)
          PillButton(
            key: const ValueKey('create-invite'),
            label: 'Create invite code',
            busy: _busy,
            onTap: _createInvite,
          )
        else
          _CodeCard(
            key: const ValueKey('invite-card'),
            title: 'Invite code',
            help: 'Give this to the family member. It works once and expires in 24 hours. They open Family, choose "Join with a code", and then show you their own code to enter below.',
            code: _invite!,
          ),
        if (_inviteError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _inviteError!,
              style: TextStyle(fontSize: 13, color: t.rose),
            ),
          ),
        const SizedBox(height: 16),
        const _SectionTitle('Add a member'),
        _CodeInput(
          key: const ValueKey('member-code-input'),
          hint: 'Paste the member\'s code',
          action: 'Add member',
          error: _addError,
          onSubmit: _addMember,
        ),
        const SizedBox(height: 16),
        _LinkRow(
          key: const ValueKey('open-suggestions'),
          icon: Icons.inbox_outlined,
          label: pending == 0
              ? 'Suggestions'
              : 'Suggestions ($pending waiting)',
          onTap: () => context.push('/suggestions'),
        ),
      ],
    );
  }
}

class _PairTile extends ConsumerWidget {
  const _PairTile({required this.pair});
  final SheetPairRow pair;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final (label, color) = switch (pair.status) {
      'active' => (
        pair.lastSyncedAt == null ? 'Paired, not read yet' : 'Up to date',
        t.primary,
      ),
      'accessRemoved' => ('Access removed', t.rose),
      _ => ('No longer shared', t.muted),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pair.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                Text(
                  '${pair.memberEmail} · $label',
                  key: ValueKey('pair-status-${pair.memberEmail}'),
                  style: TextStyle(fontSize: 13, color: color),
                ),
              ],
            ),
          ),
          if (pair.status != 'unpaired')
            TextLinkButton(
              label: 'Unpair',
              onTap: () => _confirmUnpair(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmUnpair(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unpair ${pair.name}?'),
        content: const Text(
          'They lose access to the household sheet and the app stops reading their sheet. Expenses already imported stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-unpair'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(pairingServiceProvider)?.unpairMember(pair.memberEmail);
    }
  }
}

// ---- Member ------------------------------------------------------------------------------------

class _MemberView extends ConsumerStatefulWidget {
  const _MemberView();

  @override
  ConsumerState<_MemberView> createState() => _MemberViewState();
}

class _MemberViewState extends ConsumerState<_MemberView> {
  String? _error;

  Future<void> _join(String text) async {
    final service = ref.read(pairingServiceProvider);
    if (service == null) return;
    setState(() => _error = null);
    final InviteCode invite;
    try {
      invite = service.previewInvite(text);
    } on PairingError catch (e) {
      setState(() => _error = e.message);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Share your expenses?'),
        content: Text(
          'Share your expenses with ${invite.organiserEmail} (read only)? They can see your expense sheet but cannot change it. You can stop at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const ValueKey('confirm-share'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Share'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await service.joinWithInvite(text);
      if (mounted) unawaited(ref.read(sheetsSyncProvider.notifier).syncNow());
    } on PairingError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not share. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final settings = ref.watch(sheetsSettingsProvider);
    ref.watch(googleAccountProvider);
    final service = ref.watch(pairingServiceProvider);
    final myCode = service?.currentMemberCode();
    final mine =
        ref.watch(suggestionsListProvider).value ?? const <SuggestionRow>[];
    final waiting = mine.where((s) => s.status == 'pending').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!settings.isPaired) ...[
          const _SectionTitle('Join with a code'),
          _CodeInput(
            key: const ValueKey('invite-code-input'),
            hint: 'Paste the invite code',
            action: 'Join',
            error: _error,
            onSubmit: _join,
          ),
          const SizedBox(height: 8),
          Text(
            'Your expenses are saved in your own Google Sheet from now on, even before you join.',
            style: TextStyle(fontSize: 13, color: t.muted),
          ),
        ] else ...[
          const _SectionTitle('Sharing'),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your expenses are shared with ${settings.organiserEmail}',
                  key: const ValueKey('sharing-with'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Read only. They do not see anyone else\'s spending, and nobody else sees yours.',
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (myCode != null)
            _CodeCard(
              key: const ValueKey('member-code-card'),
              title: 'Your code',
              help: 'Show this to the person who runs the household. They scan it or paste it under "Add a member" to finish pairing.',
              code: myCode,
            ),
          const SizedBox(height: 12),
          PillButton(
            key: const ValueKey('stop-sharing'),
            label: 'Stop sharing',
            style: PillStyle.outlined,
            onTap: () => _confirmLeave(context),
          ),
          const SizedBox(height: 16),
          _LinkRow(
            key: const ValueKey('open-suggestions'),
            icon: Icons.lightbulb_outline,
            label: waiting == 0
                ? 'Suggest a change'
                : 'Suggestions ($waiting waiting)',
            onTap: () => context.push('/suggestions'),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'The organiser loses access to your sheet. Your expenses stay on this device and in your sheet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-leave'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(pairingServiceProvider)?.leave();
  }
}

// ---- Shared pieces -----------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: context.tokens.text,
        ),
      ),
    ),
  );
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
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
    return SurfaceCard(
      onTap: onTap,
      semanticLabel: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        child: Row(
          children: [
            Icon(icon, color: t.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 15, color: t.text)),
            ),
            Icon(Icons.chevron_right, color: t.muted),
          ],
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({
    super.key,
    required this.title,
    required this.help,
    required this.code,
  });
  final String title;
  final String help;
  final String code;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(help, style: TextStyle(fontSize: 13, color: t.muted)),
          const SizedBox(height: 12),
          Center(
            child: Semantics(
              label: '$title as a QR code',
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: code,
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            code,
            key: const ValueKey('code-text'),
            maxLines: 3,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          PillButton(
            key: const ValueKey('copy-code'),
            label: 'Copy code',
            style: PillStyle.outlined,
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(
                  context,
                )?.showSnackBar(const SnackBar(content: Text('Code copied')));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _CodeInput extends ConsumerStatefulWidget {
  const _CodeInput({
    super.key,
    required this.hint,
    required this.action,
    required this.onSubmit,
    this.error,
  });
  final String hint;
  final String action;
  final String? error;
  final Future<void> Function(String code) onSubmit;

  @override
  ConsumerState<_CodeInput> createState() => _CodeInputState();
}

class _CodeInputState extends ConsumerState<_CodeInput> {
  final _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit([String? text]) async {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scan = ref.watch(qrScanProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: widget.hint,
          controller: _controller,
          onSubmitted: _submit,
        ),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.error!,
              key: const ValueKey('code-error'),
              style: TextStyle(fontSize: 13, color: t.rose),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: PillButton(
                key: const ValueKey('code-submit'),
                label: widget.action,
                busy: _busy,
                onTap: _submit,
              ),
            ),
            if (scan != null) ...[
              const SizedBox(width: 8),
              PillButton(
                key: const ValueKey('code-scan'),
                label: 'Scan',
                style: PillStyle.outlined,
                icon: Icons.qr_code_scanner,
                onTap: () async {
                  final text = await scan(context);
                  if (text != null) {
                    _controller.text = text;
                    await _submit(text);
                  }
                },
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SyncFooter extends ConsumerWidget {
  const _SyncFooter({required this.state, required this.account});
  final SheetsSyncState state;
  final String account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final last = state.lastSyncedAt;
    final text = state.syncing
        ? 'Syncing…'
        : state.error ?? (last == null ? 'Not synced yet' : 'Synced');
    return Row(
      children: [
        Expanded(
          child: Text(
            '$account · $text',
            key: const ValueKey('sync-status'),
            style: TextStyle(
              fontSize: 13,
              color: state.error == null ? t.muted : t.rose,
            ),
          ),
        ),
        TextLinkButton(
          label: 'Sync now',
          onTap: () =>
              ref.read(sheetsSyncProvider.notifier).syncNow(force: true),
        ),
        TextLinkButton(
          label: 'Sign out',
          onTap: () => unawaited(
            ref.read(googleAuthProvider)?.signOut() ?? Future.value(),
          ),
        ),
      ],
    );
  }
}
