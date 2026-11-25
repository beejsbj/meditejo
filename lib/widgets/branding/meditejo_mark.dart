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

/// A Meditejo mark, alive: it appears, draws its line, then lives in its
/// parts. Its round shapes ease between a true circle and their organic
/// form once every 10 s, as on the page, and each part keeps a slow motion
/// of its own besides (a wave along a line, a pebble breathing and shifting
/// its shape; see `MarkMotion`). Nothing is ever scaled as a whole. Drawn
/// straight on the app's background in the active palette's colours (an
/// atmospheric scene sits in a circle).
///
/// It runs only while it can be seen: it stops when [animate] is false (Home
/// scrolled it away), when its tab is hidden (`Visibility.of`, which
/// `IndexedStack` sets), when a route covers it (`TickerMode`) and while the
/// app is in the background. Stopped, it holds its frame and later carries
/// on from there. With reduced motion it shows its settled frame.
///
/// Two one-shot moments ride on the same clock (timings in [MarkMoments]):
/// [MeditejoMarkState.breathe] sends one deep breath through its parts (the
/// body swells and settles, the rest follow a moment later), and [from]
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

  /// The square's side; null fills the box it is given (the mark is drawn
  /// in the largest square that fits, centred).
  final double? size;
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
  /// its parts swell and settle as in a deep breath, over and over, instead
  /// of only when touched. Null (Home) is the resting mark. Changing it carries
  /// on from the same point in the breath. Reduced motion ignores it.
  final double? breathSeconds;

  /// Rests a [breathSeconds] mark (playback is paused): the breath settles
  /// to its out-breath, the mark first finishes drawing itself in, then
  /// nothing moves. Unpausing starts a fresh breath from rest.
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

  /// The continuous breath now, written to [_cycle] with each drawn frame.
  double _cycleNow = 0;

  /// 0 out, 1 in: the continuous breath, drawn as a deep breath's swell.
  final ValueNotifier<double> _cycle = ValueNotifier(0);

  /// The same breath as the parts that follow the body feel it: [_cycle],
  /// trailing by about [_followSeconds].
  double _followNow = 0;
  final ValueNotifier<double> _follow = ValueNotifier(0);
  double? _settleFollowFrom;

  /// The idle motion's strength: 1, but a paused player's mark eases to 0
  /// as its breath settles, and back when it plays again.
  final ValueNotifier<double> _life = ValueNotifier(1);

  /// How far the following parts trail a continuous breath.
  static const _followSeconds = 0.45;

  /// With reduced motion a touch is answered by a brief dip in opacity
  /// instead of a breath.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    animationBehavior: AnimationBehavior.preserve,
  );
  late final Animation<double> _pulseOpacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.55,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 3,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.55,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 4,
    ),
  ]).animate(_pulse);

  /// While paused, when the settle to rest began and from where.
  double? _settleStart, _settleFrom;

  /// Seconds a paused mark takes to settle back to rest.
  static const _settleSeconds = 1.5;

  /// Counts the continuous breath's updates, for the 30 fps check.
  @visibleForTesting
  ValueListenable<double> get cycleListenable => _cycle;

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

  /// The continuous breath as the following parts feel it.
  @visibleForTesting
  double get follow => _follow.value;

  /// Whether a deep breath is under way.
  bool get isBreathing => _breathStart != null;

  /// Whether a touch's opacity pulse (reduced motion) is under way.
  @visibleForTesting
  bool get isPulsing => _pulse.isAnimating;

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

  /// Sends one deep breath through the mark's parts: the body swells and
  /// settles, the parts that follow it a moment later, all within
  /// [MarkMoments.breathSeconds]; then it rests. Ignored while one is
  /// already under way (taps don't stack), while it arrives from another
  /// mark and while it can't be seen. With reduced motion nothing moves:
  /// the mark's opacity dips once, briefly. Says whether a breath began.
  bool breathe() {
    if (_still && !widget.still && !isArriving && !_pulse.isAnimating) {
      _pulse.forward(from: 0);
    }
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
      _settleStart = _settleFrom = null;
      _cycleNow = 0;
      _cycle.value = 0;
      _followNow = 0;
      _follow.value = 0;
      _settleFollowFrom = null;
      _life.value = 1;
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
    var cycle = _cycleNow;
    var follow = _followNow;
    if (period != null) {
      // The clock carries on from where it stopped, so a restart cannot
      // jump the breath; it only ever moves forward.
      final dt = math.max(0.0, t - _phaseAt);
      _phaseAt = t;
      final step = dt / _settleSeconds;
      _life.value = widget.paused
          ? math.max(0, _life.value - step)
          : math.min(1, _life.value + step);
      if (!widget.paused) {
        if (_settleStart != null) {
          // Resumed part-way through settling: breathe in from where it is.
          _phase = math.acos((1 - 2 * cycle).clamp(-1.0, 1.0)) / (2 * math.pi);
          _settleStart = _settleFrom = _settleFollowFrom = null;
        }
        _phase = (_phase + dt / period) % 1;
        cycle = 0.5 - 0.5 * math.cos(2 * math.pi * _phase);
        // The following parts trail the body: never a jump, whatever the
        // rate, a pause or a resume does to the breath.
        follow += (cycle - follow) * (1 - math.exp(-dt / _followSeconds));
      } else if (cycle > 0 || follow > 0) {
        // Paused: the breath settles to rest rather than freezing half-way,
        // its parts together.
        _settleStart ??= t;
        _settleFrom ??= cycle;
        _settleFollowFrom ??= follow;
        final u = (t - _settleStart!) / _settleSeconds;
        final left = u >= 1 ? 0.0 : 1 - easeInOut(u);
        cycle = _settleFrom! * left;
        follow = _settleFollowFrom! * left;
        if (cycle == 0) _phase = 0;
      }
      if (cycle == 0 && follow == 0) {
        _settleStart = _settleFrom = _settleFollowFrom = null;
      }
      _cycleNow = cycle;
      _followNow = follow;
      // Coming to rest is written at once, not left to the throttle.
      if (cycle == 0 && _cycle.value != 0) _cycle.value = 0;
      if (follow == 0 && _follow.value != 0) _follow.value = 0;
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
    // deep breath moves every part at once, so it gets every frame.
    if (t > 5 && _breathStart == null && t - _lastFrame < 0.03) return;
    _lastFrame = t;
    _time.value = t;
    // Written with the frame, not every tick, so the throttle holds.
    if (_cycle.value != cycle) _cycle.value = cycle;
    if (_follow.value != follow) _follow.value = follow;
    // Paused, settled and drawn in: nothing is left to move, so stop.
    if (_continuous &&
        widget.paused &&
        cycle == 0 &&
        follow == 0 &&
        _life.value == 0 &&
        t > MarkMoments.drawnBy(widget.mark)) {
      _stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _crossfade.dispose();
    _turn.dispose();
    _pulse.dispose();
    _time.dispose();
    _cycle.dispose();
    _follow.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors =
        widget.colors ?? MeditejoPalette.of(context).markColors(scheme);
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _pulseOpacity,
        child: RepaintBoundary(
          child: CustomPaint(
            key: const ValueKey('meditejo_mark'),
            size: switch (widget.size) {
              final side? => Size.square(side),
              null => Size.infinite,
            },
            painter: MarkPainter(
              mark: widget.mark,
              colors: colors,
              time: _time,
              still: _still,
              // A paused player's mark comes to rest; Home's keeps its idle
              // motion for as long as it is seen.
              life: _life,
              breathStart: _breathStart,
              cycle: _continuous ? _cycle : null,
              follow: _continuous ? _follow : null,
              from: _from,
              fade: _still && _from != null ? _crossfade : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints [mark] at [time]'s moment, without a tile, so it sits on whatever
/// is below. [still] paints the settled frame. An atmospheric scene is
/// clipped to its circle here; the circle never moves.
///
/// [life] is the strength of the parts' idle motion (see `MarkMotion`);
/// without it they have none.
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
    this.life,
    this.breathStart,
    this.cycle,
    this.follow,
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
  final ValueListenable<double>? life;
  final double? breathStart;

  /// A continuous breath, 0 out to 1 in, moving the mark's parts as a deep
  /// breath does; null when the mark only rests. [follow] is the same
  /// breath as the parts that trail the body feel it ([cycle] if null).
  final ValueListenable<double>? cycle;
  final ValueListenable<double>? follow;
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
      _layer(canvas, mark, 1, () {
        renderer.draw(mark, t, still: still, tile: tile, motion: motionAt(t));
      });
    }
    canvas.restore();
  }

  /// How the mark's parts move at clock time [t]: the idle motion, and a
  /// deep breath (one from a touch, or the continuous one) on top of it.
  @visibleForTesting
  MarkMotion motionAt(double t) {
    if (still) return MarkMotion.none;
    final life = this.life?.value ?? 0.0;
    final start = breathStart;
    if (start != null) {
      final s = t - start;
      return MarkMotion(
        life: life,
        deep: MarkMoments.swellAt(s),
        follow: MarkMoments.swellAt(s, lag: MarkMoments.partLag),
        run: MarkMoments.runAt(s),
      );
    }
    final deep = cycle?.value ?? 0.0;
    return MarkMotion(life: life, deep: deep, follow: follow?.value ?? deep);
  }

  static final _circle = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.5));

  /// Draws one mark at [opacity]: a scene inside its circle.
  static void _layer(
    Canvas canvas,
    MarkSpec m,
    double opacity,
    void Function() draw,
  ) {
    if (opacity <= 0) return;
    canvas.save();
    if (m.family == MarkFamily.atmos) canvas.clipPath(_circle);
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
      old.life != life ||
      old.breathStart != breathStart ||
      old.cycle != cycle ||
      old.follow != follow ||
      !identical(old.from, from) ||
      old.fade != fade;
}
