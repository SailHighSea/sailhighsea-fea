import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'window_class.dart';

/// Widest the page content grows; wider windows centre it instead of stretching.
const double kMaxContentWidth = 1200;

/// Title row for a page. On the phone, pages outside the tab bar show a back arrow.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = context.layout.titleSize < 24
        ? 24.0
        : context.layout.titleSize;
    return Row(
      children: [
        if (onBack != null)
          Transform.translate(
            offset: const Offset(-10, 0),
            child: _HeaderIconButton(
              icon: Icons.chevron_left_rounded,
              label: 'Back',
              onTap: onBack!,
            ),
          ),
        Expanded(
          child: Transform.translate(
            offset: Offset(onBack != null ? -6 : 0, 0),
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox(
          width: kMinTapTarget,
          height: kMinTapTarget,
          child: Icon(icon, size: 30, color: context.tokens.text),
        ),
      ),
    );
  }
}

/// A scrolling page body with the standard padding for the current window class.
class AdaptivePage extends StatelessWidget {
  const AdaptivePage({super.key, required this.children, this.header});

  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final metrics = context.layout;
    return SingleChildScrollView(
      padding: metrics.pagePadding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              if (header != null) const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

enum PaneMode { stacked, split }

/// Primary content with a secondary pane. On the phone they stack with the secondary
/// pinned under the scrolling primary; on wider windows they sit side by side.
class AdaptiveTwoPane extends StatelessWidget {
  const AdaptiveTwoPane({
    super.key,
    required this.header,
    required this.primary,
    required this.secondary,
    this.secondaryWidth = 300,
    this.scrollWhenStacked = false,
  });

  final Widget header;
  final Widget Function(BuildContext, PaneMode) primary;
  final Widget Function(BuildContext, PaneMode) secondary;
  final double secondaryWidth;

  /// On the phone, scroll both panes together instead of pinning the secondary one under
  /// the primary (the Family screen is a plain scrolling page).
  final bool scrollWhenStacked;

  @override
  Widget build(BuildContext context) {
    final metrics = context.layout;
    if (metrics.isCompact && scrollWhenStacked) {
      return SingleChildScrollView(
        padding: metrics.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 18),
            primary(context, PaneMode.stacked),
            const SizedBox(height: 12),
            secondary(context, PaneMode.stacked),
          ],
        ),
      );
    }
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
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: primary(context, PaneMode.stacked),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 28),
              child: secondary(context, PaneMode.stacked),
            ),
          ],
        ),
      );
    }
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
                  Expanded(child: primary(context, PaneMode.split)),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: secondaryWidth,
                    child: secondary(context, PaneMode.split),
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

/// Stand-in body for destinations that land in later phases.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({
    super.key,
    required this.title,
    required this.phase,
    this.onBack,
  });

  final String title;
  final String phase;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AdaptivePage(
      header: PageHeader(title: title, onBack: onBack),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Text(
            '$title arrives in $phase.',
            style: TextStyle(fontSize: 15, color: t.muted),
          ),
        ),
      ],
    );
  }
}
