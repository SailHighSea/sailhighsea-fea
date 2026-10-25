import 'package:flutter/material.dart';

import '../../../core/db/app_database.dart';
import '../../../core/layout/adaptive_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/pill_button.dart';
import '../domain/permissions.dart';
import '../domain/role.dart';
import '../domain/visibility.dart';

/// What the person picked in the role sheet.
sealed class RoleSheetResult {
  const RoleSheetResult();
}

class RoleChosen extends RoleSheetResult {
  const RoleChosen(this.role);
  final Role role;
}

class VisibilityChosen extends RoleSheetResult {
  const VisibilityChosen(this.visibility);
  final MemberVisibility visibility;
}

class RemoveChosen extends RoleSheetResult {
  const RemoveChosen();
}

/// "Change access" for one member: pick Admin, Can edit or View only, or remove them.
/// Promoting to Admin is just choosing Admin. Options the role may not use are not shown.
Future<RoleSheetResult?> showRoleSheet(
  BuildContext context, {
  required MemberRow member,
  required Permissions permissions,
}) {
  return showAdaptiveSheet<RoleSheetResult>(
    context,
    builder: (context) => _RoleSheet(member: member, permissions: permissions),
  );
}

class _RoleSheet extends StatelessWidget {
  const _RoleSheet({required this.member, required this.permissions});

  final MemberRow member;
  final Permissions permissions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = Role.fromDb(member.role);
    return Column(
      key: const ValueKey('role-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Access for ${member.displayName}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final role in Role.assignable)
          ChoiceTile(
            key: ValueKey('role-option-${role.dbValue}'),
            title: role.label,
            description: role.description,
            selected: role == current,
            onTap: () => Navigator.of(context).pop(RoleChosen(role)),
          ),
        if (permissions.canSetVisibility(current, isSelf: false)) ...[
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              'Can see',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 6),
          for (final v in MemberVisibility.values)
            ChoiceTile(
              key: ValueKey('visibility-option-${v.dbValue}'),
              title: v.label,
              description: v.description,
              selected: v == MemberVisibility.fromDb(member.visibility),
              onTap: () => Navigator.of(context).pop(VisibilityChosen(v)),
            ),
        ],
        if (permissions.canRemove(current, isSelf: false)) ...[
          const SizedBox(height: 8),
          PillButton(
            key: const ValueKey('remove-member'),
            label: 'Remove from household',
            style: PillStyle.danger,
            onTap: () => Navigator.of(context).pop(const RemoveChosen()),
          ),
        ],
      ],
    );
  }
}

/// One selectable row in the access sheet (a role, or what the member can see).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $description',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: selected ? t.navActiveBackground : t.background,
          borderRadius: BorderRadius.circular(AppRadii.smallCard),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.smallCard),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: selected ? t.navActiveText : t.text,
                            ),
                          ),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 13,
                              color: selected ? t.navActiveText : t.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(Icons.check_rounded, color: t.navActiveText),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
