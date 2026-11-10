import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/art_textures.dart';
import 'package:medito/widgets/art/engine/compose.dart';
import 'package:medito/widgets/art/engine/registry.dart';

/// Draws [comp] to fill [size] on [canvas] at [t] seconds: the card's
/// ground, figure and accent, then the baked print [finish]. A card taller
/// than it is wide is drawn square and cropped to the middle, so its figure
/// stays centred.
void paintArt(
  Canvas canvas,
  Size size,
  ArtComposition comp,
  ArtRoles roles,
  double t, {
  bool still = true,
  bool scrim = false,
  ui.Image? finish,
}) {
  if (size.isEmpty) return;
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  var w = size.width;
  if (size.height > size.width) {
    w = size.height;
    canvas.translate((size.width - w) / 2, 0);
  }
  canvas.scale(w);
  final H = size.height / w;
  final ctx = Ctx(canvas);
  Compose.draw(ctx, comp, roles, t, still: still, H: H, scrim: scrim);
  if (finish != null) ctx.drawImage(finish, 0, 0, 1, H);
  canvas.restore();
}

/// The art's palette roles, made once per palette.
ArtRoles artRoles(IdentityPalette palette) =>
    _roles[palette.id] ??= ArtRoles.of(palette);
final _roles = <String, ArtRoles>{};

/// Still frames of the art, rasterised once at their display size and kept
/// in a least-recently-used cache, so lists scroll over images rather than
/// painting (NOTES.md, round 3's port). Keyed by subject, palette, pixel
/// size and scrim; a palette change leaves the old ones to age out.
class ArtRasters {
  ArtRasters._();

  static final instance = ArtRasters._();

  /// About 48 MB of rasters: a long list's worth at phone sizes.
  static const budgetBytes = 48 << 20;

  final _images = <String, ui.Image>{};
  final _pending = <String, Future<ui.Image?>>{};
  var _bytes = 0;

  static String keyOf(
    ArtSubject s,
    IdentityPalette p,
    int w,
    int h,
    bool scrim,
  ) => '${s.key}|${p.id}|${w}x$h${scrim ? '|scrim' : ''}';

  ui.Image? peek(String key) {
    final image = _images.remove(key);
    if (image != null) _images[key] = image;
    return image;
  }

  /// The still frame for [key], drawing it if needed. Null when the
  /// finish isn't ready yet (try again when [ArtTextures] notifies).
  Future<ui.Image?> still(
    String key,
    ArtComposition comp,
    ArtRoles roles,
    int w,
    int h, {
    bool scrim = false,
  }) {
    final have = peek(key);
    if (have != null) return Future.value(have);
    return _pending[key] ??= () async {
      try {
        final logical = Size(w.toDouble(), h.toDouble());
        final side = math.max(w, h).toDouble();
        final finish = await ArtTextures.instance.finishFor(
          roles,
          ArtTextures.finishSize(side),
          h / side,
        );
        final recorder = ui.PictureRecorder();
        paintArt(
          Canvas(recorder),
          logical,
          comp,
          roles,
          60,
          scrim: scrim,
          finish: finish,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(w, h);
        picture.dispose();
        _put(key, image);
        return image;
      } finally {
        _pending.remove(key);
      }
    }();
  }

  void _put(String key, ui.Image image) {
    _images[key] = image;
    _bytes += image.width * image.height * 4;
    while (_bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final gone = _images.remove(oldest)!;
      _bytes -= gone.width * gone.height * 4;
      gone.dispose();
    }
  }

  /// Drops every raster (tests; memory pressure).
  void clear() {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _bytes = 0;
  }
}

/// How long a bell moves after it's struck: 0.8 + 3 × (0.45 + 1.25 ring)
/// seconds, capped at 16 (identity round 5).
Duration bellStrikeLength(ArtComposition comp) {
  final knobs = comp.figure?.p.m['knobs'];
  final ring = knobs is Map ? (knobs['ring'] as num?)?.toDouble() ?? 1.5 : 1.5;
  final s = math.min(0.8 + 3 * (0.45 + 1.25 * ring), 16.0);
  return Duration(milliseconds: (s * 1000).round());
}

/// Generated art for [subject], filling its box: Meditejo's curated card
/// when the subject ships, otherwise one built from its id (decision 22).
///
/// - **Still** by default: a raster of the settled frame, drawn once per
///   palette and size.
/// - **[live]**: moves at up to 30 fps while on screen. It stops off screen,
///   when tickers are muted (a hidden tab or route), and under reduced
///   motion, which keeps the still frame.
/// - **[strike]** (bells): each notification strikes the bell once; it
///   moves as its sound does, then settles back to its still frame.
class ArtCover extends StatefulWidget {
  const ArtCover({
    super.key,
    required this.subject,
    this.live = false,
    this.strike,
    this.scrim = false,
    this.placeholder,
    this.holdWhileChanging = false,
  });

  final ArtSubject subject;
  final bool live;
  final Listenable? strike;

  /// Darkens the lower half, for text laid over the art.
  final bool scrim;

  /// Shown when nothing in the meaning map fits the subject.
  final Widget? placeholder;

  /// Keeps showing the last picture while a changed subject is drawn, for art
  /// that is dragged (a bell being made) and would otherwise flash blank at
  /// every move.
  final bool holdWhileChanging;

  @override
  State<ArtCover> createState() => _ArtCoverState();
}

class _ArtCoverState extends State<ArtCover>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(60);
  ui.Image? _still;
  String? _stillKey;
  Duration? _struckAt;
  Duration _lastFrame = Duration.zero;
  Duration _strikeLength = Duration.zero;
  var _frames = 0;
  var _onScreen = true;

