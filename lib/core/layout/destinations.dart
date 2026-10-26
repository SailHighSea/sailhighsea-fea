import 'package:flutter/material.dart';

/// Every top-level destination. Each exists in the bottom tabs, rail or sidebar so no
/// screen is reachable on one size only (docs/SPEC.md section 4).
enum AppDestination {
  home('Home', '/home', Icons.home_outlined, Icons.home_rounded),
  budgets(
    'Budgets',
    '/budgets',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
  ),
  insights(
    'Insights',
    '/insights',
    Icons.bar_chart_rounded,
    Icons.bar_chart_rounded,
  ),
  goals('Goals', '/goals', Icons.track_changes, Icons.track_changes),
  bills('Bills', '/bills', Icons.calendar_today_outlined, Icons.calendar_today),
  family('Family', '/family', Icons.group_outlined, Icons.group),
  appearance(
    'Appearance',
    '/appearance',
    Icons.settings_outlined,
    Icons.settings,
  ),

  /// The phone's Settings tab: a page that lists Family, Goals, Bills and Appearance.
  settings('Settings', '/settings', Icons.settings_outlined, Icons.settings);

  const AppDestination(this.label, this.path, this.icon, this.activeIcon);

  final String label;
  final String path;
  final IconData icon;
  final IconData activeIcon;

  /// Label for the rail: the tablet mockup calls the last item "Settings".
  String get railLabel => this == appearance ? 'Settings' : label;

  /// Items in the phone's bottom tab bar.
  static const tabs = [home, budgets, insights, settings];

  /// Items in the rail and sidebar, above the pinned bottom item.
  static const main = [home, budgets, insights, goals, bills, family];

  /// Listed on the phone's Settings tab (items not in the tab bar).
  static const overflow = [family, goals, bills, appearance];

  bool get isTab => tabs.contains(this);

  static AppDestination fromLocation(String location) {
    for (final d in values) {
      if (location == d.path || location.startsWith('${d.path}/')) return d;
    }
    return home;
  }
}
