import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/page_layout.dart';
import '../../core/layout/window_class.dart';
import '../../core/money/money_format.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/month_navigator.dart';
import '../../core/widgets/surface_card.dart';
import '../family/member_providers.dart';
import '../overview/widgets/member_filter_chips.dart';
import 'data/day_format.dart';
import 'expense_list_providers.dart';
import 'expense_providers.dart';

/// All expenses of the selected month with search, a category filter, and soft delete
/// (swipe or the row menu) with undo.
class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(ExpenseRow expense) async {
    final repo = ref.read(expenseRepositoryProvider);
    await repo.softDelete(expense.id);
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('Expense deleted'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restore(expense.id),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final month = ref.watch(selectedMonthProvider);
    final months = ref.read(selectedMonthProvider.notifier);
    final filter = ref.watch(expenseFilterProvider);
    final filterController = ref.read(expenseFilterProvider.notifier);
    final expenses = ref.watch(filteredExpensesProvider);
    final categories =
        ref.watch(categoriesProvider).value ?? const <CategoryRow>[];
    final money = ref.watch(moneyFormatterProvider);
    final now = ref.watch(clockProvider)();
    final addedByLabel = ref.watch(addedByLabelProvider);
    final permissions = ref.watch(permissionsProvider);
    final categoryById = {for (final c in categories) c.id: c};

    return AdaptivePage(
      header: PageHeader(
        title: 'Expenses',
        onBack: context.layout.isCompact ? () => context.go('/home') : null,
        trailing: permissions.canWriteExpenses
            ? _AddButton(onTap: () => context.push('/add'))
            : null,
      ),
      children: [
        MonthNavigator(
          month: month,
          onPrevious: months.previous,
          onNext: months.next,
          titleSize: 18,
        ),
        if (ref.watch(canSeeEveryoneProvider)) ...[
          const SizedBox(height: 12),
          const MemberFilterChips(),
        ],
        const SizedBox(height: 12),
        _SearchField(
          controller: _search,
          onChanged: filterController.setQuery,
          onClear: () {
            _search.clear();
            filterController.setQuery('');
          },
          hasText: filter.query.isNotEmpty,
        ),
        const SizedBox(height: 12),
        _CategoryFilter(
          categories: categories,
          selectedId: filter.categoryId,
          onSelect: filterController.setCategory,
        ),
        const SizedBox(height: 16),
        expenses.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text(
            'Could not load expenses: $e',
            style: TextStyle(color: t.rose),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return SurfaceCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      filter.query.isNotEmpty || filter.categoryId != null
                          ? 'No expenses match your search'
                          : 'No expenses this month',
                      style: TextStyle(fontSize: 15, color: t.muted),
                    ),
                  ),
                ),
              );
            }
            final total = rows.fold<int>(0, (sum, e) => sum + e.amountCents);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    '${money.format(total)} · ${rows.length} ${rows.length == 1 ? 'expense' : 'expenses'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.muted,
                    ),
                  ),
                ),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        _ExpenseTile(
                          key: ValueKey(rows[i].id),
                          expense: rows[i],
                          category: categoryById[rows[i].categoryId],
                          money: money,
                          now: now,
                          addedBy: addedByLabel(rows[i].createdBy),
                          showDivider: i > 0,
                          canEdit: permissions.canWriteExpenses,
                          onEdit: () =>
                              context.push('/expenses/${rows[i].id}/edit'),
                          onDelete: () => _delete(rows[i]),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: 'Add expense',
      excludeSemantics: true,
      child: Material(
        color: t.primary,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  '+ Add',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.onPrimary,
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

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.chipBorder),
      ),
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: t.muted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: const Key('expense-search'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(fontSize: 15, color: t.text),
              cursorColor: t.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search notes, categories or people',
                hintStyle: TextStyle(fontSize: 15, color: t.muted),
              ),
            ),
          ),
          if (hasText)
            Semantics(
              button: true,
              label: 'Clear search',
              excludeSemantics: true,
              child: InkResponse(
                onTap: onClear,
                radius: 22,
                child: SizedBox(
                  width: kMinTapTarget,
                  height: kMinTapTarget,
                  child: Icon(Icons.close, size: 20, color: t.muted),
                ),
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  final List<CategoryRow> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final chips = <(String?, String)>[
      (null, 'All'),
      for (final c in categories) (c.id, c.name),
    ];
    return SizedBox(
      height: kMinTapTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = context.tokens;
          final (id, label) = chips[i];
          final selected = id == selectedId;
          return Semantics(
            button: true,
            selected: selected,
            label: id == null ? 'All categories' : 'Category $label',
            excludeSemantics: true,
            child: Material(
              color: selected ? t.navActiveBackground : t.surface,
              shape: StadiumBorder(
                side: BorderSide(
                  color: selected ? t.primary : t.chipBorder,
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected ? t.navActiveText : t.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

enum _RowAction { edit, delete }

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    super.key,
    required this.expense,
    required this.category,
    required this.money,
    required this.now,
    required this.addedBy,
    required this.showDivider,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final ExpenseRow expense;
  final CategoryRow? category;
  final MoneyFormatter money;
  final DateTime now;
  final String addedBy;
  final bool showDivider;

  /// View-only members see the row but cannot open, swipe or delete it.
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final categoryName = category?.name ?? 'Other';
    final title = expense.note.isEmpty ? categoryName : expense.note;
    final date = relativeDateLabel(parseDay(expense.spentOn), now);
    final amount = money.format(-expense.amountCents);
    final row = DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: showDivider ? Border(top: BorderSide(color: t.border)) : null,
      ),
      child: Semantics(
        container: true,
        label: '$title, $categoryName, $date, $addedBy, $amount',
        child: InkWell(
          onTap: canEdit ? onEdit : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: t.categoryColor(category?.color ?? 'other'),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          Text(
                            '$categoryName · $date · $addedBy',
                            style: TextStyle(fontSize: 13, color: t.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                  ),
                ),
                if (canEdit)
                  PopupMenuButton<_RowAction>(
                    tooltip: 'More actions for $title',
                    icon: Icon(Icons.more_vert, color: t.muted),
                    onSelected: (action) =>
                        action == _RowAction.edit ? onEdit() : onDelete(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _RowAction.edit,
                        height: kMinTapTarget,
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: _RowAction.delete,
                        height: kMinTapTarget,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!canEdit) return row;
    return Dismissible(
      key: ValueKey('dismiss-${expense.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: t.rose,
        child: Icon(Icons.delete_outline, color: t.onPrimary),
      ),
      child: row,
    );
  }
}
