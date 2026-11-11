import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// What Home's mark gives way to: the bottom of the first row of one-tap
/// tiles (or, with those hidden, of the first section). [HomeMarkLayout]
/// keeps that above the bottom of the screen for as long as the mark has
/// room to give.
class HomeFold {
  _RenderHomeFoldMarker? _marker;

  /// The height the mark's block has now.
  double headerHeight = 0;
}

/// Hands [fold] to the sections below, so one of them can mark it.
class HomeFoldScope extends InheritedWidget {
  const HomeFoldScope({super.key, required this.fold, required super.child});

  final HomeFold fold;

  static HomeFold? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeFoldScope>()?.fold;

  @override
  bool updateShouldNotify(HomeFoldScope oldWidget) => oldWidget.fold != fold;
}

/// Marks [child]'s bottom edge as Home's fold. Outside Home it does nothing.
class HomeFoldMarker extends SingleChildRenderObjectWidget {
  const HomeFoldMarker({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHomeFoldMarker(HomeFoldScope.maybeOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderHomeFoldMarker).fold = HomeFoldScope.maybeOf(
      context,
    );
  }
}

class _RenderHomeFoldMarker extends RenderProxyBox {
  _RenderHomeFoldMarker(this._fold);

  HomeFold? _fold;

  /// Its height as last laid out, kept for [RenderHomeMarkLayout] (which
  /// is no parent of this box, so may not ask for its size).
  double? height;

  @override
  void performLayout() {
    super.performLayout();
    height = size.height;
  }

  set fold(HomeFold? value) {
    if (identical(value, _fold)) return;
    if (identical(_fold?._marker, this)) _fold!._marker = null;
    _fold = value;
    if (attached) value?._marker = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fold?._marker = this;
  }

  @override
  void detach() {
    if (identical(_fold?._marker, this)) _fold!._marker = null;
    super.detach();
  }
}

/// Home's two blocks, as a sliver: the mark's ([header]) above everything
/// else ([rest]).
///
/// [rest] is laid out first, at its natural height. The mark's block then
/// takes what is left of the scroll view's height above the fold (see
/// [HomeFold]): at
/// most [maxHeader], so the mark has about the top half of the screen when
/// little is below it, and never under [minHeader], so a full Home scrolls
/// rather than squeeze the mark away. The room is measured, not estimated:
/// a third Continue card or a larger text size takes it from the mark.
///
/// [header] is laid out tight: what is in it fills the height it is given.
/// A change of height after the first layout is eased ([animate]), so
/// removing a Continue card does not make the mark jump.
///
/// Nothing here waits for layout to build (no `LayoutBuilder`): Home is
/// built whole under the intro, where it is not laid out.
class HomeMarkLayout extends StatelessWidget {
  const HomeMarkLayout({
    super.key,
    required this.fold,
    required this.minHeader,
    required this.maxHeader,
    required this.header,
    required this.rest,
    this.foldMargin = 16,
    this.animate = true,
  });

  final HomeFold fold;
  final double minHeader, maxHeader, foldMargin;
  final bool animate;
  final Widget header, rest;

