import 'package:flutter/material.dart';

import 'page_layout.dart';
import 'window_class.dart';

/// How the Home sections are arranged. Chosen here, from the window width, so the Home
/// feature itself never reads the width.
enum DashboardMode {
  /// Phone: one column.
  stacked,

  /// Tablet: hero and summary cards on the left, chart and recent list on the right.
  split,

  /// Desktop: hero beside the month chart, three cards below, recent as a table.
  wide,
}

typedef SlotBuilder = Widget Function(BuildContext context, DashboardMode mode);

/// Arranges the Home dashboard sections for the current window (docs/SPEC.md section 3
/// and the Main, Tablet and Desktop mockups). Features supply the sections.
class DashboardLayout extends StatelessWidget {
  const DashboardLayout({
    super.key,
    required this.header,
    required this.hero,
    required this.trend,
    required this.categories,
    required this.nextBill,
    required this.goal,
    required this.recent,
    this.filters,
    this.everyone,
  });

  final SlotBuilder header;
  final SlotBuilder hero;
  final SlotBuilder trend;
  final SlotBuilder categories;
  final SlotBuilder nextBill;
  final SlotBuilder goal;
  final SlotBuilder recent;

  /// A row of filter chips under the header (who's spending is shown). Absent for most people.
  final SlotBuilder? filters;

  /// A full-width "See everyone" card above the recent list. Absent for most people.
  final SlotBuilder? everyone;

  static const double _splitMinContent = 760;
  static const double _heroColumn = 380;

  DashboardMode _modeFor(WindowClass windowClass, double contentWidth) {
    return switch (windowClass) {
      WindowClass.compact => DashboardMode.stacked,
      WindowClass.medium =>
        contentWidth >= _splitMinContent
            ? DashboardMode.split
            : DashboardMode.stacked,
      WindowClass.expanded => DashboardMode.wide,
    };
  }

  @override
  Widget build(BuildContext context) {
    final metrics = context.layout;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth =
            constraints.maxWidth - metrics.pagePadding.horizontal;
        final mode = _modeFor(metrics.windowClass, contentWidth);
        final gap = metrics.isCompact ? 14.0 : 16.0;
        Widget slot(SlotBuilder s) => s(context, mode);

        Widget twoCards() => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: slot(nextBill)),
              const SizedBox(width: 12),
              Expanded(child: slot(goal)),
            ],
          ),
        );

        final List<Widget> body = switch (mode) {
          DashboardMode.stacked => [
            slot(hero),
            SizedBox(height: gap),
            slot(trend),
            SizedBox(height: gap),
            slot(categories),
            SizedBox(height: gap),
            twoCards(),
            SizedBox(height: gap),
            if (everyone != null) ...[slot(everyone!), SizedBox(height: gap)],
            slot(recent),
          ],
          DashboardMode.split => [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _heroColumn,
                  child: Column(
                    children: [
                      slot(hero),
                      SizedBox(height: gap),
                      slot(categories),
                      SizedBox(height: gap),
                      twoCards(),
                    ],
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: Column(
                    children: [
                      slot(trend),
                      SizedBox(height: gap),
                      if (everyone != null) ...[
                        slot(everyone!),
                        SizedBox(height: gap),
                      ],
                      slot(recent),
                    ],
                  ),
                ),
              ],
            ),
          ],
          DashboardMode.wide => [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: _heroColumn, child: slot(hero)),
                  SizedBox(width: gap),
                  Expanded(child: slot(trend)),
                ],
              ),
            ),
            SizedBox(height: gap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: slot(categories)),
                  SizedBox(width: gap),
                  Expanded(child: slot(nextBill)),
                  SizedBox(width: gap),
                  Expanded(child: slot(goal)),
                ],
              ),
            ),
            SizedBox(height: gap),
            if (everyone != null) ...[slot(everyone!), SizedBox(height: gap)],
            slot(recent),
          ],
        };

        return SingleChildScrollView(
          padding: metrics.pagePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  slot(header),
                  SizedBox(height: gap),
                  if (filters != null) ...[
                    slot(filters!),
                    SizedBox(height: gap),
                  ],
                  ...body,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