  @override
  void initState() {
    super.initState();
    CuratedArt.instance
      ..addListener(_changed)
      ..load();
    ArtTextures.instance
      ..addListener(_changed)
      ..load();
    widget.strike?.addListener(_struck);
  }

  @override
  void didUpdateWidget(ArtCover old) {
    super.didUpdateWidget(old);
    if (old.strike != widget.strike) {
      old.strike?.removeListener(_struck);
      widget.strike?.addListener(_struck);
    }
  }

  @override
  void dispose() {
    CuratedArt.instance.removeListener(_changed);
    ArtTextures.instance.removeListener(_changed);
    widget.strike?.removeListener(_struck);
    _ticker.dispose();
    _time.dispose();
    _still?.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // The tile keeps its own handle: the cache disposes what it evicts, and a
  // tile still showing that raster must not be left holding a dead image.
  void _adopt(ui.Image image) {
    _still?.dispose();
    _still = image.clone();
  }

  // Stamped with the ticker's clock on its next tick.
  static const _unstamped = Duration(microseconds: -1);

  void _struck() {
    if (mounted) setState(() => _struckAt = _unstamped);
  }

  bool get _motionAllowed => !MediaQuery.disableAnimationsOf(context);

  bool get _striking => _struckAt != null;

  void _tick(Duration elapsed) {
    if (_struckAt == _unstamped) _struckAt = elapsed;
    final struck = _struckAt;
    if (struck != null && elapsed - struck > _strikeLength) {
      setState(() => _struckAt = null);
      return;
    }
    // Up to 30 fps.
    if (elapsed - _lastFrame < const Duration(microseconds: 33000)) return;
    _lastFrame = elapsed;
    if (++_frames % 15 == 0) _onScreen = _visible();
    if (!_onScreen) return;
    final s =
        (struck == null ? elapsed : elapsed - struck).inMicroseconds / 1e6;
    _time.value = struck == null ? 60 + s : s;
  }

  // Whether any of this box is inside the window.
  bool _visible() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final view = View.of(context);
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    return rect.overlaps(screen);
  }

  @override
  Widget build(BuildContext context) {
    final curated = CuratedArt.instance;
    final comp = curated.resolve(widget.subject);
    final palette = MeditejoPalette.of(context).palette;
    final roles = artRoles(palette);
    if (comp == null) {
      return curated.loaded
          ? widget.placeholder ?? _blank(context)
          : _blank(context);
    }
    final animate =
        _motionAllowed &&
        (widget.live || _striking) &&
        TickerMode.valuesOf(context).enabled;
    if (_striking && widget.strike != null) {
      _strikeLength = bellStrikeLength(comp);
    }
    if (animate && !_ticker.isActive) {
      _lastFrame = Duration.zero;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
      _time.value = 60;
    }
    final tone = ArtRegistry.ground(
      comp.ground.name,
    ).tone(roles, comp.ground.p);
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final size = box.biggest;
          if (!size.isFinite || size.isEmpty) return const SizedBox.shrink();
          if (animate) {
            final w = math.max(size.width, size.height);
            final finish = ArtTextures.instance.finish(
              roles,
              ArtTextures.finishSize(
                w * MediaQuery.devicePixelRatioOf(context),
              ),
              size.height / w,
            );
            if (finish == null) {
              unawaited(
                ArtTextures.instance.finishFor(
                  roles,
                  ArtTextures.finishSize(
                    w * MediaQuery.devicePixelRatioOf(context),
                  ),
                  size.height / w,
                ),
              );
            }
            return RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _LivePainter(
                  comp,
                  roles,
                  _time,
                  still: false,
                  scrim: widget.scrim,
                  finish: finish,
                ),
              ),
            );
          }
          return _stillFrame(context, comp, palette, roles, size, tone);
        },
      ),
    );
  }

  Widget _stillFrame(
    BuildContext context,
    ArtComposition comp,
    IdentityPalette palette,
    ArtRoles roles,
    Size size,
    Rgb tone,
  ) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = math.max(1, (size.width * dpr).round());
    final h = math.max(1, (size.height * dpr).round());
    final key = ArtRasters.keyOf(widget.subject, palette, w, h, widget.scrim);
    final rasters = ArtRasters.instance;
    final image = rasters.peek(key);
    if (image != null) {
      if (_stillKey != key || _still == null) _adopt(image);
      _stillKey = key;
    } else if (_stillKey != key) {
      _stillKey = key;
      unawaited(
        rasters.still(key, comp, roles, w, h, scrim: widget.scrim).then((_) {
          if (!mounted || _stillKey != key) return;
          // Re-read the cache: a later raster may already have evicted it,
          // in which case the next build asks again.
          final live = rasters.peek(key);
          setState(() {
            if (live != null) {
              _adopt(live);
            } else {
              _stillKey = null;
            }
          });
        }),
      );
    }
    final current = _stillKey == key || widget.holdWhileChanging
        ? _still
        : null;
    if (current == null) return ColoredBox(color: css(tone));
    return RawImage(
      image: current,
      width: size.width,
      height: size.height,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }

  Widget _blank(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
}

class _LivePainter extends CustomPainter {
  _LivePainter(
    this.comp,
    this.roles,
    this.time, {
    required this.still,
    required this.scrim,
    this.finish,
  }) : super(repaint: time);

  final ArtComposition comp;
  final ArtRoles roles;
  final ValueListenable<double> time;
  final bool still, scrim;
  final ui.Image? finish;

  @override
  void paint(Canvas canvas, Size size) => paintArt(
    canvas,
    size,
    comp,
    roles,
    time.value,
    still: still,
    scrim: scrim,
    finish: finish,
  );

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.comp != comp ||
      old.roles != roles ||
      old.finish != finish ||
      old.scrim != scrim;
}
