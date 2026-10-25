import 'package:flutter/material.dart';

import 'window_class.dart';

/// Lays [children] out in equal-width columns: [compact] columns on the phone, [medium] on
/// the rail layout and [wide] with the sidebar. Rows are as tall as their tallest card.
/// Features supply the cards; the window width is read here, not in the feature.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.compact = 1,
    this.medium = 2,
    this.wide = 3,
    this.gap = 12,
  });

  final List<Widget> children;
  final int compact;
  final int medium;
  final int wide;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final columns = switch (context.windowClass) {
      WindowClass.compact => compact,
      WindowClass.medium => medium,
      WindowClass.expanded => wide,
    };
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.skip(i).take(columns).toList();
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) SizedBox(width: gap),
                Expanded(child: c < slice.length ? slice[c] : const SizedBox()),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          rows[i],
        ],
      ],
    );
  }
}

/// A main column with a side column. On the phone they stack ([side] first when
/// [sideFirstWhenStacked]); on wider windows they sit side by side.
class PrimarySideLayout extends StatelessWidget {
  const PrimarySideLayout({
    super.key,
    required this.primary,
    required this.side,
    this.sideWidth = 340,
    this.sideFirstWhenStacked = false,
    this.gap = 16,
  });

  final Widget primary;
  final Widget side;
  final double sideWidth;
  final bool sideFirstWhenStacked;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (context.layout.isCompact) {
      final first = sideFirstWhenStacked ? side : primary;
      final second = sideFirstWhenStacked ? primary : side;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          SizedBox(height: gap),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: primary),
        SizedBox(width: gap + 8),
        SizedBox(width: sideWidth, child: side),
      ],
    );
  }
}

/// A fixed-width highlight card beside a grid of cards (Budgets: the ring beside the
/// category cards). On the phone the highlight is dropped when [hideHeroWhenStacked].
class HeroGridLayout extends StatelessWidget {
  const HeroGridLayout({
    super.key,
    required this.hero,
    required this.grid,
    this.heroWidth = 300,
    this.hideHeroWhenStacked = true,
    this.gap = 16,
  });

  final Widget hero;
  final Widget grid;
  final double heroWidth;
  final bool hideHeroWhenStacked;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (context.layout.isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!hideHeroWhenStacked) ...[hero, SizedBox(height: gap)],
          grid,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: heroWidth, child: hero),
        SizedBox(width: gap),
        Expanded(child: grid),
      ],
    );
  }
}
