import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'destinations.dart';
import 'hinge.dart';
import 'nav_icon.dart';
import 'window_class.dart';

/// The one navigation shell for every device. Picks bottom tabs, a 96px rail or a 240px
/// sidebar from the window width alone (docs/SPEC.md section 4). The pages inside are
/// the same widgets on every size.
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.destination,
    required this.onSelect,
    required this.child,
    this.memberInitials = const [],
    this.foldBottom,
    this.showBottomTabs = true,
    this.syncIndicator,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final Widget child;

  /// Initials shown in the sidebar footer.
  final List<String> memberInitials;

  /// Shown below the hinge when a foldable is half-open (for example the Add form).
  final Widget? foldBottom;

  /// Phone only: false on pages that open full screen (Add, Expenses, Appearance) so they
  /// can use the whole height. The rail and sidebar are always shown.
  final bool showBottomTabs;

  /// Sync status shown on every size: a strip above the page on phones, in the rail and in
  /// the sidebar. `dense` asks for the one-word version that fits the 96px rail. Null when
  /// there is nothing to sync.
  final Widget Function(bool dense)? syncIndicator;

  @override
  Widget build(BuildContext context) {
    final windowClass = context.windowClass;
    final body = switch (windowClass) {
      WindowClass.compact => _CompactShell(
        destination: destination,
        onSelect: onSelect,
        showTabs: showBottomTabs,
        syncIndicator: syncIndicator?.call(false),
        child: child,
      ),
      WindowClass.medium => Row(
        children: [
          _NavRail(
            destination: destination,
            onSelect: onSelect,
            syncIndicator: syncIndicator?.call(true),
          ),
          Expanded(child: child),
        ],
      ),
      WindowClass.expanded => Row(
        children: [
          _Sidebar(
            destination: destination,
            onSelect: onSelect,
            memberInitials: memberInitials,
            syncIndicator: syncIndicator?.call(false),
          ),
          Expanded(child: child),
        ],
      ),
    };
    return Scaffold(
      body: HingeSplit(bottom: foldBottom, child: body),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.destination,
    required this.onSelect,
    required this.showTabs,
    required this.child,
    this.syncIndicator,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final bool showTabs;
  final Widget child;
  final Widget? syncIndicator;

  @override
  Widget build(BuildContext context) {
    final indicator = syncIndicator;
    return Column(
      children: [
        if (indicator != null)
          SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: indicator,
              ),
            ),
          ),
        Expanded(
          child: SafeArea(
            top: indicator == null,
            bottom: !showTabs,
            child: child,
          ),
        ),
        if (showTabs) _BottomTabs(destination: destination, onSelect: onSelect),
      ],
    );
  }
}

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.destination, required this.onSelect});

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.navRail,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            children: [
              for (final d in AppDestination.tabs)
                Expanded(
                  child: _TabItem(
                    destination: d,
                    selected: d == destination,
                    onTap: () => onSelect(d),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.primary : t.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NavIcon(destination, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({
    required this.destination,
    required this.onSelect,
    this.syncIndicator,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final Widget? syncIndicator;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: t.navRail,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        right: false,
        // Short windows (a half-open fold, large text) scroll the rail instead of overflowing.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    const SizedBox(height: 28),
                    for (final d in AppDestination.main) ...[
                      _RailItem(
                        destination: d,
                        selected: d == destination,
                        onTap: () => onSelect(d),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const Spacer(),
                    if (syncIndicator != null) ...[
                      syncIndicator!,
                      const SizedBox(height: 8),
                    ],
                    _RailItem(
                      destination: AppDestination.appearance,
                      selected: destination == AppDestination.appearance,
                      onTap: () => onSelect(AppDestination.appearance),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.navActiveText : t.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.railLabel,
      excludeSemantics: true,
      child: Material(
        color: selected ? t.navActiveBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 72, minHeight: 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                NavIcon(destination, size: 24, color: color),
                const SizedBox(height: 4),
                Text(
                  destination.railLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destination,
    required this.onSelect,
    required this.memberInitials,
    this.syncIndicator,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final List<String> memberInitials;
  final Widget? syncIndicator;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: t.sidebar,
        border: Border(right: BorderSide(color: t.sidebarBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SafeArea(
        right: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                child: Text(
                  'Expenses',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: t.heroText,
                  ),
                ),
              ),
              for (final d in AppDestination.main) ...[
                _SidebarItem(
                  destination: d,
                  selected: d == destination,
                  onTap: () => onSelect(d),
                ),
                const SizedBox(height: 6),
              ],
              const Spacer(),
              if (syncIndicator != null) ...[
                Align(alignment: Alignment.centerLeft, child: syncIndicator!),
                const SizedBox(height: 6),
              ],
              _SidebarItem(
                destination: AppDestination.appearance,
                selected: destination == AppDestination.appearance,
                onTap: () => onSelect(AppDestination.appearance),
              ),
              if (memberInitials.isNotEmpty)
                _MemberStack(initials: memberInitials),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = selected ? t.heroText : t.sidebarText;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: Material(
        color: selected ? t.sidebarActive : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  NavIcon(destination, size: 20, color: color),
                  const SizedBox(width: 12),
                  Text(
                    destination.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberStack extends StatelessWidget {
  const _MemberStack({required this.initials});

  final List<String> initials;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = t.avatars;
    // Five circles are enough; the count beside them says how many people there are.
    final shown = initials.length > 5 ? 5 : initials.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          SizedBox(
            width: 32.0 + (shown - 1) * 24,
            height: 32,
            child: Stack(
              children: [
                for (var i = 0; i < shown; i++)
                  Positioned(
                    left: i * 24.0,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length].background,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        initials[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors[i % colors.length].foreground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              initials.length == 1 ? '1 member' : '${initials.length} members',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.sidebarText),
            ),
          ),
        ],
      ),
    );
  }
}
