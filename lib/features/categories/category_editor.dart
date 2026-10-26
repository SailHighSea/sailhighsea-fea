import 'package:flutter/material.dart';

import '../../core/db/app_database.dart';
import '../../core/layout/adaptive_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_style.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/category_badge.dart';
import '../../core/widgets/pill_button.dart';

/// What the editor returns. [delete] is true when the person chose Delete.
class CategoryEdit {
  const CategoryEdit({
    this.name = '',
    this.color = 'other',
    this.icon,
    this.delete = false,
  });

  final String name;
  final String color;
  final String? icon;
  final bool delete;
}

/// New category (when [existing] is null) or edit one: name, icon and colour, with a preview.
/// Delete is offered for categories other than Other.
Future<CategoryEdit?> showCategoryEditor(
  BuildContext context, {
  CategoryRow? existing,
  required String defaultColor,
}) => showAdaptiveSheet<CategoryEdit>(
  context,
  builder: (_) => _Editor(existing: existing, defaultColor: defaultColor),
);

class _Editor extends StatefulWidget {
  const _Editor({required this.existing, required this.defaultColor});
  final CategoryRow? existing;
  final String defaultColor;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late String _color = widget.existing?.color ?? widget.defaultColor;
  late String? _icon = widget.existing?.icon;
  bool _colorTouched = false;
  bool _iconTouched = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// A new category follows its name until the person picks an icon or colour themselves.
  void _nameChanged(String v) {
    if (widget.existing != null) {
      setState(() {});
      return;
    }
    final g = guessCategoryStyle(v, fallbackColor: widget.defaultColor);
    setState(() {
      if (!_iconTouched) _icon = g.icon == 'category' ? null : g.icon;
      if (!_colorTouched) _color = g.color;
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }
    Navigator.of(context)
        .pop(CategoryEdit(name: name, color: _color, icon: _icon));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final editing = widget.existing != null;
    final canDelete = editing && widget.existing!.id != otherCategoryId;
    final color = t.categoryColor(_color);
    return Column(
      key: const ValueKey('category-editor'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            editing ? 'Edit category' : 'New category',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            CategoryBadge(
              key: const ValueKey('category-preview'),
              icon: _icon,
              colorKey: _color,
              size: 52,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                key: const ValueKey('category-name'),
                label: 'Name',
                controller: _name,
                autofocus: !editing,
                textCapitalization: TextCapitalization.words,
                onChanged: _nameChanged,
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Icon', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in kCategoryIcons.entries)
              _Pick(
                key: ValueKey('icon-${e.key}'),
                label: e.key.replaceAll('_', ' '),
                selected: (_icon ?? 'category') == e.key,
                onTap: () => setState(() {
                  _icon = e.key == 'category' ? null : e.key;
                  _iconTouched = true;
                }),
                child: Icon(e.value, size: 22, color: color),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Colour', style: TextStyle(fontSize: 13, color: t.muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in kCategoryColorKeys)
              _Pick(
                key: ValueKey('color-$k'),
                label: 'Colour $k',
                selected: _color == k,
                onTap: () => setState(() {
                  _color = k;
                  _colorTouched = true;
                }),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: t.categoryColor(k),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('category-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ),
        const SizedBox(height: 14),
        PillButton(
          key: const ValueKey('category-save'),
          label: editing ? 'Save' : 'Add category',
          onTap: _save,
        ),
        if (canDelete)
          PillButton(
            key: const ValueKey('category-delete'),
            label: 'Delete category',
            style: PillStyle.danger,
            onTap: () =>
                Navigator.of(context).pop(const CategoryEdit(delete: true)),
          ),
        PillButton(
          label: 'Cancel',
          style: PillStyle.text,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: kMinTapTarget,
          height: kMinTapTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? t.navActiveBackground : t.background,
            border: Border.all(
              color: selected ? t.primary : t.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
