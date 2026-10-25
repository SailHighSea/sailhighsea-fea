import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/time.dart';
import '../../../core/widgets/context_menu_region.dart';
import '../../../core/widgets/surface_card.dart';
import '../home_data.dart';

/// Recent expenses. [table] is the desktop layout with columns; otherwise a compact list.
class RecentCard extends StatelessWidget {
  const RecentCard({
    super.key,
    required this.items,
    required this.money,
    required this.now,
    required this.table,
    required this.onSeeAll,
    this.onOpen,
  });

  final List<RecentExpense> items;
  final MoneyFormatter money;
  final DateTime now;
  final bool table;
  final VoidCallback onSeeAll;

  /// `null` for members who cannot edit: rows are shown but do not open.
  final ValueChanged<RecentExpense>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (table) {
      return SurfaceCard(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _TableRow(
              minHeight: 40,
              cells: [
                _cell(
                  'Recent',
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                _cell(
                  'Note',
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                _cell(
                  'Category',
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                _cell(
                  'Added by',
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                ),
                _cell(
                  'Amount',
                  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.muted,
                  ),
                  right: true,
                ),
              ],
            ),
            if (items.isEmpty) _empty(t),
            for (final e in items)
              ContextMenuRegion(
                enabled: onOpen != null,
                items: [ContextMenuItem('Edit', () => onOpen!(e))],
                child: Semantics(
                  container: true,
                  button: onOpen != null,
                  excludeSemantics: true,
                  onTap: onOpen == null ? null : () => onOpen!(e),
                  label:
                      '${e.note}, ${e.categoryName}, ${relativeDateLabel(e.spentOn, now)}, ${e.addedBy}, ${money.format(e.cents)}',
                  child: InkWell(
                    onTap: onOpen == null ? null : () => onOpen!(e),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border)),
                      ),
                      child: _TableRow(
                        minHeight: 44,
                        cells: [
                          _cell(
                            relativeDateLabel(e.spentOn, now),
                            TextStyle(fontSize: 15, color: t.muted),
                          ),
                          _cell(
                            e.note,
                            TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          _cell(
                            e.categoryName,
                            TextStyle(fontSize: 15, color: t.text),
                          ),
                          _cell(
                            e.addedBy,
                            TextStyle(fontSize: 15, color: t.text),
                          ),
                          _cell(
                            money.format(-e.cents),
                            TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                            right: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recent',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ),
              TextLinkButton(label: 'See all', onTap: onSeeAll),
            ],
          ),
          if (items.isEmpty) _empty(t),
          for (final e in items)
            ContextMenuRegion(
              enabled: onOpen != null,
              items: [ContextMenuItem('Edit', () => onOpen!(e))],
              child: Semantics(
                container: true,
                button: onOpen != null,
                excludeSemantics: true,
                onTap: onOpen == null ? null : () => onOpen!(e),
                label:
                    '${e.note}, ${e.categoryName}, ${relativeDateLabel(e.spentOn, now)}, ${e.addedBy}, ${money.format(e.cents)}',
                child: InkWell(
                  onTap: onOpen == null ? null : () => onOpen!(e),
                  child: ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: t.border)),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 52),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.note,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: t.text,
                                      ),
                                    ),
                                    Text(
                                      '${e.categoryName} · ${relativeDateLabel(e.spentOn, now)} · ${e.addedBy}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: t.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                money.format(-e.cents),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: t.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(AppTokens t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      'No expenses this month',
      style: TextStyle(fontSize: 13, color: t.muted),
    ),
  );

  static _Cell _cell(String text, TextStyle style, {bool right = false}) =>
      _Cell(text, style, right);
}

class _Cell {
  const _Cell(this.text, this.style, this.right);
  final String text;
  final TextStyle style;
  final bool right;
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.cells, required this.minHeight});

  final List<_Cell> cells;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    Widget cell(_Cell c) => Text(
      c.text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: c.right ? TextAlign.right : TextAlign.left,
      style: c.style,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Row(
        children: [
          SizedBox(width: 110, child: cell(cells[0])),
          const SizedBox(width: 12),
          Expanded(child: cell(cells[1])),
          const SizedBox(width: 12),
          SizedBox(width: 140, child: cell(cells[2])),
          const SizedBox(width: 12),
          SizedBox(width: 120, child: cell(cells[3])),
          const SizedBox(width: 12),
          SizedBox(width: 120, child: cell(cells[4])),
        ],
      ),
    );
  }
}
