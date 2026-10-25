import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/progress_bar.dart';
import '../../../core/widgets/surface_card.dart';
import '../domain/insights_calculations.dart';

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.tile, required this.money});

  final StatTile tile;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final value = tile.text ?? money.formatWhole(tile.cents);
    return SurfaceCard(
      radius: AppRadii.smallCard,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      semanticLabel: '${tile.label}: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tile.label, style: TextStyle(fontSize: 12, color: t.muted)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
              ),
              if (trailing != null)
                Text(trailing!, style: TextStyle(fontSize: 13, color: t.muted)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// "Spending by category": a bar per category, longest first, in the category's colour.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.lines, required this.money});

  final List<BreakdownLine> lines;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final max = lines.isEmpty ? 1 : lines.first.cents;
    final shown = lines.take(8).toList();
    return Column(
      children: [
        for (final line in shown)
          Semantics(
            label: '${line.name}: ${money.formatWhole(line.cents)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 88,
                    child: Text(
                      line.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: t.text),
                    ),
                  ),
                  Expanded(
                    child: ProgressBar(
                      fraction: max <= 0 ? 0 : line.cents / max,
                      height: 10,
                      color: t.categoryColor(line.colorKey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 72,
                    child: Text(
                      money.formatWhole(line.cents),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Who spent what": one stacked bar split by person, with a legend.
class MemberShares extends StatelessWidget {
  const MemberShares({super.key, required this.members, required this.money});

  final List<MemberShare> members;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = [t.primary, t.amber, t.purple, t.blue, t.rose, t.grey];
    final total = members.fold<int>(0, (s, m) => s + m.cents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < members.length; i++) ...[
                  if (i > 0)
                    SizedBox(width: 2, child: ColoredBox(color: t.surface)),
                  Expanded(
                    flex: total <= 0 ? 1 : members[i].cents.clamp(1, 1 << 30),
                    child: ColoredBox(color: colors[i % colors.length]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < members.length; i++)
          Semantics(
            label: '${members[i].name}: ${money.formatWhole(members[i].cents)}',
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      members[i].name,
                      style: TextStyle(fontSize: 15, color: t.text),
                    ),
                  ),
                  Text(
                    money.formatWhole(members[i].cents),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class NoteBox extends StatelessWidget {
  const NoteBox({super.key, required this.note});

  final InsightNote note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final good = note.kind == NoteKind.good;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: good ? t.navActiveBackground : t.amber.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
      ),
      child: Text(
        note.text,
        style: TextStyle(
          fontSize: 15,
          height: 1.35,
          color: good ? t.navActiveText : t.amberText,
        ),
      ),
    );
  }
}
