import 'package:flutter/widgets.dart';

/// Window size classes from docs/SPEC.md section 4. Layout depends on window width,
/// never on device type, and only `lib/core/layout` reads it.
enum WindowClass {
  /// Under 600dp: bottom tabs.
  compact,

  /// 600 to 1199dp: side rail (96px).
  medium,

  /// 1200dp and up: full sidebar (240px).
  expanded;

  static const double mediumBreakpoint = 600;
  static const double expandedBreakpoint = 1200;

  static WindowClass forWidth(double width) {
    if (width >= expandedBreakpoint) return WindowClass.expanded;
    if (width >= mediumBreakpoint) return WindowClass.medium;
    return WindowClass.compact;
  }
}

extension WindowClassContext on BuildContext {
  WindowClass get windowClass =>
      WindowClass.forWidth(MediaQuery.sizeOf(this).width);
}

/// Sizes that scale with the window class (page padding, header title size).
class LayoutMetrics {
  const LayoutMetrics._(
    this.windowClass,
    this.pagePadding,
    this.titleSize,
    this.railWidth,
  );

  factory LayoutMetrics.of(WindowClass windowClass) => switch (windowClass) {
    WindowClass.compact => const LayoutMetrics._(
      WindowClass.compact,
      EdgeInsets.fromLTRB(20, 24, 20, 24),
      20,
      0,
    ),
    WindowClass.medium => const LayoutMetrics._(
      WindowClass.medium,
      EdgeInsets.fromLTRB(32, 24, 32, 24),
      24,
      96,
    ),
    WindowClass.expanded => const LayoutMetrics._(
      WindowClass.expanded,
      EdgeInsets.fromLTRB(40, 28, 40, 24),
      28,
      240,
    ),
  };

  final WindowClass windowClass;
  final EdgeInsets pagePadding;

  /// Header title size (month name, page title).
  final double titleSize;

  /// Width taken by the side rail or sidebar; 0 when bottom tabs are used.
  final double railWidth;

  bool get isCompact => windowClass == WindowClass.compact;
}

extension LayoutMetricsContext on BuildContext {
  LayoutMetrics get layout => LayoutMetrics.of(windowClass);
}
