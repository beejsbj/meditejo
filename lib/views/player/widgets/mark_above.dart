import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [child] out first, at its natural height, then gives [mark] whatever
/// height is left of [minHeight] above it: a square, at most [maxMark] and
/// [minMark] at the least. With less room than [minMark] the mark is left
/// out, and [child] is laid out as it would be alone (centred, and taller
/// than [minHeight] only if it must be, so a scroll view around it scrolls).
///
/// The room is measured, not estimated, so whatever grows [child] (text
/// size, a stopwatch's larger readout) takes room from the mark and never
/// from the transport. [mark] is built into the square it is given: it is
/// laid out tight, so a `LayoutBuilder` reads its side from `maxWidth`.
class MarkAbove extends MultiChildRenderObjectWidget {
  MarkAbove({
    super.key,
    required this.minHeight,
    required Widget mark,
    required Widget child,
    this.gap = 24,
    this.minMark = 96,
    this.maxMark = 320,
  }) : super(children: [child, mark]);

  final double minHeight;
  final double gap, minMark, maxMark;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMarkAbove(
    minHeight: minHeight,
    gap: gap,
    minMark: minMark,
    maxMark: maxMark,
  );

  @override
  void updateRenderObject(BuildContext context, RenderMarkAbove renderObject) {
    renderObject
      ..minHeight = minHeight
      ..gap = gap
      ..minMark = minMark
      ..maxMark = maxMark;
  }
}

class _MarkAboveParentData extends ContainerBoxParentData<RenderBox> {}

class RenderMarkAbove extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MarkAboveParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MarkAboveParentData> {
  RenderMarkAbove({
    required double minHeight,
    required double gap,
    required double minMark,
    required double maxMark,
  }) : _minHeight = minHeight,
       _gap = gap,
       _minMark = minMark,
       _maxMark = maxMark;

  double _minHeight, _gap, _minMark, _maxMark;

  set minHeight(double v) => _set(_minHeight, v, (x) => _minHeight = x);
  set gap(double v) => _set(_gap, v, (x) => _gap = x);
  set minMark(double v) => _set(_minMark, v, (x) => _minMark = x);
  set maxMark(double v) => _set(_maxMark, v, (x) => _maxMark = x);

  void _set(double old, double v, void Function(double) assign) {
    if (old == v) return;
    assign(v);
    markNeedsLayout();
  }

  RenderBox get _rest => firstChild!;
  RenderBox get _mark => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MarkAboveParentData) {
      child.parentData = _MarkAboveParentData();
    }
  }

  /// The mark's side for a [rest] this tall in [width], or 0 for none.
  double _markSide(double restHeight, double width) {
    final side = math.min(
      math.min(_minHeight - restHeight - _gap, _maxMark),
      width,
    );
    return side >= _minMark ? side : 0;
  }

  double _height(double restHeight, double side) {
    final content = restHeight + (side > 0 ? side + _gap : 0);
    return math.max(_minHeight, content);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final rest = _rest.getDryLayout(BoxConstraints(maxWidth: width));
    return constraints.constrain(
      Size(width, _height(rest.height, _markSide(rest.height, width))),
    );
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _rest.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final restHeight = _rest.size.height;
    final side = _markSide(restHeight, width);
    if (side > 0) {
      _mark.layout(BoxConstraints.tight(Size.square(side)));
    } else {
      _mark.layout(BoxConstraints.tight(Size.zero));
    }
    final height = _height(restHeight, side);
    size = constraints.constrain(Size(width, height));
    final content = restHeight + (side > 0 ? side + _gap : 0);
    var y = (size.height - content) / 2;
    if (side > 0) {
      (_mark.parentData! as _MarkAboveParentData).offset = Offset(
        (size.width - side) / 2,
        y,
      );
      y += side + _gap;
    }
    (_rest.parentData! as _MarkAboveParentData).offset = Offset(
      (size.width - _rest.size.width) / 2,
      y,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
