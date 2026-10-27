import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/widgets/branding/mark_painter.dart';
import 'package:medito/widgets/branding/mark_textures.dart';

/// A Meditejo mark, alive: it appears, draws its line, then breathes, its
/// round shapes easing between a true circle and their organic form once
/// every 10 s. Drawn straight on the app's background in the active
/// palette's colours (an atmospheric scene sits in a circle).
///
/// It runs only while it can be seen: it stops when [animate] is false (Home
/// scrolled it away), when its tab is hidden (`Visibility.of`, which
/// `IndexedStack` sets), when a route covers it (`TickerMode`) and while the
/// app is in the background. Stopped, it holds its frame and later carries
/// on from there. With reduced motion it shows its settled frame.
class MeditejoMark extends StatefulWidget {
  const MeditejoMark({
    super.key,
    required this.mark,
    this.size = 160,
    this.animate = true,
    this.still = false,
    this.colors,
  });

  final MarkSpec mark;
  final double size;
  final bool animate;

  /// Always the settled frame, never moving (previews, small sizes).
  final bool still;

  /// The colours to draw in; by default the theme's palette on its
  /// background.
  final MarkColors? colors;

  @override
  State<MeditejoMark> createState() => MeditejoMarkState();
}

class MeditejoMarkState extends State<MeditejoMark>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _time = ValueNotifier(0);
  double _base = 0;
  double _lastFrame = 0;
  bool _foreground = true;
  bool _still = false;

  /// Whether the mark is moving now.
  @visibleForTesting
  bool get isRunning => _ticker.isActive;

  /// Seconds of the mark's life drawn now.
  @visibleForTesting
  double get seconds => _time.value;

  /// Whether the settled frame is shown (reduced motion).
  @visibleForTesting
  bool get isStill => _still;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    MarkTextures.instance.load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MeditejoMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mark.seed != widget.mark.seed) {
      // A new mark (a new day, or a pin) draws itself in.
      _stop();
      _base = 0;
      _time.value = 0;
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    _still = widget.still || MediaQuery.disableAnimationsOf(context);
    final run =
        widget.animate &&
        !_still &&
        _foreground &&
        Visibility.of(context) &&
        TickerMode.valuesOf(context).enabled;
    if (run) {
      if (!_ticker.isActive) {
        _lastFrame = 0;
        _ticker.start();
      }
    } else {
      _stop();
    }
  }

  void _stop() {
    if (!_ticker.isActive) return;
    _base = _time.value;
    _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final t = _base + elapsed.inMicroseconds / 1e6;
    // Once it has drawn in, breathing is slow: 30 frames a second is plenty.
    // (Just under 1/30 s, so every other 60 Hz frame is drawn.)
    if (t > 5 && t - _lastFrame < 0.03) return;
    _lastFrame = t;
    _time.value = t;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors =
        widget.colors ?? MeditejoPalette.of(context).markColors(scheme);
    Widget paint = CustomPaint(
      key: const ValueKey('meditejo_mark'),
      size: Size.square(widget.size),
      painter: MarkPainter(
        mark: widget.mark,
        colors: colors,
        time: _time,
        still: _still,
      ),
    );
    if (widget.mark.family == MarkFamily.atmos) {
      paint = ClipOval(child: paint);
    }
    return ExcludeSemantics(child: RepaintBoundary(child: paint));
  }
}

/// Paints [mark] at [time]'s moment, without a tile, so it sits on whatever
/// is below. [still] paints the settled frame.
class MarkPainter extends CustomPainter {
  MarkPainter({
    required this.mark,
    required this.colors,
    required this.time,
    this.still = false,
    this.tile = false,
  }) : super(repaint: Listenable.merge([time, MarkTextures.instance]));

  final MarkSpec mark;
  final MarkColors colors;
  final ValueListenable<double> time;
  final bool still;
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas
      ..save()
      ..translate((size.width - side) / 2, (size.height - side) / 2)
      ..scale(side);
    MarkRenderer(
      canvas,
      colors,
      textures: MarkTextures.instance,
      texel: 1 / math.max(side, 1),
    ).draw(mark, time.value, still: still, tile: tile);
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkPainter old) =>
      !identical(old.mark, mark) ||
      old.colors != colors ||
      old.time != time ||
      old.still != still ||
      old.tile != tile;
}
