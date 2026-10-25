import 'package:flutter/material.dart';

import 'page_layout.dart';
import 'window_class.dart';

/// Arranges an add/edit form (Add, TabAdd and DeskAdd mockups): one column with the
/// action pinned at the bottom on the phone, two columns on wider windows.
class AdaptiveFormLayout extends StatelessWidget {
  const AdaptiveFormLayout({
    super.key,
    required this.header,
    required this.amount,
    required this.categories,
    required this.details,
    required this.keypad,
    required this.actions,
    this.tip,
    this.notice,
  });

  final Widget header;
  final Widget amount;
  final Widget categories;
  final Widget details;
  final Widget keypad;

  /// Primary actions (Save). Pinned to the bottom on the phone.
  final Widget actions;

  /// Keyboard shortcut hint, shown only where there is a hardware keyboard layout (desktop width).
  final Widget? tip;

  /// Something to tell the person above the details at every width (a receipt is attached).
  final Widget? notice;

  @override
  Widget build(BuildContext context) {
    final metrics = context.layout;
    if (metrics.isCompact) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.pagePadding.left,
          4,
          metrics.pagePadding.right,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    amount,
                    const SizedBox(height: 18),
                    categories,
                    const SizedBox(height: 14),
                    if (notice != null) ...[
                      notice!,
                      const SizedBox(height: 14),
                    ],
                    details,
                    const SizedBox(height: 14),
                    keypad,
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 20),
              child: actions,
            ),
          ],
        ),
      );
    }
    final showTip = metrics.windowClass == WindowClass.expanded && tip != null;
    return SingleChildScrollView(
      padding: metrics.pagePadding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        amount,
                        const SizedBox(height: 18),
                        categories,
                        const SizedBox(height: 18),
                        keypad,
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (notice != null) ...[
                          notice!,
                          const SizedBox(height: 16),
                        ],
                        details,
                        if (showTip) ...[const SizedBox(height: 16), tip!],
                        const SizedBox(height: 16),
                        actions,
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
