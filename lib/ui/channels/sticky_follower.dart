import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Keeps [child] (a sender's disc) in view while its memo scrolls past.
///
/// Fills the height its parent gives it — the memo's height — and paints
/// [child] at the top, or, once the memo's top has scrolled out of the
/// enclosing scroll view, just inside the view's top edge, stopping at the
/// bottom of the memo. Outside a scroll view it simply stays at the top.
class StickyFollower extends SingleChildRenderObjectWidget {
  const StickyFollower({super.key, this.inset = 8, required super.child});

  /// Gap between the view's top edge and a disc that is following.
  final double inset;

  @override
  RenderStickyFollower createRenderObject(BuildContext context) =>
      RenderStickyFollower(inset, Scrollable.maybeOf(context)?.position);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderStickyFollower renderObject,
  ) {
    renderObject
      ..inset = inset
      ..position = Scrollable.maybeOf(context)?.position;
  }
}

class RenderStickyFollower extends RenderProxyBox {
  RenderStickyFollower(this._inset, this._position);

  double _inset;
  set inset(double v) {
    if (v == _inset) return;
    _inset = v;
    markNeedsPaint();
  }

  ScrollPosition? _position;
  set position(ScrollPosition? p) {
    if (identical(p, _position)) return;
    if (attached) _position?.removeListener(markNeedsPaint);
    _position = p;
    if (attached) _position?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Where the child was last painted, for tests and hit testing.
  double get childTop => _childTop;
  double _childTop = 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _position?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _position?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void performLayout() {
    final c = child;
    size = constraints.biggest;
    c?.layout(constraints.loosen(), parentUsesSize: true);
  }

  double _followTop() {
    final c = child;
    if (c == null) return 0;
    final room = size.height - c.size.height;
    if (room <= 0) return 0;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is! RenderBox) return 0;
    // Layout for this frame is done by paint time, so this is current.
    final top = MatrixUtils.transformPoint(
      getTransformTo(viewport),
      Offset.zero,
    ).dy;
    if (top >= 0) return 0; // the memo's top is in view: stay there
    // Follow the view's top edge; the inset eases in over the first pixels
    // so the disc doesn't jump when the memo starts to scroll.
    final scrolled = -top;
    return (scrolled + math.min(_inset, scrolled)).clamp(0.0, room);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    _childTop = _followTop();
    context.paintChild(c, offset + Offset(0, _childTop));
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.translateByDouble(0, _childTop, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, _childTop),
      position: position,
      hitTest: (r, p) => c.hitTest(r, position: p),
    );
  }
}
