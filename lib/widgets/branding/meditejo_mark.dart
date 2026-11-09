import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/seeded_random.dart';
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
///
/// Two one-shot moments ride on the same clock (timings in [MarkMoments]):
/// [MeditejoMarkState.breathe] sends one deep breath through it, and [from]
/// makes it arrive from another mark (yesterday's) the first time it is
/// seen, the old one un-drawing as this one draws itself in. Neither adds a
/// clock of its own, so neither runs while the mark can't be seen.
class MeditejoMark extends StatefulWidget {
  const MeditejoMark({
    super.key,
    required this.mark,
    this.size = 160,
    this.animate = true,
    this.still = false,
    this.colors,
    this.from,
    this.onSeen,
    this.turnClock,
    this.breathSeconds,
    this.paused = false,
  });

  final MarkSpec mark;
  final double size;
  final bool animate;

  /// Always the settled frame, never moving (previews, small sizes).
  final bool still;

  /// The colours to draw in; by default the theme's palette on its
  /// background.
  final MarkColors? colors;

  /// The mark this one arrives from. Read when the widget is created and
  /// when [mark] changes; until the mark is first seen, [from] is what
  /// shows, and the turn plays from there. With reduced motion the two
  /// crossfade. Clearing it later doesn't cut a turn short.
  final MarkSpec? from;

  /// Called once per [mark], just after it is first seen: in the
  /// foreground, not under a route or on a hidden tab, and not scrolled
  /// away ([animate]). Reduced motion doesn't change when it is seen.
  final VoidCallback? onSeen;

  /// Where the turn from [from] is, in seconds, written on the mark's own
  /// clock: it holds whenever the mark does (covered, on a hidden tab,
  /// scrolled away, in the background) and carries on from there. It runs
  /// to [MarkMoments.nameSeconds], with reduced motion too, so a caption
  /// (Home's day name) can ride on it. Written only from frame callbacks.
  final ValueNotifier<double>? turnClock;

  /// Seconds per breath for a mark that breathes on and on (the player's):
  /// it swells and settles as a deep breath does, over and over, instead of
  /// only when touched. Null (Home) is the resting mark. Changing it carries
  /// on from the same point in the breath. Reduced motion ignores it.
  final double? breathSeconds;

  /// Holds a [breathSeconds] mark where it is (playback is paused). The mark
  /// first finishes drawing itself in; after that nothing moves, and it
  /// carries on from there.
  final bool paused;

  @override
  State<MeditejoMark> createState() => MeditejoMarkState();
}

