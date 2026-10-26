import 'dart:convert';
import 'dart:typed_data';

/// A built mark: everything needed to draw it, and nothing random. The
/// generator (`mark_generator.dart`) makes one from a seed; the painter
/// (`widgets/branding/mark_painter.dart`) draws it at any moment of its
/// breath. A pinned mark is stored as this, frozen ([toJson]), so a later
/// change to the generator never redraws a mark the user kept.
///
/// Coordinates are in a unit tile: (0, 0) top left, (1, 1) bottom right.
sealed class MarkSpec {
  const MarkSpec({required this.seed, required this.type, required this.fit});

  /// `<family>-<anything>`: `g-` gesture, `m-` minimal, `a-` atmospheric.
  final String seed;

  /// The kind within the family, e.g. `shelter` or `doorway`.
  final String type;

  /// How far the composition is scaled to stay inside the safe circle.
  final double fit;

  MarkFamily get family;

  /// The frozen form's format. Bump it when the JSON's shape changes, and
  /// keep reading the older one.
  static const formatVersion = 1;

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  static MarkSpec decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);

  static MarkSpec fromJson(Map<String, Object?> json) {
    final v = json['v'] as int? ?? 1;
    if (v > formatVersion) {
      throw FormatException('Unknown mark format $v');
    }
    final seed = json['seed'] as String;
    final type = json['type'] as String;
    final fit = _d(json['fit']);
    return switch (json['family']) {
      'gesture' => GestureMark(
        seed: seed,
        type: type,
        fit: fit,
        stroke: MarkStroke.fromJson(_map(json['stroke'])),
        blob: MarkBlob.fromJson(_map(json['blob'])),
        duration: _d(json['dur']),
      ),
      'minimal' => MinimalMark(
        seed: seed,
        type: type,
        fit: fit,
        roles: [for (final r in json['roles'] as List) r as String],
        blobs: {
          for (final e in _map(json['blobs']).entries)
            e.key: MarkBlob.fromJson(_map(e.value)),
        },
        stones: [
          for (final s in (json['stones'] as List? ?? const []))
            MarkBlob.fromJson(_map(s)),
        ],
        values: {
          for (final e in _map(json['values']).entries) e.key: _d(e.value),
        },
        mullion: json['mullion'] as bool? ?? false,
      ),
      'atmos' => AtmosMark(
        seed: seed,
        type: type,
        fit: fit,
        misregister: (_d(json['misX']), _d(json['misY'])),
        sun: MarkBlob.fromJson(_map(json['sun'])),
        horizon: _d(json['h']),
        layers: [
          for (final l in json['layers'] as List) RidgeLayer.fromJson(_map(l)),
        ],
        door: (_d(json['doorW']), _d(json['doorH'])),
        ring: json['ring'] == null
            ? null
            : MarkStroke.fromJson(_map(json['ring'])),
      ),
      final f => throw FormatException('Unknown mark family $f'),
    };
  }

  Map<String, Object?> _base() => {
    'v': formatVersion,
    'seed': seed,
    'family': family.name,
    'type': type,
    'fit': _r(fit),
  };
}

enum MarkFamily {
  gesture,
  minimal,
  atmos;

  static MarkFamily ofSeed(String seed) => switch (seed[0]) {
    'm' => minimal,
    'a' => atmos,
    _ => gesture,
  };

  String get prefix => switch (this) {
    gesture => 'g',
    minimal => 'm',
    atmos => 'a',
  };
}

/// One hand-drawn line and one pebble, making a place together.
class GestureMark extends MarkSpec {
  const GestureMark({
    required super.seed,
    required super.type,
    required super.fit,
    required this.stroke,
    required this.blob,
    required this.duration,
  });

  final MarkStroke stroke;
  final MarkBlob blob;

  /// Seconds the line takes to draw itself.
  final double duration;

  @override
  MarkFamily get family => MarkFamily.gesture;

  @override
  Map<String, Object?> toJson() => {
    ..._base(),
    'stroke': stroke.toJson(),
    'blob': blob.toJson(),
    'dur': _r(duration),
  };
}

/// Two or three flat shapes, cut slightly by hand. Which shapes and numbers
/// it has depends on [type]; see the generator.
class MinimalMark extends MarkSpec {
  const MinimalMark({
    required super.seed,
    required super.type,
    required super.fit,
    required this.roles,
    required this.blobs,
    required this.values,
    this.stones = const [],
    this.mullion = false,
  });

  /// Three palette roles (`form`, `stroke`, `accent`), in the order the
  /// shapes take them.
  final List<String> roles;
  final Map<String, MarkBlob> blobs;
  final Map<String, double> values;

  /// A cairn's stones, bottom up.
  final List<MarkBlob> stones;

  /// Whether a window has its cross bars.
  final bool mullion;

  double operator [](String key) => values[key]!;

  @override
  MarkFamily get family => MarkFamily.minimal;

  @override
  Map<String, Object?> toJson() => {
    ..._base(),
    'roles': roles,
    'blobs': {for (final e in blobs.entries) e.key: e.value.toJson()},
    if (stones.isNotEmpty) 'stones': [for (final s in stones) s.toJson()],
    'values': {for (final e in values.entries) e.key: _r(e.value)},
    if (mullion) 'mullion': true,
  };
}

/// A printed scene with one clear silhouette: dawn, ridges, a moon pool, a
/// lit doorway, a halo or a shoreline.
class AtmosMark extends MarkSpec {
  const AtmosMark({
    required super.seed,
    required super.type,
    required super.fit,
    required this.misregister,
    required this.sun,
    required this.horizon,
    required this.layers,
    required this.door,
    this.ring,
  });

