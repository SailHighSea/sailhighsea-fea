import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';

/// Foldable half-open helper (docs/SPEC.md section 4).
/// Returns the hinge rectangle when the device is half-open with a horizontal hinge
/// (the fold runs across the full width), otherwise null.
Rect? horizontalHingeOf(MediaQueryData media) {
  for (final DisplayFeature feature in media.displayFeatures) {
    final isFold =
        feature.type == DisplayFeatureType.hinge ||
        feature.type == DisplayFeatureType.fold;
    if (!isFold) continue;
    if (feature.state != DisplayFeatureState.postureHalfOpened) continue;
    final bounds = feature.bounds;
    final spansWidth = bounds.width >= media.size.width - 1;
    if (spansWidth) return bounds;
  }
  return null;
}

extension HingeContext on BuildContext {
  /// The horizontal hinge rectangle when half-open, otherwise null.
  Rect? get horizontalHinge => horizontalHingeOf(MediaQuery.of(this));
}

/// With a half-open horizontal hinge: [child] fills the area above the hinge and
/// [bottom] fills the area below it. In any other posture only [child] is shown and
/// the caller keeps presenting [bottom] its usual way (pane or dialog).
class HingeSplit extends StatelessWidget {
  const HingeSplit({super.key, required this.child, this.bottom});

  final Widget child;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final hinge = horizontalHingeOf(MediaQuery.of(context));
    final lower = bottom;
    if (hinge == null || lower == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: hinge.top,
          child: MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: child,
          ),
        ),
        SizedBox(height: hinge.height),
        Expanded(child: lower),
      ],
    );
  }
}
