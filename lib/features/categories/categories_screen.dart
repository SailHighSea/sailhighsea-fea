import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/page_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_style.dart';
import '../../core/widgets/async_placeholder.dart';
import '../../core/widgets/category_badge.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../expenses/data/category_repository.dart' show newCategoryColorKeys;
import '../expenses/expense_providers.dart';
import '../family/member_providers.dart';
import 'category_editor.dart';

/// Every category with its icon and colour. Owner and admin (and a person on their own device)
/// add, edit and delete; everyone else only looks.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(categoriesProvider);
    final categories = async.value;
    final t = context.tokens;
    if (categories == null) {
      return AsyncPlaceholder(
        what: 'categories',
        error: async.hasError ? async.error : null,
        onRetry: () => ref.invalidate(categoriesProvider),
      );
    }
    final canManage = ref.watch(permissionsProvider).canManageCategories;
    final repo = ref.read(categoryRepositoryProvider);
    final taken = {for (final c in categories) c.name.toLowerCase()};
    final suggestions = [
      for (final s in kSuggestedCategories)
        if (!taken.contains(s.name.toLowerCase())) s,
    ];
    String nextColor() {
      final custom = categories
          .where((c) => !c.id.startsWith('default-'))
          .length;
      return newCategoryColorKeys[custom % newCategoryColorKeys.length];
    }

    Future<void> add() async {
      final r = await showCategoryEditor(context, defaultColor: nextColor());
      if (r == null || r.delete) return;
      await repo.add(r.name, color: r.color, icon: r.icon);
    }

    Future<void> edit(CategoryRow c) async {
      final r = await showCategoryEditor(
        context,
        existing: c,
        defaultColor: c.color,
      );
      if (r == null) return;
      if (r.delete) {
        await repo.delete(c.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  'Deleted ${c.name}. Its expenses moved to Other.',
                ),
              ),
            );
        }
        return;
      }
      try {
        await repo.update(c.id, name: r.name, color: r.color, icon: r.icon);
      } on ArgumentError {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('There is already a category called ${r.name}.'),
            ),
          );
        }
      }
    }

    return AdaptivePage(
      header: PageHeader(
        title: 'Categories',
        onBackWhenCompact: () => context.go('/home'),
        trailing: canManage
            ? PillButton(
                key: const ValueKey('add-category-button'),
                label: '+ New',
                height: 44,
                onTap: add,
              )
            : null,
      ),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < categories.length; i++)
                _Row(
                  key: ValueKey('category-${categories[i].id}'),
                  category: categories[i],
                  divider: i > 0,
                  onTap: canManage ? () => edit(categories[i]) : null,
                ),
            ],
          ),
        ),
        if (canManage && suggestions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Semantics(
            header: true,
            child: Text(
              'Add a ready-made category',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in suggestions)
                _SuggestionChip(
                  key: ValueKey('suggest-${s.name}'),
                  suggestion: s,
                  onTap: () => repo.add(s.name, color: s.color, icon: s.icon),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.category,
    required this.divider,
    required this.onTap,
  });

  final CategoryRow category;
  final bool divider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: onTap != null,
      label: onTap == null ? category.name : 'Edit ${category.name}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: divider ? Border(top: BorderSide(color: t.border)) : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                CategoryBadge(icon: category.icon, colorKey: category.color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(Icons.edit_outlined, size: 20, color: t.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    super.key,
    required this.suggestion,
    required this.onTap,
  });

  final SuggestedCategory suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Add ${suggestion.name}',
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        shape: StadiumBorder(side: BorderSide(color: t.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryBadge(
                    icon: suggestion.icon,
                    colorKey: suggestion.color,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    suggestion.name,
                    style: TextStyle(fontSize: 14, color: t.text),
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
