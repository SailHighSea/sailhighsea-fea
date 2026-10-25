import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';
import '../../family/member_providers.dart';
import '../overview_providers.dart';

/// Home's "See everyone" card: the family's total this month, and a way into the overview.
class EveryoneCard extends ConsumerWidget {
  const EveryoneCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final money = ref.watch(moneyFormatterProvider);
    final overview = ref.watch(overviewProvider).value;
    final members = ref.watch(membersProvider).value ?? const [];
    final total = overview == null
        ? ''
        : ' · ${money.formatWhole(overview.totalCents)} this month';
    return SurfaceCard(
      key: const ValueKey('see-everyone'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      onTap: onTap,
      semanticLabel: 'See everyone. ${members.length} members$total',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTapTarget),
        child: ExcludeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See everyone',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                    Text(
                      '${members.length} members$total',
                      style: TextStyle(fontSize: 13, color: t.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}
