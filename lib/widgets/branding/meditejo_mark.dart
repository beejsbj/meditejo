import 'package:flutter/material.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/widgets/branding/mark_geometry.dart';

/// The Meditejo mark, slowly moving (see [MarkGeometry] for the shapes).
///
/// It runs only while it can be seen: it stops when [animate] is false (Home
/// scrolled it away), when its tab is hidden (`Visibility.of`, which
/// `IndexedStack` sets), when a route covers it (`TickerMode`) and while the
/// app is in the background. With reduced motion it shows its still frame.
class MeditejoMark extends StatefulWidget {
  const MeditejoMark({super.key, this.size = 160, this.animate = true});

  final double size;
  final bool animate;

  @override
  State<MeditejoMark> createState() => MeditejoMarkState();
}

class MeditejoMarkState extends State<MeditejoMark>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MeditejoMotion.markLoop,
  );
  bool _foreground = true;
  MeditejoMarkPainter? _painter;

  /// Whether the mark is moving now.
  @visibleForTesting
  bool get isRunning => _controller.isAnimating;

  /// The loop phase being drawn, in [0, 1).
  @visibleForTesting
  double get phase => _controller.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MeditejoMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    final still = MediaQuery.disableAnimationsOf(context);
    final run =
        widget.animate &&
        !still &&
        _foreground &&
        Visibility.of(context) &&
        TickerMode.valuesOf(context).enabled;
    if (run) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      if (still) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final painter = _painter =
        _painter != null &&
            _painter!.blob == scheme.primaryContainer &&
            _painter!.ring == scheme.tertiary &&
            _painter!.core == scheme.primary
        ? _painter
        : MeditejoMarkPainter.forScheme(_controller, scheme);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('meditejo_mark'),
          size: Size.square(widget.size),
          painter: painter,
        ),
      ),
    );
  }
}

/// Draws [MarkGeometry]'s frame at [progress]'s phase (an
/// `AlwaysStoppedAnimation` draws one still frame). The frame,
/// path and paints are made once and reused; a frame makes only the small
/// value objects Canvas takes (the arc's bounds, the dot's centre).
class MeditejoMarkPainter extends CustomPainter {
  MeditejoMarkPainter.forScheme(Animation<double> progress, ColorScheme scheme)
    : this(
        progress: progress,
        blob: scheme.primaryContainer,
        ring: scheme.tertiary,
        core: scheme.primary,
      );

  MeditejoMarkPainter({
    required this.progress,
    required this.blob,
    required this.ring,
    required this.core,
  }) : _blobPaint = Paint()..color = blob,
       _ringPaint = Paint()
         ..color = ring
         ..style = PaintingStyle.stroke
         ..strokeCap = StrokeCap.round
         ..strokeWidth = MarkGeometry.ringWidth,
       _dotPaint = Paint()..color = ring,
       _corePaint = Paint()..color = core,
       super(repaint: progress);

  final Animation<double> progress;
  final Color blob;
  final Color ring;
  final Color core;

  final MarkFrame _frame = MarkFrame();
  final Path _blob = Path();
  final Paint _blobPaint;
  final Paint _ringPaint;
  final Paint _dotPaint;
  final Paint _corePaint;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    MarkGeometry.frameAt(progress.value, _frame);
    canvas
      ..save()
      ..translate((size.width - side) / 2, (size.height - side) / 2)
      ..scale(side);

    final b = _frame.blob;
    _blob
      ..reset()
      ..moveTo(b[0], b[1]);
    for (var i = 0; i < MarkGeometry.blobPoints; i++) {
      final o = 2 + 6 * i;
      _blob.cubicTo(b[o], b[o + 1], b[o + 2], b[o + 3], b[o + 4], b[o + 5]);
    }
    _blob.close();
    canvas.drawPath(_blob, _blobPaint);

    final r = _frame.ringRadiusNow;
    canvas
      ..drawArc(
        Rect.fromLTRB(
          MarkGeometry.center - r,
          MarkGeometry.center - r,
          MarkGeometry.center + r,
          MarkGeometry.center + r,
        ),
        _frame.ringStart,
        MarkGeometry.ringSweep,
        false,
        _ringPaint,
      )
      ..drawCircle(
        Offset(_frame.dotX, _frame.dotY),
        MarkGeometry.dotRadius,
        _dotPaint,
      )
      ..drawCircle(
        const Offset(MarkGeometry.center, MarkGeometry.center),
        _frame.coreRadiusNow,
        _corePaint,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(MeditejoMarkPainter old) =>
      old.progress != progress ||
      old.blob != blob ||
      old.ring != ring ||
      old.core != core;
}
