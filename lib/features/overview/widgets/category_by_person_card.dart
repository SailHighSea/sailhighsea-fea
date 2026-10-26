import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money_provider.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/time.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/auth_providers.dart';
import '../../expenses/expense_providers.dart';
import '../domain/overview_calculations.dart';
import '../overview_providers.dart';

/// "Who spent it": each of the biggest categories as one bar split by person, with a legend.
/// Shown only to people who see everyone; colours match the Everyone page.
class CategoryByPersonCard extends ConsumerWidget {
  const CategoryByPersonCard({
    super.key,
    this.horizontalPadding = 16,
    this.limit = 5,
  });

  final double horizontalPadding;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final money = ref.watch(moneyFormatterProvider);
    final overview = ref.watch(overviewProvider).value;
    final expenses = ref.watch(overviewExpensesProvider).value;
    final categories = ref.watch(categoriesProvider).value;
    if (overview == null || expenses == null || categories == null) {
      return const SizedBox.shrink();
    }
    final items = buildCategoriesByPerson(
      month: ref.watch(selectedMonthProvider),
      expenses: expenses,
      categories: categories,
      currentUserId: ref.watch(currentUserIdProvider),
    ).take(limit).toList();
    final palette = [t.primary, t.amber, t.purple, t.blue, t.rose, t.grey];
    final people = overview.people;
    Color colorOf(int i) => palette[i % palette.length];

    return SurfaceCard(
      key: const ValueKey('category-by-person'),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 14,
      ),
      semanticLabel:
          'Categories by person: ${items.map((c) => '${c.name} ${money.formatWhole(c.totalCents)}').join(', ')}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Who spent it',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(
              'No spending to split yet',
              style: TextStyle(fontSize: 13, color: t.muted),
            )
          else
            for (final c in items) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                  Text(
                    money.formatWhole(c.totalCents),
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (var i = 0; i < people.length; i++)
                        if ((c.byPerson[people[i].userId] ?? 0) > 0)
                          Expanded(
                            flex: c.byPerson[people[i].userId]!,
                            child: ColoredBox(color: colorOf(i)),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (var i = 0; i < people.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colorOf(i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      people[i].name,
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
