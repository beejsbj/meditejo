import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/registry.dart';

/// The art's composition (`compose.js`, round 5): a tight meaning map, a
/// seeded builder, presets, and the frozen form that `curated_art.json`
/// ships.
///
///     card = ground (an atmosphere or paper) + figure? + accent?
///
/// **The order of random draws is part of the output,** as on the page:
/// a class's draws decide every item built from it. Items Meditejo ships
/// are drawn from their frozen entries, never rebuilt, so generator changes
/// can't move them; everything else is built here from its id.

/// One row of the meaning map. Round 4's rows list grounds, figures and
/// accents; round 5's place rows list (ground, figure) pairs. A variant
/// after a colon is pinned: `rings:ripple`, `terrace:tiles`.
@immutable
class ArtClass {
  const ArtClass(
    this.label, {
    this.grounds = const [],
    this.figures = const [],
    this.pairs = const [],
    this.accents = const [null],
    this.layout,
  });

  final String label;
  final List<String> grounds;
  final List<String?> figures;
  final List<(String, String?)> pairs;
  final List<String?> accents;

  /// A fixed layout (the bell icons').
  final String? layout;
}

/// Where a figure sits.
typedef Place = ({double cx, double cy, double s});

abstract final class ArtMap {
  static const classes = <String, ArtClass>{
    // Round 5: places, as (ground, figure) pairs.
    'terrace': ArtClass(
      'Rain on a terrace',
      pairs: [
        ('terrace:tiles', null),
        ('terrace:tiles', 'droplets'),
        ('terrace:eave', null),
        ('terrace:eave', 'streaks'),
      ],
    ),
    'umbrella': ArtClass(
      'Rain on an umbrella',
      pairs: [('rainfield', 'umbrella'), ('mist', 'umbrella')],
    ),
    'window': ArtClass(
      'Rain at the window',
      pairs: [('window', 'droplets'), ('room', 'window')],
    ),
    'car': ArtClass(
      'Rain on a car roof',
      pairs: [('car', 'droplets'), ('car', 'streaks')],
    ),
    'indoors': ArtClass(
      'Rain from indoors',
      pairs: [('room', 'window'), ('room', 'lamp'), ('window', 'droplets')],
    ),
    'balcony': ArtClass(
      'Rain on a balcony',
      pairs: [
        ('balcony:balcony', 'streaks'),
        ('balcony:balcony', null),
        ('rainfield', 'railing'),
      ],
    ),
    'cafe': ArtClass(
      'Café',
      pairs: [('room', 'cup'), ('bokeh', 'cup'), ('room', 'lamp')],
    ),
    'house': ArtClass(
      'Quiet house',
      pairs: [('room', 'doorway'), ('room', 'lamp'), ('bokeh', 'doorway')],
    ),
    'laundry': ArtClass(
      'Laundry room',
      pairs: [('room', 'porthole'), ('paper', 'porthole')],
    ),
    'fanhum': ArtClass(
      'Fan hum',
      pairs: [('room', 'fan'), ('paper', 'fan'), ('mist', 'fan')],
    ),
    'metro': ArtClass(
      'Trains',
      pairs: [('metro', 'strap'), ('bokeh', 'strap'), ('metro', 'threads')],
    ),
    // Round 5: bells, the figure pinned to the bell's own controls.
    'bell': ArtClass(
      'Bells',
      pairs: [
        ('paper', 'bell'),
        ('mist', 'bell'),
        ('dawn', 'bell'),
        ('night', 'bell'),
      ],
    ),
    'bellicon': ArtClass(
      'Bell icons',
      pairs: [('paper', 'bell'), ('mist', 'bell'), ('night', 'bell')],
      layout: 'icon',
    ),
    // Round 4.
    'rain': ArtClass(
      'Rain',
      grounds: ['rainfield', 'mist'],
      figures: ['streaks', 'rings:ripple', 'disc:halo'],
      accents: [null, null, 'disc:plain'],
    ),
    'stream': ArtClass(
      'Stream and river',
      grounds: ['mist', 'paper'],
      figures: ['waves', 'threads'],
    ),
    'brook': ArtClass(
      'Forest brook',
      grounds: ['canopy', 'mist'],
      figures: ['waves', 'threads'],
      accents: [null, 'flock'],
    ),
    'sea': ArtClass(
      'Sea',
      grounds: ['sea', 'dawn'],
      figures: ['disc:plain', 'flock', 'scales'],
      accents: [null, 'flock'],
    ),
    'wind': ArtClass(
      'Wind',
      grounds: ['mist', 'dawn'],
      figures: ['threads', 'grass'],
      accents: [null, 'flock'],
    ),
    'pines': ArtClass(
      'Wind in the pines',
      grounds: ['canopy', 'mist'],
      figures: ['threads'],
      accents: [null, 'flock'],
    ),
    'birds': ArtClass(
      'Birds',
      grounds: ['canopy', 'dawn'],
      figures: ['flock', 'petals'],
      accents: [null, 'disc:plain'],
    ),
    'fire': ArtClass(
      'Fire',
      grounds: ['hearth'],
      figures: ['fire:tongues', 'fire:embers'],
    ),
    'room': ArtClass(
      'Rooms',
      grounds: ['bokeh', 'paper'],
      figures: ['disc:halo', 'breath', 'rings:target'],
    ),
    'fan': ArtClass(
      'Fan',
      grounds: ['paper', 'mist'],
      figures: ['mandala', 'rings:target'],
    ),
    'train': ArtClass(
      'Trains',
      grounds: ['night', 'bokeh'],
      figures: ['threads', 'disc:halo'],
    ),
    'night': ArtClass(
      'Night',
      grounds: ['night'],
      figures: ['stars', 'moon'],
      accents: [null, 'stars'],
    ),
    'frogs': ArtClass(
      'Frogs by a pond',
      grounds: ['night'],
      figures: ['rings:ripple', 'moon', 'stars'],
      accents: [null, 'stars'],
    ),
    'nightshore': ArtClass(
      'Crickets by the sea',
      grounds: ['night'],
      figures: ['waves', 'moon', 'stars'],
      accents: [null, 'stars'],
    ),
    'meadow': ArtClass(
      'Meadow at night',
      grounds: ['night'],
      figures: ['grass', 'stars', 'moon'],
      accents: [null, 'stars'],
    ),
    'noise': ArtClass('Noise colours', grounds: ['grain'], figures: [null]),
    'drone': ArtClass(
      'Drone',
      grounds: ['night', 'mist'],
      figures: ['rings:target', 'mandala', 'breath'],
    ),
    'binaural': ArtClass(
      'Binaural',
      grounds: ['paper', 'night'],
      figures: ['rings:interference'],
    ),
    'course': ArtClass(
      'Courses',
      grounds: ['dawn', 'mist', 'paper'],
      figures: [
        'mandala',
        'lotus',
        'cairn',
        'ammonite',
        'disc:rayed',
        'breath',
      ],
      accents: [null, null, 'disc:plain', 'stars'],
    ),
    'single': ArtClass(
      'Singles',
      grounds: ['paper', 'mist'],
      figures: ['disc', 'breath', 'lotus', 'rings:ripple', 'ammonite'],
    ),
    'teacher': ArtClass(
      'Teachers',
      grounds: ['paper'],
      figures: ['mandala', 'lotus'],
    ),
    'playlist': ArtClass(
      'Playlists',
      grounds: ['paper', 'mist'],
      figures: ['cairn', 'scales', 'mandala', 'rings:target'],
    ),
  };

