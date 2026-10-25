import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/auth_providers.dart';
import '../../family/member_providers.dart';
import '../overview_providers.dart';

/// "Everyone, You, Maya, Sam": narrows every number on the page to one person. Shown only to
/// people who may see everyone's spending and only when there is someone else.
class MemberFilterChips extends ConsumerWidget {
  const MemberFilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canSeeEveryoneProvider)) return const SizedBox.shrink();
    final members = ref.watch(membersProvider).value ?? const <MemberRow>[];
    final me = ref.watch(currentUserIdProvider);
    final selected = ref.watch(activeMemberFilterProvider);
    final notifier = ref.read(memberFilterProvider.notifier);
    // You first, then everyone else in the order the household lists them.
    final ordered = [
      ...members.where((m) => m.userId == me),
      ...members.where((m) => m.userId != me),
    ];
    return Semantics(
      container: true,
      label: 'Show spending of',
      child: SingleChildScrollView(
        key: const ValueKey('member-filter'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              key: const ValueKey('member-chip-all'),
              label: 'Everyone',
              selected: selected == null,
              onTap: () => notifier.select(null),
            ),
            for (final m in ordered) ...[
              const SizedBox(width: 8),
              _Chip(
                key: ValueKey('member-chip-${m.userId}'),
                label: m.userId == me ? 'You' : m.displayName,
                selected: selected == m.userId,
                onTap: () => notifier.select(m.userId),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? t.primary : t.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? t.primary : t.chipBorder),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kMinTapTarget,
              minWidth: kMinTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? t.onPrimary : t.text,
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