class MeditejoMarkState extends State<MeditejoMark>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _time = ValueNotifier(0);
  double _base = 0;
  double _lastFrame = 0;
  bool _foreground = true;
  bool _still = false;

  /// The mark being left, while the turn from it plays.
  MarkSpec? _from;

  /// Whether a turn's moment (the turn, then its caption) is still running.
  bool _turning = false;

  /// With reduced motion the turn's clock: the crossfade from [_from], then
  /// the rest of the moment.
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (MarkMoments.nameSeconds * 1000).round()),
    // A quiet fade even when the system asks for less motion: this is the
    // reduced-motion path already.
    animationBehavior: AnimationBehavior.preserve,
  )..addListener(_onStillTurn);

  late final CurvedAnimation _crossfade = CurvedAnimation(
    parent: _turn,
    curve: Interval(
      0,
      MarkMoments.crossfade.inMilliseconds / 1000 / MarkMoments.nameSeconds,
    ),
  );

  /// How far through a continuous breath the mark is, in breaths.
  double _phase = 0;
  double _phaseAt = 0;

  /// 0 out, 1 in: the continuous breath, drawn as a deep breath's swell.
  final ValueNotifier<double> _cycle = ValueNotifier(0);

  bool get _continuous => widget.breathSeconds != null;

  /// The mark's clock when a deep breath began.
  double? _breathStart;

  /// The mark [MeditejoMark.onSeen] was last called for.
  String? _seenSeed;

  /// Whether the mark is moving now.
  @visibleForTesting
  bool get isRunning => _ticker.isActive;

  /// Seconds of the mark's life drawn now. Negative while a turn is still
  /// un-drawing the old mark, before this one starts to draw.
  @visibleForTesting
  double get seconds => _time.value;

  /// Whether the settled frame is shown (reduced motion).
  @visibleForTesting
  bool get isStill => _still;

  /// How far in the continuous breath is (0 out, 1 in).
  @visibleForTesting
  double get cycle => _cycle.value;

  /// Whether a deep breath is under way.
  bool get isBreathing => _breathStart != null;

  /// Whether the mark is still arriving from [MeditejoMark.from].
  bool get isArriving => _from != null;

  /// The mark it is arriving from, while it does.
  @visibleForTesting
  MarkSpec? get arrivingFrom => _from;

  /// How far into the turn from [MeditejoMark.from] the mark is: 0 before
  /// it is seen, 1 once only this mark shows.
  @visibleForTesting
  double get arrival {
    if (_from == null) return 1;
    if (_still) return _crossfade.value;
    return clamp01(
      (_time.value + MarkMoments.morphLead) / MarkMoments.undrawSeconds,
    );
  }

  /// Sends one deep breath through the mark: it swells and settles over
  /// [MarkMoments.breathSeconds], then rests. Ignored while one is already
  /// under way (taps don't stack), while it arrives from another mark, while
  /// it can't be seen, and with reduced motion. Says whether a breath began.
  bool breathe() {
    if (_still || isBreathing || isArriving || !_ticker.isActive) {
      return false;
    }
    setState(() => _breathStart = _time.value);
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    MarkTextures.instance.load();
    _arriveFrom(widget.from);
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
      _breathStart = null;
      _phase = 0;
      _phaseAt = 0;
      _cycle.value = 0;
      _from = null;
      _turning = false;
      _turn
        ..stop()
        ..value = 0;
      _arriveFrom(widget.from);
    }
    _sync();
  }

  /// Sets up the turn from [from]; it waits until the mark is seen.
  void _arriveFrom(MarkSpec? from) {
    if (from == null || from.seed == widget.mark.seed) return;
    _from = from;
    _turning = true;
    _base = -MarkMoments.morphLead;
    _time.value = _base;
  }

  /// The turn's clock moved to [s] seconds.
  void _turnAt(double s) {
    final clock = widget.turnClock;
    if (clock != null) clock.value = math.min(s, MarkMoments.nameSeconds);
    if (s >= MarkMoments.nameSeconds) _turning = false;
  }

  void _onStillTurn() {
    if (!_still || !_turning) return;
    _turnAt(_turn.value * MarkMoments.nameSeconds);
    if (_from != null && _crossfade.value >= 1) setState(() => _from = null);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  void _sync() {
    _still = widget.still || MediaQuery.disableAnimationsOf(context);
    final seen =
        widget.animate &&
        _foreground &&
        Visibility.of(context) &&
        TickerMode.valuesOf(context).enabled;
    if (seen && !_still) {
      if (!_ticker.isActive) {
        _lastFrame = double.negativeInfinity;
        _ticker.start();
      }
    } else {
      _stop();
    }
    // With reduced motion the turn runs on its own controller, held and
    // carried on just as the ticker is.
    if (_turning && _still && seen) {
      if (!_turn.isAnimating) _turn.forward();
    } else {
      _turn.stop();
    }
    if (seen && _seenSeed != widget.mark.seed) {
      _seenSeed = widget.mark.seed;
      final onSeen = widget.onSeen;
      if (onSeen != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) onSeen();
        });
      }
    }
  }

  void _stop() {
    if (!_ticker.isActive) return;
    _base = _time.value;
    _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final t = _base + elapsed.inMicroseconds / 1e6;
    final period = widget.breathSeconds;
    if (period != null) {
      // The clock carries on from where it stopped, so a restart cannot
      // jump the breath; it only ever moves forward.
      final dt = math.max(0.0, t - _phaseAt);
      _phaseAt = t;
      if (!widget.paused) {
        _phase = (_phase + dt / period) % 1;
        _cycle.value = 0.5 - 0.5 * math.cos(2 * math.pi * _phase);
      }
    }
    if (_turning) _turnAt(t + MarkMoments.morphLead);
    // A turn or a deep breath ends: back to resting.
    if (_from != null &&
        t + MarkMoments.morphLead >= MarkMoments.undrawSeconds) {
      setState(() => _from = null);
    }
    final breath = _breathStart;
    if (breath != null && t - breath >= MarkMoments.breathSeconds) {
      setState(() => _breathStart = null);
    }
    // Once it has drawn in, resting breath is slow: 30 frames a second is
    // plenty. (Just under 1/30 s, so every other 60 Hz frame is drawn.) A
    // deep breath swells the whole mark, so it gets every frame.
    if (t > 5 && _breathStart == null && t - _lastFrame < 0.03) return;
    _lastFrame = t;
    _time.value = t;
    // Paused and drawn in: nothing is left to move, so stop the clock.
    if (_continuous && widget.paused && t > MarkMoments.drawnBy(widget.mark)) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _crossfade.dispose();
    _turn.dispose();
    _time.dispose();
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors =
        widget.colors ?? MeditejoPalette.of(context).markColors(scheme);
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('meditejo_mark'),
          size: Size.square(widget.size),
          painter: MarkPainter(
            mark: widget.mark,
            colors: colors,
            time: _time,
            still: _still,
            breathStart: _breathStart,
            cycle: _continuous ? _cycle : null,
            from: _from,
            fade: _still && _from != null ? _crossfade : null,
          ),
        ),
      ),
    );
  }
}