  /// The second plate's offset, as in two-colour printing.
  final (double, double) misregister;
  final MarkBlob sun;
  final double horizon;
  final List<RidgeLayer> layers;

  /// The lit doorway's width and height.
  final (double, double) door;

  /// The halo's ring.
  final MarkStroke? ring;

  @override
  MarkFamily get family => MarkFamily.atmos;

  @override
  Map<String, Object?> toJson() => {
    ..._base(),
    'misX': _r(misregister.$1),
    'misY': _r(misregister.$2),
    'sun': sun.toJson(),
    'h': _r(horizon),
    'layers': [for (final l in layers) l.toJson()],
    'doorW': _r(door.$1),
    'doorH': _r(door.$2),
    if (ring != null) 'ring': ring!.toJson(),
  };
}

/// One ridge of mist: a base height and two sines.
class RidgeLayer {
  const RidgeLayer({
    required this.y,
    required this.amp,
    required this.f,
    required this.ph,
    required this.f2,
    required this.ph2,
    required this.period,
  });

  factory RidgeLayer.fromJson(Map<String, Object?> j) => RidgeLayer(
    y: _d(j['y']),
    amp: _d(j['amp']),
    f: _d(j['f']),
    ph: _d(j['ph']),
    f2: _d(j['f2']),
    ph2: _d(j['ph2']),
    period: _d(j['per']),
  );

  final double y, amp, f, ph, f2, ph2, period;

  Map<String, Object?> toJson() => {
    'y': _r(y),
    'amp': _r(amp),
    'f': _r(f),
    'ph': _r(ph),
    'f2': _r(f2),
    'ph2': _r(ph2),
    'per': _r(period),
  };
}

/// A pebble: radius r(θ) = R(1 + Σ aₖ sin(kθ + φₖ)) for k = 2, 3, 4, plus a
/// fine "cut" edge. Drawn with its harmonics scaled by how imperfect it is
/// at that moment: 0 is a true circle, 1 its full organic shape.
class MarkBlob {
  MarkBlob({
    required this.cx,
    required this.cy,
    required this.r,
    required this.rot,
    required this.asp,
    required this.a,
    required this.p,
    required this.cut,
    required this.cp,
    required this.ck,
    this.rx,
    this.ry,
  });

  factory MarkBlob.fromJson(Map<String, Object?> j) => MarkBlob(
    cx: _d(j['cx']),
    cy: _d(j['cy']),
    r: _d(j['R']),
    rot: _d(j['rot']),
    asp: _d(j['asp']),
    a: _list(j['a']),
    p: _list(j['p']),
    cut: _d(j['cut']),
    cp: _list(j['cp']),
    ck: [for (final k in j['ck'] as List) (k as num).toInt()],
    rx: j['rx'] == null ? null : _d(j['rx']),
    ry: j['ry'] == null ? null : _d(j['ry']),
  );

  // Mutable only while the generator places it, as `marks.js` does.
  double cx, cy, r, rot;
  final double asp;
  final List<double> a, p;
  final double cut;
  final List<double> cp;
  final List<int> ck;

  /// A flattened stone or cushion's radii (its unit radius is scaled by
  /// these).
  double? rx, ry;

  Map<String, Object?> toJson() => {
    'cx': _r(cx),
    'cy': _r(cy),
    'R': _r(r),
    'rot': _r(rot),
    'asp': _r(asp),
    'a': [for (final x in a) _r(x)],
    'p': [for (final x in p) _r(x)],
    'cut': _r(cut),
    'cp': [for (final x in cp) _r(x)],
    'ck': ck,
    if (rx != null) 'rx': _r(rx!),
    if (ry != null) 'ry': _r(ry!),
  };
}

/// A hand-drawn ribbon: its centreline sampled evenly by arc length, the
/// normal and width at each sample, and the pen clock ([cost], 0 to 1, slower
/// in tight curves) that a partial draw follows.
class MarkStroke {
  MarkStroke({
    required this.x,
    required this.y,
    required this.nx,
    required this.ny,
    required this.w,
    required this.cost,
    required this.length,
  });

  factory MarkStroke.fromJson(Map<String, Object?> j) => MarkStroke(
    x: _f64(j['x']),
    y: _f64(j['y']),
    nx: _f64(j['nx']),
    ny: _f64(j['ny']),
    w: _f64(j['w']),
    cost: _f64(j['cost']),
    length: _d(j['len']),
  );

  final Float64List x, y, nx, ny, w, cost;
  final double length;

  int get n => x.length;

  Map<String, Object?> toJson() => {
    'x': _rs(x),
    'y': _rs(y),
    'nx': _rs(nx),
    'ny': _rs(ny),
    'w': _rs(w),
    'cost': _rs(cost),
    'len': _r(length),
  };
}

/// Five decimals: a hundred-thousandth of the tile, far under a pixel at any
/// size the mark is drawn.
double _r(double x) => (x * 1e5).roundToDouble() / 1e5;

List<double> _rs(List<double> xs) => [for (final x in xs) _r(x)];

double _d(Object? x) => (x as num).toDouble();

List<double> _list(Object? xs) => [for (final x in xs as List) _d(x)];

Float64List _f64(Object? xs) => Float64List.fromList(_list(xs));

Map<String, Object?> _map(Object? x) => (x as Map).cast<String, Object?>();
