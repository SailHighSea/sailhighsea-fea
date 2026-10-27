import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays its child out in full but reports a height [amount] smaller, so whatever comes next in a
/// column is drawn over the child's bottom edge. Used to let the Home overview card overlap the
/// gradient header. Taps on the overlapped strip go to what is drawn over it.
class OverlapBottom extends SingleChildRenderObjectWidget {
  const OverlapBottom({super.key, required this.amount, super.child});

  final double amount;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOverlapBottom(amount);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderOverlapBottom).amount = amount;
  }
}

class _RenderOverlapBottom extends RenderShiftedBox {
  _RenderOverlapBottom(this._amount) : super(null);

  double _amount;
  set amount(double v) {
    if (v == _amount) return;
    _amount = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints, parentUsesSize: true);
    (c.parentData! as BoxParentData).offset = Offset.zero;
    final h = (c.size.height - _amount).clamp(0.0, double.infinity);
    size = constraints.constrain(Size(c.size.width, h));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      ((child?.getMinIntrinsicHeight(width) ?? 0) - _amount).clamp(0, 1e9);
  @override
  double computeMaxIntrinsicHeight(double width) =>
      ((child?.getMaxIntrinsicHeight(width) ?? 0) - _amount).clamp(0, 1e9);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final s = c.getDryLayout(constraints);
    return constraints.constrain(
      Size(s.width, (s.height - _amount).clamp(0.0, double.infinity)),
    );
  }
}