/// Paints [mark] at [time]'s moment, without a tile, so it sits on whatever
/// is below. [still] paints the settled frame. An atmospheric scene is
/// clipped to its circle here, so a deep breath swells the circle too.
///
/// [breathStart] is the clock time a deep breath began. [from] is a mark
/// being left: drawn un-drawing over the turn's first seconds (the clock
/// starts at `-MarkMoments.morphLead`), or, with [fade] (reduced motion),
/// crossfading into [mark]'s settled frame.
class MarkPainter extends CustomPainter {
  MarkPainter({
    required this.mark,
    required this.colors,
    required this.time,
    this.still = false,
    this.tile = false,
    this.breathStart,
    this.cycle,
    this.from,
    this.fade,
  }) : super(
         repaint: Listenable.merge([
           time,
           MarkTextures.instance,
           ?fade,
           ?cycle,
         ]),
       );

  final MarkSpec mark;
  final MarkColors colors;
  final ValueListenable<double> time;
  final bool still;
  final bool tile;
  final double? breathStart;

  /// A continuous breath, 0 out to 1 in, swelling the mark as a deep breath
  /// does; null when the mark only rests.
  final ValueListenable<double>? cycle;
  final MarkSpec? from;
  final Animation<double>? fade;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas
      ..save()
      ..translate((size.width - side) / 2, (size.height - side) / 2)
      ..scale(side);
    final renderer = MarkRenderer(
      canvas,
      colors,
      textures: MarkTextures.instance,
      texel: 1 / math.max(side, 1),
    );
    final t = time.value;
    final old = from;
    final crossfade = fade;
    if (old != null && crossfade != null) {
      _layer(canvas, old, 1 - crossfade.value, () {
        renderer.draw(old, t, still: true, tile: tile);
      });
      _layer(canvas, mark, crossfade.value, () {
        renderer.draw(mark, t, still: true, tile: tile);
      });
    } else {
      final s = t + MarkMoments.morphLead;
      if (old != null && !still && s < MarkMoments.undrawSeconds) {
        _layer(canvas, old, MarkMoments.undrawOpacityAt(s), () {
          renderer.draw(
            old,
            MarkMoments.undrawTimeAt(old, s),
            tile: tile,
            breathe: false,
          );
        });
      }
      final start = breathStart;
      final swell = still
          ? 0.0
          : start != null
          ? MarkMoments.swellAt(t - start)
          : cycle?.value ?? 0.0;
      _layer(canvas, mark, 1, swell: swell, () {
        renderer.draw(mark, t, still: still, tile: tile, swell: swell);
      });
    }
    canvas.restore();
  }

  /// Draws one mark at [opacity]: a scene inside its circle, grown by
  /// [swell] as the renderer grows the scene.
  static void _layer(
    Canvas canvas,
    MarkSpec m,
    double opacity,
    void Function() draw, {
    double swell = 0,
  }) {
    if (opacity <= 0) return;
    canvas.save();
    if (m.family == MarkFamily.atmos) {
      final r = 0.5 * (1 + MarkMoments.swellScale * swell);
      canvas.clipPath(
        Path()
          ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: r)),
      );
    }
    if (opacity < 1) {
      canvas.saveLayer(
        const Rect.fromLTWH(-0.5, -0.5, 2, 2),
        Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }
    draw();
    if (opacity < 1) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(MarkPainter old) =>
      !identical(old.mark, mark) ||
      old.colors != colors ||
      old.time != time ||
      old.still != still ||
      old.tile != tile ||
      old.breathStart != breathStart ||
      old.cycle != cycle ||
      !identical(old.from, from) ||
      old.fade != fade;
}
