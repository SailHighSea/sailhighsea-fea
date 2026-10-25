import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/permissions.dart';
import '../domain/role.dart';
import '../domain/visibility.dart';

/// The household's members with a role pill each (Family, TabFamily, DeskFamily mockups).
/// A role the viewer may change is a button that opens the role sheet; otherwise it is plain.
class MembersCard extends StatelessWidget {
  const MembersCard({
    super.key,
    required this.members,
    required this.currentUserId,
    required this.permissions,
    required this.onChangeRole,
  });

  final List<MemberRow> members;
  final String? currentUserId;
  final Permissions permissions;
  final ValueChanged<MemberRow> onChangeRole;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      radius: AppRadii.card,
      child: Column(
        children: [
          for (var i = 0; i < members.length; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: t.border)),
              ),
              child: MemberTile(
                key: ValueKey('member-${members[i].userId}'),
                member: members[i],
                index: i,
                isSelf: members[i].userId == currentUserId,
                canChange: permissions.canChangeRoleOf(
                  Role.fromDb(members[i].role),
                  isSelf: members[i].userId == currentUserId,
                ),
                onChangeRole: () => onChangeRole(members[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class MemberTile extends StatelessWidget {
  const MemberTile({
    super.key,
    required this.member,
    required this.index,
    required this.isSelf,
    required this.canChange,
    required this.onChangeRole,
  });

  final MemberRow member;
  final int index;
  final bool isSelf;
  final bool canChange;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final role = Role.fromDb(member.role);
    final name = isSelf ? 'You' : member.displayName;
    // Owner and admin always see everything, so only editors and viewers can be private.
    final private =
        MemberVisibility.fromDb(member.visibility) == MemberVisibility.own &&
        role != Role.owner &&
        role != Role.admin;
    final subtitle = role == Role.owner
        ? 'Household owner'
        : 'Joined ${DateFormat('d MMM', 'en_US').format(member.joinedAt)}';
    return Semantics(
      container: true,
      label:
          '$name, ${role.label}. $subtitle${private ? '. Private: sees only their own spending' : ''}',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Row(
          children: [
            ExcludeSemantics(
              child: _Avatar(member: member, index: index),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 13, color: t.muted),
                        ),
                        if (private)
                          Container(
                            key: ValueKey('private-${member.userId}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: t.amber.withValues(alpha: 0.32),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Private',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: t.amberText,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (canChange)
              _RoleButton(
                key: ValueKey('role-button-${member.userId}'),
                label: role.label,
                semanticLabel: 'Change access for $name, now ${role.label}',
                onTap: onChangeRole,
              )
            else
              _RolePill(role: role, key: ValueKey('role-${member.userId}')),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.member, required this.index});

  final MemberRow member;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isOwner = member.role == Role.owner.dbValue;
    // The owner is the dark green circle; the others take the member avatar colours in turn.
    final others = t.avatars.length > 1 ? t.avatars.sublist(1) : t.avatars;
    final bg = isOwner
        ? t.hero
        : others[(index - 1).abs() % others.length].background;
    final fg = isOwner
        ? t.heroText
        : others[(index - 1).abs() % others.length].foreground;
    final trimmed = member.displayName.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

/// The plain role label: green for the owner, quiet text for everyone else.
class _RolePill extends StatelessWidget {
  const _RolePill({super.key, required this.role});

  final Role role;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final owner = role == Role.owner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: owner ? t.navActiveBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: Text(
        role.label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: owner ? t.navActiveText : t.muted,
        ),
      ),
    );
  }
}

/// Outlined pill with a chevron: tapping it opens the role sheet.
class _RoleButton extends StatelessWidget {
  const _RoleButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: t.muted.withAlpha(120))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinTapTarget,
              minWidth: 96,
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: t.text,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The green card that explains the roles.
class RoleLegendCard extends StatelessWidget {
  const RoleLegendCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget line(String label, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: text),
          ],
        ),
        style: TextStyle(fontSize: 14, height: 1.35, color: t.navActiveText),
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: t.navActiveBackground,
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(
            'Admin',
            'full access, same as the owner, except removing the owner or deleting the household.',
          ),
          line('Can edit', 'add and change expenses.'),
          line('View only', 'see everything, change nothing.'),
        ],
      ),
    );
  }
}