  /// Sound ids whose class is a round 5 place.
  static const places = {
    'rain-terrace': 'terrace',
    'rain-umbrella': 'umbrella',
    'rain-window': 'window',
    'rain-car': 'car',
    'rain-indoors': 'indoors',
    'rain-balcony': 'balcony',
    'cafe': 'cafe',
    'room-house': 'house',
    'laundry-room': 'laundry',
    'fan': 'fanhum',
    'train': 'metro',
    'train-yamanote': 'metro',
  };

  /// The cover kinds that are classes of their own.
  static const coverKinds = {'course', 'single', 'teacher', 'playlist'};

  /// Which class an id belongs to: bells, then sounds, then the cover
  /// kinds. [legacy] is round 4's answer, which presets keep using so the
  /// curated presets don't move. Null when nothing in the map fits (a
  /// sound this map doesn't know).
  static String? classOf(String id, String? kind, {bool legacy = false}) {
    if (kind == 'bell' || kind == 'bellicon') return kind;
    if (!legacy && places.containsKey(id)) return places[id];
    if (kind != null && kind != 'sound' && kind != 'preset') {
      return classes.containsKey(kind) ? kind : null;
    }
    if (id.startsWith('rain')) return 'rain';
    if (id == 'stream' || id == 'river') return 'stream';
    if (id == 'forest-brook') return 'brook';
    if (const ['waves', 'sea', 'ocean'].contains(id)) return 'sea';
    if (id == 'wind-trees') return 'pines';
    if (id.startsWith('wind')) return 'wind';
    if (const [
      'forest-birds',
      'dawn-chorus',
      'evening-birds',
      'wood-thrush',
    ].contains(id)) {
      return 'birds';
    }
    if (id.startsWith('fire')) return 'fire';
    if (id == 'fan') return 'fan';
    if (id.startsWith('train')) return 'train';
    if (const ['room-house', 'cafe', 'laundry-room'].contains(id)) {
      return 'room';
    }
    if (id == 'night-frogs') return 'frogs';
    if (id == 'night-shore') return 'nightshore';
    if (id == 'night-meadow') return 'meadow';
    if (id.startsWith('night')) return 'night';
    if (id.startsWith('noise')) return 'noise';
    return classes.containsKey(id) ? id : null; // drone, binaural
  }

