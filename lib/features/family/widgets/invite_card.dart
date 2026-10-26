import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/time.dart';
import '../../../core/widgets/dashed_box.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/segmented_pills.dart';
import '../../../core/widgets/surface_card.dart';
import '../data/household_remote.dart';
import '../domain/role.dart';
import '../invite_controller.dart';

/// "Invite someone": pick a role, create a code, copy or share it. The code is shown once
/// (only a hash is stored); open codes below it can be revoked.
class InviteCard extends ConsumerWidget {
  const InviteCard({super.key, this.showTitle = false});

  /// The wide layouts put the title inside the card; the phone has it above.
  final bool showTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final state = ref.watch(inviteControllerProvider);
    final controller = ref.read(inviteControllerProvider.notifier);
    final now = ref.watch(clockProvider)();
    final created = state.created;
    final pending = ref.watch(pendingInvitesProvider).value ?? const [];

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      radius: AppRadii.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            Semantics(
              header: true,
              child: Text(
                'Invite someone',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SegmentedPills(
            labels: [for (final r in Role.invitable) r.label],
            selected: Role.invitable.indexOf(state.role),
            onChanged: (i) => controller.setRole(Role.invitable[i]),
          ),
          const SizedBox(height: 16),
          DashedBox(
            color: t.grey,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            child: created == null
                ? Center(
                    child: Text(
                      'Create a code to share',
                      style: TextStyle(fontSize: 15, color: t.muted),
                    ),
                  )
                : _CodeText(created: created, now: now),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                state.error!,
                key: const ValueKey('invite-error'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.rose,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (created == null)
            PillButton(
              key: const ValueKey('invite-create'),
              label: 'Create code',
              busy: state.busy,
              onTap: controller.create,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    key: const ValueKey('invite-copy'),
                    label: 'Copy code',
                    onTap: () => _copy(context, created),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    key: const ValueKey('invite-share'),
                    label: 'Share',
                    style: PillStyle.outlined,
                    onTap: () => _share(context, created),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            PillButton(
              key: const ValueKey('invite-new'),
              label: 'Generate a new code',
              style: PillStyle.text,
              busy: state.busy,
              onTap: controller.create,
            ),
          ],
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(color: t.border, height: 1),
            const SizedBox(height: 12),
            Text(
              'Open codes',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.muted,
              ),
            ),
            for (final invite in pending)
              _PendingRow(
                key: ValueKey('pending-${invite.id}'),
                invite: invite,
                now: now,
                onRevoke: () => _revoke(context, ref, invite),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context, CreatedInvite invite) async {
    await Clipboard.setData(ClipboardData(text: invite.display));
    if (!context.mounted) return;
    _snack(context, 'Code copied');
  }

  Future<void> _share(BuildContext context, CreatedInvite invite) async {
    final text =
        'Join our household on $kAppName with this code: ${invite.display}. '
        'It works once and expires in 24 hours.';
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } on Object {
      // No share sheet on this platform: put the message on the clipboard instead.
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _snack(context, 'Message copied');
    }
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    PendingInvite invite,
  ) async {
    final error = await ref
        .read(inviteControllerProvider.notifier)
        .revoke(invite.id);
    if (context.mounted) _snack(context, error ?? 'Code revoked');
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CodeText extends StatelessWidget {
  const _CodeText({required this.created, required this.now});

  final CreatedInvite created;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label:
          'Invite code ${created.code.split('').join(' ')}. One use. Expires in ${expiresInLabel(created.expiresAt, now)}.',
      child: ExcludeSemantics(
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                created.display,
                key: const ValueKey('invite-code'),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'One use · expires in ${expiresInLabel(created.expiresAt, now)}',
              style: TextStyle(fontSize: 13, color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    super.key,
    required this.invite,
    required this.now,
    required this.onRevoke,
  });

  final PendingInvite invite;
  final DateTime now;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kMinTapTarget),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${invite.role.label} · expires in ${expiresInLabel(invite.expiresAt, now)}',
              style: TextStyle(fontSize: 14, color: t.text),
            ),
          ),
          PillButton(
            label: 'Revoke',
            semanticLabel: 'Revoke ${invite.role.label} code',
            style: PillStyle.danger,
            height: kMinTapTarget,
            onTap: onRevoke,
          ),
        ],
      ),
    );
  }
}

/// "24 hours", "3 hours", "40 minutes", "less than a minute".
String expiresInLabel(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  if (left.inMinutes < 1) return 'less than a minute';
  if (left.inMinutes < 60) return '${left.inMinutes} minutes';
  final hours = (left.inMinutes / 60).round();
  return hours == 1 ? '1 hour' : '$hours hours';
}
