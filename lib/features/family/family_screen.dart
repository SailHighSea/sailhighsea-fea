import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/page_layout.dart';
import '../../core/layout/window_class.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../auth/auth_providers.dart';
import '../integrations/sheets_providers.dart';
import '../integrations/widgets/sheet_card.dart';
import 'data/household_remote.dart';
import 'domain/role.dart';
import 'domain/visibility.dart';
import 'member_providers.dart';
import 'widgets/invite_card.dart';
import 'widgets/members_card.dart';
import 'widgets/role_sheet.dart';

/// Family and sharing (Family, TabFamily and DeskFamily mockups): members with role pills,
/// the role explainer, and the invite card. What a role cannot do is not shown; the server
/// rejects it regardless.
class FamilyScreen extends ConsumerStatefulWidget {
  const FamilyScreen({super.key});

  @override
  ConsumerState<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends ConsumerState<FamilyScreen> {
  @override
  void initState() {
    super.initState();
    // Show the cached members at once, then bring them up to date.
    Future<void>.microtask(() async {
      if (ref.read(householdRemoteProvider) == null) return;
      try {
        await ref.read(householdControllerProvider).refresh();
      } on HouseholdFailure {
        // Offline: the local copy is shown.
      }
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeRole(MemberRow member) async {
    final permissions = ref.read(permissionsProvider);
    final result = await showRoleSheet(
      context,
      member: member,
      permissions: permissions,
    );
    if (result == null || !mounted) return;
    final controller = ref.read(householdControllerProvider);
    try {
      switch (result) {
        case RoleChosen(:final role):
          if (role.dbValue == member.role) return;
          await controller.setRole(member.userId, role);
          _toast('${member.displayName} is now ${role.label}');
        case VisibilityChosen(:final visibility):
          if (visibility.dbValue == member.visibility) return;
          await controller.setVisibility(member.userId, visibility);
          _toast(
            visibility == MemberVisibility.own
                ? '${member.displayName} now sees only their own spending'
                : '${member.displayName} now sees everyone\'s spending',
          );
        case RemoveChosen():
          final ok = await _confirm(
            title: 'Remove ${member.displayName}?',
            body: 'They lose access to this household straight away.',
            action: 'Remove',
          );
          if (ok != true) return;
          await controller.removeMember(member.userId);
          _toast('${member.displayName} was removed');
      }
    } on HouseholdFailure catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _leave() async {
    final ok = await _confirm(
      title: 'Leave this household?',
      body: 'You will need a new invite code to join again.',
      action: 'Leave',
    );
    if (ok != true) return;
    try {
      await ref.read(householdControllerProvider).leave();
    } on HouseholdFailure catch (e) {
      _toast(e.message);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('confirm-action'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final compact = context.layout.isCompact;
    final permissions = ref.watch(permissionsProvider);
    final members = ref.watch(membersProvider).value ?? const <MemberRow>[];
    final me = ref.watch(currentUserIdProvider);
    final signedIn = ref.watch(authServiceProvider) != null;
    final email = ref.watch(authUserProvider).value?.email;
    final myRole = ref.watch(currentRoleProvider);

    return AdaptiveTwoPane(
      secondaryWidth: 360,
      scrollWhenStacked: true,
      header: PageHeader(
        title: 'Family',
        onBack: compact ? () => context.go('/home') : null,
        trailing: compact || !signedIn
            ? null
            : TextLinkButton(
                label: 'Have a code? Join a household',
                onTap: () => context.push('/join'),
              ),
      ),
      primary: (context, mode) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!signedIn)
            const _LocalOnlyCard()
          else
            MembersCard(
              members: members,
              currentUserId: me,
              permissions: permissions,
              onChangeRole: _changeRole,
            ),
          const SizedBox(height: 14),
          const RoleLegendCard(),
          if (signedIn) ...[
            const SizedBox(height: 14),
            if (myRole != Role.owner)
              PillButton(
                key: const ValueKey('leave-household'),
                label: 'Leave household',
                style: PillStyle.danger,
                onTap: _leave,
              ),
            if (email != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Signed in as $email',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: t.muted),
                ),
              ),
            PillButton(
              key: const ValueKey('sign-out'),
              label: 'Sign out',
              style: PillStyle.text,
              onTap: () => ref.read(authServiceProvider)!.signOut(),
            ),
          ],
        ],
      ),
      secondary: (context, mode) {
        if (!signedIn) return const SizedBox.shrink();
        final stacked = mode == PaneMode.stacked;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (permissions.canInvite) ...[
              if (stacked) ...[
                const SizedBox(height: 8),
                Semantics(
                  header: true,
                  child: Text(
                    'Invite someone',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              InviteCard(showTitle: !stacked),
            ] else
              _CannotInviteCard(role: myRole),
            if (ref.watch(sheetsRemoteProvider) != null) ...[
              const SizedBox(height: 14),
              const SheetCard(),
            ],
            if (stacked) ...[
              const SizedBox(height: 16),
              Center(
                child: TextLinkButton(
                  label: 'Have a code instead? Join a household',
                  onTap: () => context.push('/join'),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _LocalOnlyCard extends StatelessWidget {
  const _LocalOnlyCard();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sharing is not set up',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This copy of the app has no Supabase connection, so everything stays on this '
            'device. Add SUPABASE_URL and SUPABASE_ANON_KEY (see supabase/README.md) to '
            'invite family and sync.',
            style: TextStyle(fontSize: 14, height: 1.35, color: t.muted),
          ),
        ],
      ),
    );
  }
}

class _CannotInviteCard extends StatelessWidget {
  const _CannotInviteCard({required this.role});

  final Role role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Text(
        'Your access is ${role.label}. Only the owner and admins can invite people or change roles.',
        key: const ValueKey('cannot-invite'),
        style: TextStyle(fontSize: 14, height: 1.35, color: t.muted),
      ),
    );
  }
}