  static const layouts = <String, Place>{
    'centre': (cx: 0.5, cy: 0.48, s: 0.3),
    'big': (cx: 0.5, cy: 0.5, s: 0.38),
    'low': (cx: 0.5, cy: 0.58, s: 0.27),
    'high': (cx: 0.5, cy: 0.34, s: 0.22),
    'left': (cx: 0.36, cy: 0.44, s: 0.25),
    'right': (cx: 0.64, cy: 0.44, s: 0.25),
    'icon': (cx: 0.5, cy: 0.52, s: 0.31),
  };

  /// Figures with homes (fire low, birds high); the rest use [anywhere].
  static const homes = <String, List<String>>{
    'fire': ['low', 'centre'],
    'grass': ['low', 'big'],
    'lotus': ['low', 'centre'],
    'cairn': ['low', 'centre'],
    'flock': ['high', 'left', 'right'],
    'moon': ['high', 'left', 'right'],
    'disc': ['high', 'centre', 'left', 'right'],
    'stars': ['centre', 'big'],
    'petals': ['centre', 'big'],
    'waves': ['low', 'centre'],
    'streaks': ['centre', 'big'],
    'threads': ['centre', 'big'],
    'lamp': ['centre', 'left', 'right'],
    'window': ['centre', 'big'],
    'cup': ['low', 'centre'],
    'porthole': ['centre', 'big'],
    'fan': ['centre', 'big'],
    'umbrella': ['centre', 'big'],
    'railing': ['low'],
    'droplets': ['centre', 'big'],
    'strap': ['high', 'centre'],
    'doorway': ['centre', 'big'],
    'bell': ['centre', 'big'],
  };
  static const anywhere = ['centre', 'centre', 'big', 'left', 'right'];

  /// Every (ground, figure) pair a class allows, and its accents: what the
  /// meaning map permits to meet. Variants are dropped (`rings`, not
  /// `rings:ripple`).
  static ({Set<(String, String?)> pairs, Set<String?> accents}) allowed(
    String cls,
  ) {
    final m = classes[cls]!;
    String? name(String? s) => s?.split(':').first;
    final pairs = m.pairs.isNotEmpty
        ? {for (final (g, f) in m.pairs) (name(g)!, name(f))}
        : {
            for (final g in m.grounds)
              for (final f in m.figures) (name(g)!, name(f)),
          };
    return (pairs: pairs, accents: {for (final a in m.accents) name(a)});
  }
}

({String name, String? kind})? _parse(String? s) {
  if (s == null) return null;
  final parts = s.split(':');
  return (name: parts[0], kind: parts.length > 1 ? parts[1] : null);
}

/// A primitive placed in a composition: its name, pinned variant, layout
/// (figures only) and parameters.
@immutable
class ArtLayer {
  const ArtLayer(this.name, this.params, {this.kind, this.layout});

  final String name;
  final String? kind, layout;
  final Map<String, Object?> params;

  P get p => P(params);
}

/// One card's composition: ground, figure and accent, the inks' seed and
/// the second plate's misregistration.
@immutable
class ArtComposition {
  const ArtComposition({
    required this.cls,
    required this.seed,
    required this.ground,
    this.figure,
    this.accent,
    required this.inkSeed,
    required this.misregister,
    this.preset,
  });