  @override
  Widget build(BuildContext context) => _ViewportAwareSliver(
    child: _HomeMarkBox(
      fold: fold,
      minHeader: minHeader,
      maxHeader: maxHeader,
      foldMargin: foldMargin,
      animate: animate,
      header: header,
      rest: rest,
    ),
  );
}

/// A `SliverToBoxAdapter` that tells its [RenderHomeMarkLayout] how tall
/// the scroll view is, before laying it out.
class _ViewportAwareSliver extends SingleChildRenderObjectWidget {
  const _ViewportAwareSliver({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderViewportAwareSliver();
}

class _RenderViewportAwareSliver extends RenderSliverToBoxAdapter {
  @override
  void performLayout() {
    final box = child;
    if (box is RenderHomeMarkLayout) {
      // The sanctioned way to dirty a child while laying out.
      invokeLayoutCallback<SliverConstraints>((constraints) {
        box.viewport = constraints.viewportMainAxisExtent;
      });
    }
    super.performLayout();
  }
}

class _HomeMarkBox extends MultiChildRenderObjectWidget {
  _HomeMarkBox({
    required this.fold,
    required this.minHeader,
    required this.maxHeader,
    required this.foldMargin,
    required this.animate,
    required Widget header,
    required Widget rest,
  }) : super(children: [rest, header]);

  final HomeFold fold;
  final double minHeader, maxHeader, foldMargin;
  final bool animate;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderHomeMarkLayout(
    fold: fold,
    minHeader: minHeader,
    maxHeader: maxHeader,
    foldMargin: foldMargin,
    animate: animate,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderHomeMarkLayout renderObject,
  ) {
    renderObject
      ..fold = fold
      ..minHeader = minHeader
      ..maxHeader = maxHeader
      ..foldMargin = foldMargin
      ..animate = animate;
  }
}

class _HomeParentData extends ContainerBoxParentData<RenderBox> {}

class RenderHomeMarkLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HomeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HomeParentData> {
  RenderHomeMarkLayout({
    required this.fold,
    required double minHeader,
    required double maxHeader,
    required double foldMargin,
    required this.animate,
  }) : _minHeader = minHeader,
       _maxHeader = maxHeader,
       _foldMargin = foldMargin;

  HomeFold fold;
  bool animate;
  double _minHeader, _maxHeader, _foldMargin;

  /// The scroll view's height, set by the sliver around this box.
  double _viewport = 0;

  set viewport(double v) => _set(_viewport, v, (x) => _viewport = x);
  set minHeader(double v) => _set(_minHeader, v, (x) => _minHeader = x);
  set maxHeader(double v) => _set(_maxHeader, v, (x) => _maxHeader = x);
  set foldMargin(double v) => _set(_foldMargin, v, (x) => _foldMargin = x);

  void _set(double old, double v, void Function(double) assign) {
    if (old == v) return;
    assign(v);
    // A new screen size is not something to ease through.
    _shown = null;
    markNeedsLayout();
  }

  /// The header's height now, on its way to the one measured.
  double? _shown;
  Duration? _steppedAt;
  bool _stepping = false;

  /// Seconds for the eased height to close most (63%) of the distance.
  static const _ease = 0.12;

  RenderBox get _rest => firstChild!;
  RenderBox get _header => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HomeParentData) {
      child.parentData = _HomeParentData();
    }
  }

  /// The fold's distance below the top of [_rest].
  double _foldBottom() {
    final marker = fold._marker;
    final height = marker?.height;
    if (marker == null || !marker.attached || height == null) {
      return _rest.size.height;
    }
    var y = height;
    RenderObject? node = marker;
    while (node != null && node != _rest) {
      final data = node.parentData;
      if (data is BoxParentData) y += data.offset.dy;
      node = node.parent;
    }
    // Not under this layout after all (a stale marker).
    return node == null ? _rest.size.height : y;
  }

  double _target() => math.max(
    math.min(_minHeader, _maxHeader),
    math.min(_maxHeader, _viewport - _foldBottom() - _foldMargin),
  );

  void _step(Duration timeStamp) {
    _stepping = false;
    if (attached) markNeedsLayout();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final rest = _rest.getDryLayout(BoxConstraints.tightFor(width: width));
    // The fold is only known once laid out; the tallest it can be.
    return constraints.constrain(Size(width, rest.height + _maxHeader));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    _rest.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    final target = _target();
    var shown = _shown;
    if (shown == null || !animate || (target - shown).abs() < 0.5) {
      shown = target;
      _steppedAt = null;
    } else {
      final now = SchedulerBinding.instance.currentFrameTimeStamp;
      final last = _steppedAt;
      if (last != null && now > last) {
        final dt = (now - last).inMicroseconds / 1e6;
        shown += (target - shown) * (1 - math.exp(-dt / _ease));
      }
      _steppedAt = now;
      if (!_stepping) {
        _stepping = true;
        SchedulerBinding.instance.scheduleFrameCallback(_step);
      }
    }
    _shown = shown;
    fold.headerHeight = shown;
    _header.layout(BoxConstraints.tight(Size(width, shown)));
    (_header.parentData! as _HomeParentData).offset = Offset.zero;
    (_rest.parentData! as _HomeParentData).offset = Offset(0, shown);
    size = constraints.constrain(Size(width, shown + _rest.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
