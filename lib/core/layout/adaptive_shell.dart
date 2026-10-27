import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/glass.dart';
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
    this.immersiveTop = false,
  });

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final Widget child;

  /// Phone only: the page draws under the status bar (Home's gradient band), so the shell adds
  /// no top margin and the sync status floats over the page instead of sitting above it.
  final bool immersiveTop;

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
        immersiveTop: immersiveTop,
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
    this.immersiveTop = false,
  });

  final bool immersiveTop;
  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;
  final bool showTabs;
  final Widget child;
  final Widget? syncIndicator;

  @override
  Widget build(BuildContext context) {
    final indicator = syncIndicator;
    final media = MediaQuery.of(context);
    // The pill floats over the page: the page runs behind it and scrolls clear of it.
    final barSpace = showTabs ? _kBarSpace + media.viewPadding.bottom : 0.0;
    final page = MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          bottom: showTabs ? barSpace : media.padding.bottom,
        ),
      ),
      child: child,
    );
    final top = immersiveTop ? MediaQuery.viewPaddingOf(context).top + 2 : null;
    return Stack(
      children: [
        Positioned.fill(
          child: immersiveTop
              ? page
              : SafeArea(
                  bottom: !showTabs,
                  child: Column(
                    children: [
                      if (indicator != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: indicator,
                          ),
                        ),
                      Expanded(child: page),
                    ],
                  ),
                ),
        ),
        if (immersiveTop && indicator != null)
          Positioned(right: 8, top: top, child: indicator),
        if (showTabs)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomTabs(destination: destination, onSelect: onSelect),
          ),
      ],
    );
  }
}

/// Height of the floating pill with its margins (the system inset is added on top).
const double _kBarSpace = 90;

class _BottomTabs extends StatelessWidget {
  const _BottomTabs({required this.destination, required this.onSelect});

  final AppDestination destination;
  final ValueChanged<AppDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final glass = GlassScope.of(context);
    final row = SizedBox(
      height: 74,
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            for (final d in AppDestination.tabs)
              Expanded(
                child: _PillTab(
                  destination: d,
                  selected: d == destination,
                  onTap: () => onSelect(d),
                ),
              ),
          ],
        ),
      ),
    );
    final radius = BorderRadius.circular(36);
    // A floating, rounded pill with the chosen tab in a lighter pill. Glass is see-through over
    // the backdrop; Standard is a solid surface with a thin edge and a soft shadow.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
        child: glass
            ? GlassBox(
                key: const ValueKey('glass-bar'),
                color: t.navRail,
                borderRadius: radius,
                // Frosted: what scrolls under the bar is blurred, and the tint is strong enough
                // that the labels never fight with the cards behind.
                strength: 1.25,
                blur: 22,
                child: row,
              )
            : DecoratedBox(
                key: const ValueKey('pill-bar'),
                decoration: BoxDecoration(
                  color: t.navRail,
                  borderRadius: radius,
                  border: Border.all(color: t.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: row,
              ),
      ),
    );
  }
}

/// A tab in the glass bar: icon over label, the chosen one inside a lighter rounded pill.
class _PillTab extends StatelessWidget {
  const _PillTab({
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = selected ? t.text : t.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            color: selected
                ? (dark
                      ? Colors.white.withValues(alpha: 0.18)
                      : t.primary.withValues(alpha: 0.16))
                : Colors.transparent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NavIcon(destination, size: 24, color: color),
              const SizedBox(height: 3),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
    final rail = SafeArea(
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
    );
    if (GlassScope.of(context)) {
      return SizedBox(
        width: 96,
        child: GlassBox(color: t.navRail, strength: 1.1, child: rail),
      );
    }
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: t.navRail,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: rail,
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