  /// `compose.js` `thaw`: a frozen entry from `curated_art.json`.
  factory ArtComposition.thaw(Map<String, Object?> e) {
    ArtLayer? layer(Object? v) {
      if (v == null) return null;
      final m = (v as Map).cast<String, Object?>();
      return ArtLayer(
        m['name']! as String,
        (m['params']! as Map).cast<String, Object?>(),
        kind: m['kind'] as String?,
        layout: m['layout'] as String?,
      );
    }

    final mis = (e['misregister']! as List).cast<num>();
    return ArtComposition(
      cls: e['cls']! as String,
      seed: e['seed']! as String,
      ground: layer(e['ground'])!,
      figure: layer(e['figure']),
      accent: layer(e['accent']),
      inkSeed: e['inkSeed']! as String,
      misregister: (mis[0].toDouble(), mis[1].toDouble()),
    );
  }

  final String cls, seed, inkSeed;
  final ArtLayer ground;
  final ArtLayer? figure, accent;
  final (double, double) misregister;

  /// The preset this was built for, if any.
  final String? preset;

  ArtComposition withAccent(ArtLayer? accent, {String? cls, String? preset}) =>
      ArtComposition(
        cls: cls ?? this.cls,
        seed: seed,
        ground: ground,
        figure: figure,
        accent: accent,
        inkSeed: inkSeed,
        misregister: misregister,
        preset: preset ?? this.preset,
      );

  /// `compose.js` `freeze`: plain data, every number rounded to 1e-4.
  Map<String, Object?> freeze() => {
    'seed': seed,
    'cls': cls,
    'ground': {'name': ground.name, 'params': _plain(ground.params)},
    'figure': figure == null
        ? null
        : {
            'name': figure!.name,
            'kind': figure!.kind,
            'layout': figure!.layout,
            'params': _plain(figure!.params),
          },
    'accent': accent == null
        ? null
        : {
            'name': accent!.name,
            'kind': accent!.kind,
            'params': _plain(accent!.params),
          },
    'misregister': _plain([misregister.$1, misregister.$2]),
    'inkSeed': inkSeed,
  };

  static Object? _plain(Object? v) => switch (v) {
    double d => d.isFinite ? (d * 1e4 + 0.5).floorToDouble() / 1e4 : null,
    Map m => {
      for (final e in m.entries)
        if (!(e.key as String).startsWith('_')) e.key: _plain(e.value),
    },
    List l => [for (final x in l) _plain(x)],
    _ => v,
  };
}

/// A preset as the composition reads it: its id and its layers' sound ids
/// with their volumes.
typedef ArtPreset = ({String id, List<(String, double)> layers});

abstract final class Compose {
  /// `compose.js` `inks`: inks that read on [tone].
  static Inks inks(ArtRoles c, Rgb tone, SeededRandom r) {
    final light = lum(tone) > 0.3;
    final strong = light
        ? [
            c.stroke,
            mix(c.stroke, c.form, 0.35),
            c.deep,
          ].where((x) => contrast(x, tone) > 2).toList()
        : [c.light, mix(c.light, c.accent, 0.3)];
    final mains = [
      c.form,
      ...strong,
      c.accent,
    ].where((x) => contrast(x, tone) > 1.4).toList();
    final main = _pickOr(r, mains) ?? strong[0];
    final alt = _pickOr(
      r,
      [
        c.accent,
        mix(c.accent, c.form, 0.3),
        mix(main, tone, 0.4),
      ].where((x) => x.hex != main.hex).toList(),
    )!;
    return Inks(
      paper: tone,
      main: main,
      alt: alt,
      line: light ? mix(c.stroke, tone, 0.25) : mix(c.light, tone, 0.25),
      glow: mix(c.accent, c.light, 0.45),
    );
  }

  // `r.pick` on a list that may be empty: still draws, as the page does.
  static T? _pickOr<T>(SeededRandom r, List<T> items) {
    final i = (r.next() * items.length).floor();
    return items.isEmpty ? null : items[i];
  }

  static T _pick<T>(SeededRandom r, List<T> items) =>
      items[(r.next() * items.length).floor()];

