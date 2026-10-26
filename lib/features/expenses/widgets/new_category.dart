import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/theme/app_tokens.dart';
import '../expense_providers.dart';

/// Asks for the name of a new category. Returns the name, or null when cancelled.
Future<String?> askNewCategoryName(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const NewCategoryDialog(),
);

/// Asks for a name and creates the category. Returns it (an existing one with the same name is
/// returned instead of a duplicate), or null when cancelled.
Future<CategoryRow?> createCategoryFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final name = await askNewCategoryName(context);
  if (name == null || name.trim().isEmpty) return null;
  return ref.read(categoryRepositoryProvider).add(name);
}

class NewCategoryDialog extends StatefulWidget {
  const NewCategoryDialog({super.key});

  @override
  State<NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<NewCategoryDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      title: const Text('New category'),
      content: TextField(
        key: const Key('new-category-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'For example Pets'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('new-category-add'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// A category picker for tables and lists: every category, and "New category..." at the end when
/// the person may add one. The new category is created, selected, and offered from then on.
class CategoryDropdown extends ConsumerStatefulWidget {
  const CategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
    this.canAdd = true,
    this.hint = 'Choose…',
    this.highlight = false,
    this.enabled = true,
  });

  final List<CategoryRow> categories;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool canAdd;
  final String hint;

  /// Rose outline: this one still needs an answer.
  final bool highlight;
  final bool enabled;

  @override
  ConsumerState<CategoryDropdown> createState() => _CategoryDropdownState();
}

const _newCategoryValue = '__new_category__';

class _CategoryDropdownState extends ConsumerState<CategoryDropdown> {
  /// Categories created here that the list has not delivered yet.
  final _created = <CategoryRow>[];

  Future<void> _add() async {
    final row = await createCategoryFlow(context, ref);
    if (row == null || !mounted) return;
    if (!widget.categories.any((c) => c.id == row.id)) {
      setState(() => _created.add(row));
    }
    widget.onChanged(row.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = [
      ...widget.categories,
      for (final c in _created)
        if (!widget.categories.any((x) => x.id == c.id)) c,
    ];
    final value = all.any((c) => c.id == widget.value) ? widget.value : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: widget.highlight ? Border.all(color: t.rose, width: 1.5) : null,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            hint: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                widget.hint,
                style: TextStyle(
                  color: widget.highlight ? t.rose : t.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            items: [
              for (final c in all)
                DropdownMenuItem(
                  value: c.id,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(c.name),
                  ),
                ),
              if (widget.canAdd)
                DropdownMenuItem(
                  value: _newCategoryValue,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18, color: t.primary),
                        const SizedBox(width: 6),
                        Text(
                          'New category',
                          style: TextStyle(
                            color: t.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            onChanged: widget.enabled
                ? (v) {
                    if (v == _newCategoryValue) {
                      _add();
                    } else if (v != null) {
                      widget.onChanged(v);
                    }
                  }
                : null,
          ),
        ),
      ),
    );
  }
}
