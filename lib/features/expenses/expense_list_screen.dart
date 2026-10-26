import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../import/category_guess.dart';

import 'widgets/new_category.dart';
import '../../core/widgets/pill_button.dart';

import '../../core/widgets/async_placeholder.dart';

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
import '../../core/widgets/category_badge.dart';
import '../../core/widgets/context_menu_region.dart';
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
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Ctrl or Cmd + F from another page opens the list and lands here.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeFocusRequest());
  }

  void _takeFocusRequest() {
    if (!mounted || !ref.read(searchFocusRequestProvider)) return;
    _searchFocus.requestFocus();
    ref.read(searchFocusRequestProvider.notifier).clear();
  }

  @override
  void dispose() {
    _searchFocus.dispose();
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

  Future<void> _pickRange(DateTimeRange? current) async {
    final now = ref.read(clockProvider)();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: current,
      helpText: 'From and to',
      saveText: 'Show',
    );
    if (picked != null) ref.read(expenseRangeProvider.notifier).set(picked);
  }

  bool _selecting = false;
  final _selected = <String>{};

  void _startSelecting([String? first]) => setState(() {
    _selecting = true;
    if (first != null) _selected.add(first);
  });

  /// Selects every listed expense that looks like [source]: the same shop (same words in the
  /// note, ignoring digits and punctuation), or the same category when there is no note.
  void _selectSimilar(
    ExpenseRow source,
    List<ExpenseRow> rows,
    bool Function(String? createdBy) canEdit,
  ) {
    final key = descriptionKey(source.note);
    bool same(ExpenseRow e) => key.isEmpty
        ? e.note.trim().isEmpty && e.categoryId == source.categoryId
        : descriptionKey(e.note) == key;
    setState(() {
      _selecting = true;
      for (final e in rows) {
        if (e.id == source.id || (same(e) && canEdit(e.createdBy))) {
          _selected.add(e.id);
        }
      }
    });
  }

  void _stopSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Future<void> _deleteSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final repo = ref.read(expenseRepositoryProvider);
    await repo.softDeleteMany(ids);
    _stopSelecting();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${ids.length} ${ids.length == 1 ? 'expense' : 'expenses'} deleted',
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => repo.restoreMany(ids),
          ),
        ),
      );
  }

  Future<void> _changeCategory(
    List<CategoryRow> categories,
    List<ExpenseRow> rows,
    bool canAdd,
  ) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final categoryId = await showDialog<String>(
      context: context,
      builder: (_) => _ChangeCategoryDialog(
        categories: categories,
        canAdd: canAdd,
        count: ids.length,
      ),
    );
    if (categoryId == null || !mounted) return;
    await ref.read(expenseRepositoryProvider).setCategoryMany(ids, categoryId);
    // The shops that were moved are remembered for next time.
    final rules = ref.read(categoryRuleRepositoryProvider);
    await rules.rememberAll([
      for (final e in rows)
        if (_selected.contains(e.id) &&
            e.note.trim().isNotEmpty &&
            categoryId != otherCategoryId)
          (e.note, categoryId),
    ]);
    _stopSelecting();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${ids.length} ${ids.length == 1 ? 'expense' : 'expenses'} moved',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    ref.listen(searchFocusRequestProvider, (_, wanted) {
      if (wanted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _takeFocusRequest(),
        );
      }
    });
    final range = ref.watch(expenseRangeProvider);
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
    final canEdit = ref.watch(canEditExpenseProvider);
    final categoryById = {for (final c in categories) c.id: c};

    return AdaptivePage(
      header: PageHeader(
        title: 'Expenses',
        onBack: context.layout.isCompact ? () => context.go('/home') : null,
        trailing: permissions.canWriteExpenses
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PillAction(
                    key: ValueKey(
                      _selecting ? 'select-cancel' : 'select-start',
                    ),
                    label: _selecting ? 'Cancel' : 'Select',
                    onTap: _selecting ? _stopSelecting : _startSelecting,
                  ),
                  if (!_selecting) ...[
                    const SizedBox(width: 8),
                    _AddButton(onTap: () => context.push('/add')),
                  ],
                ],
              )
            : null,
      ),
      children: [
        if (range == null)
          MonthNavigator(
            month: month,
            onPrevious: months.previous,
            onNext: months.next,
            titleSize: 18,
          )
        else
          _RangeBar(
            range: range,
            onChange: () => _pickRange(range),
            onClear: ref.read(expenseRangeProvider.notifier).clear,
          ),
        if (range == null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextLinkButton(
              key: const ValueKey('range-start'),
              label: 'Choose a date range',
              onTap: () => _pickRange(null),
            ),
          ),
        if (ref.watch(canSeeEveryoneProvider)) ...[
          const SizedBox(height: 12),
          const MemberFilterChips(),
        ],
        const SizedBox(height: 12),
        _SearchField(
          controller: _search,
          focusNode: _searchFocus,
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
          loading: () => const AsyncPlaceholder(what: 'expenses'),
          error: (e, _) => AsyncPlaceholder(
            what: 'expenses',
            error: e,
            onRetry: () => ref.invalidate(filteredExpensesProvider),
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
                if (_selecting) ...[
                  _SelectionBar(
                    count: _selected.length,
                    total: rows.where((e) => canEdit(e.createdBy)).length,
                    onSelectAll: () => setState(() {
                      final all = rows
                          .where((e) => canEdit(e.createdBy))
                          .map((e) => e.id)
                          .toSet();
                      if (_selected.containsAll(all)) {
                        _selected.clear();
                      } else {
                        _selected.addAll(all);
                      }
                    }),
                    onCategory: () => _changeCategory(
                      categories,
                      rows,
                      permissions.canManageCategories,
                    ),
                    onDelete: _deleteSelected,
                  ),
                  const SizedBox(height: 12),
                ],
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
                          canEdit: canEdit(rows[i].createdBy),
                          selecting: _selecting,
                          selected: _selected.contains(rows[i].id),
                          onToggle: () => _toggle(rows[i].id),
                          onLongPress: () => _startSelecting(rows[i].id),
                          onSelectSimilar: () =>
                              _selectSimilar(rows[i], rows, canEdit),
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
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
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
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              style: TextStyle(fontSize: 15, color: t.text),
              cursorColor: t.primary,
              decoration: InputDecoration(
                isDense: true,
                constraints: const BoxConstraints(minHeight: kMinTapTarget),
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
    final t = context.tokens;
    final chips = <(String?, String)>[
      (null, 'All'),
      for (final c in categories) (c.id, c.name),
    ];
    // Wrapped, so every category is visible and none is cut off at the edge.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (id, label) in chips)
          Semantics(
            button: true,
            selected: id == selectedId,
            label: id == null ? 'All categories' : 'Category $label',
            excludeSemantics: true,
            child: Material(
              color: id == selectedId ? t.navActiveBackground : t.surface,
              shape: StadiumBorder(
                side: BorderSide(
                  color: id == selectedId ? t.primary : t.chipBorder,
                  width: id == selectedId ? 2 : 1,
                ),
              ),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onSelect(id),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: id == selectedId
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: id == selectedId ? t.navActiveText : t.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _RowAction { edit, selectSimilar, delete }

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
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
    required this.onEdit,
    required this.onSelectSimilar,
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

  /// Select-many mode: a checkbox on rows that can be changed; tapping toggles it.
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;
  final VoidCallback onEdit;
  final VoidCallback onSelectSimilar;
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
          onTap: selecting
              ? (canEdit ? onToggle : null)
              : (canEdit ? onEdit : null),
          onLongPress: !selecting && canEdit ? onLongPress : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Row(
              children: [
                if (selecting)
                  SizedBox(
                    width: kMinTapTarget,
                    child: canEdit
                        ? Semantics(
                            container: true,
                            excludeSemantics: true,
                            checked: selected,
                            label: 'Select $title',
                            onTap: onToggle,
                            child: Checkbox(
                              key: ValueKey('select-${expense.id}'),
                              value: selected,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.padded,
                              onChanged: (_) => onToggle(),
                            ),
                          )
                        : null,
                  ),
                CategoryBadge(
                  icon: category?.icon,
                  colorKey: category?.color ?? 'other',
                  size: 36,
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
                if (canEdit && !selecting)
                  PopupMenuButton<_RowAction>(
                    tooltip: 'More actions for $title',
                    icon: Icon(Icons.more_vert, color: t.muted),
                    onSelected: (action) => switch (action) {
                      _RowAction.edit => onEdit(),
                      _RowAction.selectSimilar => onSelectSimilar(),
                      _RowAction.delete => onDelete(),
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _RowAction.edit,
                        height: kMinTapTarget,
                        child: Text('Edit'),
                      ),
                      PopupMenuItem(
                        value: _RowAction.selectSimilar,
                        height: kMinTapTarget,
                        child: Text('Select similar'),
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
    if (!canEdit || selecting) return row;
    return ContextMenuRegion(
      items: [
        ContextMenuItem('Edit', onEdit),
        ContextMenuItem('Select similar', onSelectSimilar),
        ContextMenuItem('Delete', onDelete, destructive: true),
      ],
      child: Dismissible(
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
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.onSelectAll,
    required this.onCategory,
    required this.onDelete,
  });

  final int count;
  final int total;
  final VoidCallback onSelectAll;
  final VoidCallback onCategory;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final none = count == 0;
    return SurfaceCard(
      key: const ValueKey('selection-bar'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  none ? 'Tap expenses to select them' : '$count selected',
                  key: const ValueKey('selected-count'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              TextLinkButton(
                key: const ValueKey('select-all'),
                label: count == total && total > 0 ? 'Clear' : 'Select all',
                onTap: onSelectAll,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  key: const ValueKey('bulk-category'),
                  label: 'Change category',
                  height: 44,
                  style: PillStyle.outlined,
                  onTap: none ? null : onCategory,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(
                  key: const ValueKey('bulk-delete'),
                  label: 'Delete',
                  height: 44,
                  style: PillStyle.danger,
                  onTap: none ? null : onDelete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChangeCategoryDialog extends StatefulWidget {
  const _ChangeCategoryDialog({
    required this.categories,
    required this.canAdd,
    required this.count,
  });

  final List<CategoryRow> categories;
  final bool canAdd;
  final int count;

  @override
  State<_ChangeCategoryDialog> createState() => _ChangeCategoryDialogState();
}

class _ChangeCategoryDialogState extends State<_ChangeCategoryDialog> {
  String? _choice;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Move ${widget.count} ${widget.count == 1 ? 'expense' : 'expenses'}',
      ),
      content: CategoryDropdown(
        key: const ValueKey('bulk-category-picker'),
        categories: widget.categories,
        value: _choice,
        canAdd: widget.canAdd,
        hint: 'Choose a category',
        onChanged: (v) => setState(() => _choice = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('bulk-category-apply'),
          onPressed: _choice == null
              ? null
              : () => Navigator.pop(context, _choice),
          child: const Text('Move'),
        ),
      ],
    );
  }
}

/// A small outlined pill next to the Add button (Select, Cancel).
class _PillAction extends StatelessWidget {
  const _PillAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: t.chipBorder)),
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
                    fontWeight: FontWeight.w700,
                    color: t.primary,
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

/// Shown instead of the month arrows while a custom date range is active.
class _RangeBar extends StatelessWidget {
  const _RangeBar({
    required this.range,
    required this.onChange,
    required this.onClear,
  });

  final DateTimeRange range;
  final VoidCallback onChange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    String d(DateTime x) => DateFormat('d MMM yyyy', 'en_US').format(x);
    return SurfaceCard(
      key: const ValueKey('range-bar'),
      child: Row(
        children: [
          Icon(Icons.date_range, color: t.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Change the date range',
              excludeSemantics: true,
              child: InkWell(
                onTap: onChange,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTapTarget),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${d(range.start)} to ${d(range.end)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          TextLinkButton(
            key: const ValueKey('range-clear'),
            label: 'Back to months',
            onTap: onClear,
          ),
        ],
      ),
    );
  }
}