  /// `compose.js` `build`: [seed] is the whole identity of a composition.
  static ArtComposition build(
    String cls,
    String seed, {
    Map<String, Object?> groundExtra = const {},
    Map<String, Object?> figureExtra = const {},
  }) {
    final m = ArtMap.classes[cls]!;
    final r = SeededRandom('r4:$cls:$seed');
    final String gName;
    final ({String name, String? kind})? f, a;
    final gOpts = <String, Object?>{...groundExtra};
    if (m.pairs.isNotEmpty) {
      final (gs, fs) = _pick(r, m.pairs);
      final g = _parse(gs)!;
      gName = g.name;
      if (g.kind != null) gOpts['variant'] = g.kind;
      f = _parse(fs);
      a = _parse(_pick(r, m.accents));
    } else {
      gName = _pick(r, m.grounds);
      f = _parse(_pick(r, m.figures));
      a = _parse(_pick(r, m.accents));
    }
    final ground = ArtLayer(
      gName,
      ArtRegistry.ground(gName).build(SeededRandom('$seed:g'), gOpts),
    );
    final mis = (r.range(-0.01, 0.01), r.range(0.003, 0.01));
    ArtLayer? figure, accent;
    if (f != null) {
      final layout =
          m.layout ?? _pick(r, ArtMap.homes[f.name] ?? ArtMap.anywhere);
      final pl = ArtMap.layouts[layout]!;
      final p = ArtRegistry.figure(f.name).build(SeededRandom('$seed:f'), {
        'cx': pl.cx,
        'cy': pl.cy,
        's': pl.s,
        ...figureExtra,
      }, 'figure');
      if (f.kind != null) p['kind'] = f.kind;
      figure = ArtLayer(
        f.name,
        p,
        kind: f.kind ?? p['kind'] as String?,
        layout: layout,
      );
    }
    if (a != null && (f == null || a.name != f.name)) {
      final fig = ArtMap.layouts[figure?.layout ?? 'centre']!;
      final ang = r.range(0, math.pi * 2), d = fig.s * r.range(1.1, 1.45);
      final p = ArtRegistry.figure(a.name).build(SeededRandom('$seed:a'), {
        'cx': clamp(fig.cx + math.cos(ang) * d, 0.15, 0.85),
        'cy': clamp(fig.cy + math.sin(ang) * d * 0.7 - 0.06, 0.14, 0.62),
        's': r.range(0.06, 0.09),
      }, 'accent');
      if (a.kind != null) p['kind'] = a.kind;
      accent = ArtLayer(a.name, p, kind: a.kind);
    }
    return ArtComposition(
      cls: cls,
      seed: seed,
      ground: ground,
      figure: figure,
      accent: accent,
      inkSeed: '$seed:ink',
      misregister: mis,
    );
  }

  /// `compose.js` `buildFor`: an item by id and kind. Null when the map has
  /// no class for it.
  static ArtComposition? buildFor(
    String id,
    String? kind, {
    String? seed,
    bool legacy = false,
  }) {
    final cls = ArtMap.classOf(id, kind, legacy: legacy);
    if (cls == null) return null;
    return build(
      cls,
      seed ?? id,
      groundExtra: id.startsWith('noise-')
          ? {'colour': id.substring(6)}
          : const {},
      figureExtra: id.startsWith('bell-')
          ? {'preset': ArtRegistry.bellPresetFor(id)}
          : const {},
    );
  }

  /// `compose.js` `buildPreset`: the loudest layer's ground and figure; the
  /// next layer's figure becomes the accent, so the blend reads as one
  /// place. Layers keep round 4's classes. Layers the map doesn't know are
  /// skipped.
  static ArtComposition? buildPreset(ArtPreset preset, {String? seed}) {
    final layers = [
      for (final l in preset.layers)
        if (ArtMap.classOf(l.$1, 'sound', legacy: true) != null) l,
    ];
    // A stable sort, loudest first, as Array.prototype.sort is.
    final sorted = [for (var i = 0; i < layers.length; i++) (i, layers[i])]
      ..sort((a, b) {
        final c = b.$2.$2.compareTo(a.$2.$2);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    if (sorted.isEmpty) return null;
    final base = seed ?? preset.id;
    final first = sorted[0].$2.$1;
    var comp = buildFor(first, 'sound', seed: base, legacy: true)!;
    ArtLayer? accent = comp.accent;
    if (sorted.length > 1) {
      final next = sorted[1].$2.$1;
      final sub = buildFor(next, 'sound', seed: '$base:$next', legacy: true)!;
      final pick = sub.figure;
      if (pick != null &&
          (comp.figure == null || pick.name != comp.figure!.name)) {
        final fig = ArtMap.layouts[comp.figure?.layout ?? 'centre']!;
        final p = ArtRegistry.figure(pick.name).build(
          SeededRandom('$base:blend'),
          {'cx': fig.cx > 0.5 ? 0.24 : 0.76, 'cy': 0.28, 's': 0.12},
          'accent',
        );
        if (pick.kind != null) p['kind'] = pick.kind;
        accent = ArtLayer(pick.name, p, kind: pick.kind);
      }
    }
    comp = comp.withAccent(accent, cls: 'preset', preset: preset.id);
    return comp;
  }

  /// `compose.js` `candidates`: [n] seeds per item from a pool of 40,
  /// covering as many (ground, figure) pairs as the map allows.
  static List<ArtComposition> candidates(
    ArtComposition Function(String seed) make,
    String id, {
    int n = 8,
  }) {
    final pool = [for (var i = 0; i < 40; i++) make('$id#$i')];
    final out = <ArtComposition>[], seen = <String>{};
    for (final c in pool) {
      final key = '${c.ground.name}|${c.figure?.name}|${c.figure?.kind}';
      if (seen.add(key)) out.add(c);
      if (out.length >= n) break;
    }
    for (final c in pool) {
      if (out.length >= n) break;
      if (!out.contains(c)) out.add(c);
    }
    return out;
  }

  // ---------- draw ----------

  /// `compose.js` `draw`, without the grain: ground, figure, then the
  /// accent on a second, misregistered plate (multiply on light paper,
  /// screen on dark). [H] is height / width. Lay [ArtGrain] over it.
  static void draw(
    Ctx ctx,
    ArtComposition comp,
    ArtRoles c,
    double t, {
    bool still = false,
    double H = 1,
    bool scrim = false,
    String? only,
  }) {
    // Figures on flat paper (`only: 'figure'`) don't need their ground.
    final g = only == 'figure' ? null : ArtRegistry.ground(comp.ground.name);
    final paperTone = ArtRegistry.ground(
      'paper',
    ).tone(c, P(const {'key': 'light', 'k': 0.04}));
    if (only == 'figure') {
      ctx.fillStyle = css(paperTone);
      ctx.fillRect(0, 0, 1, H);
    } else {
      g!.draw(ctx, comp.ground.p, c, t, still, H);
    }
    if (only != 'ground') {
      ctx.save();
      if (H < 1) {
        ctx.translate((1 - H) / 2, 0);
        ctx.scale(H, H);
      }
      final kf = inks(
        c,
        only == 'figure' ? paperTone : g!.tone(c, comp.ground.p),
        SeededRandom(comp.inkSeed),
      );
      // Fire is always warm, whatever the palette's form colour is.
      final kfig = comp.figure?.name == 'fire'
          ? kf.copyWith(
              main: mix(c.accent, c.form, 0.25),
              alt: c.accent,
              line: mix(c.deep, c.form, 0.35),
              glow: mix(c.accent, c.light, 0.5),
            )
          : kf;
      final figure = comp.figure;
      if (figure != null) {
        ArtRegistry.figure(figure.name).draw(ctx, figure.p, kfig, t, still);
      }
      final accent = comp.accent;
      if (accent != null) {
        ctx.save();
        ctx.translate(comp.misregister.$1, comp.misregister.$2);
        ctx.globalCompositeOperation = lum(kf.paper) > 0.3
            ? ui.BlendMode.multiply
            : ui.BlendMode.screen;
        ArtRegistry.figure(accent.name).draw(
          ctx,
          accent.p,
          kf.copyWith(main: kf.alt, alt: kf.main),
          t,
          still,
        );
        ctx.restore();
      }
      ctx.restore();
    }
    if (scrim) {
      final gr = ctx.createLinearGradient(0, H * 0.5, 0, H)
        ..addColorStop(0, css(c.deep, 0))
        ..addColorStop(1, css(c.deep, 0.6));
      ctx.fillStyle = gr;
      ctx.fillRect(0, H * 0.5, 1, H * 0.5);
    }
  }
}
