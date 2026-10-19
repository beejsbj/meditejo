import 'dart:math' as math;

/// Layers generated on the device instead of shipped (BRIEF decision 6):
/// noise colours, a drone and binaural beats. They sit in a mix beside the
/// recordings, under these ids, with their settings in [SoundLayer.params].
const kSynthNoiseId = 'synth-noise';
const kSynthDroneId = 'synth-drone';
const kSynthBinauralId = 'synth-binaural';

const kSynthIds = [kSynthNoiseId, kSynthDroneId, kSynthBinauralId];

bool isSynthId(String id) => kSynthIds.contains(id);

/// The settings a generated layer starts with; empty for a recording.
Map<String, Object?> defaultSynthParams(String id) => switch (id) {
  kSynthNoiseId => const NoiseParams().toJson(),
  kSynthDroneId => const DroneParams().toJson(),
  kSynthBinauralId => const BinauralParams().toJson(),
  _ => const {},
};

/// Loudness every generated layer is made at, as the recordings are.
const kSynthTargetLufs = -27.0;

double _num(Object? v, double fallback, double min, double max) =>
    ((v is num ? v.toDouble() : fallback).clamp(min, max)).toDouble();

// ---------------------------------------------------------------------------
// Noise

/// The slope of the spectrum: white is flat, pink falls 3 dB an octave,
/// brown 6 dB.
enum NoiseColour {
  white(0),
  pink(1),
  brown(2);

  const NoiseColour(this.exponent);

  /// Power falls as 1/f^exponent.
  final double exponent;

  static NoiseColour parse(Object? v) =>
      values.firstWhere((c) => c.name == v, orElse: () => NoiseColour.pink);
}

/// A myNoise-style generator: a colour, then ten octave bands to shape it.
class NoiseParams {
  const NoiseParams({this.colour = NoiseColour.pink, this.bands = flat});

  /// Octave centres, 31 Hz to 16 kHz.
  static const bandCentres = <double>[
    31.25,
    62.5,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  static const flat = <double>[1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

  final NoiseColour colour;

  /// Amplitude of each band against the colour, 0–1 (1 = the colour as is).
  final List<double> bands;

  factory NoiseParams.fromJson(Map<String, Object?> json) {
    final raw = json['bands'];
    final bands = [
      for (var i = 0; i < bandCentres.length; i++)
        raw is List && i < raw.length ? _num(raw[i], 1, 0, 1) : 1.0,
    ];
    return NoiseParams(colour: NoiseColour.parse(json['colour']), bands: bands);
  }

  Map<String, Object?> toJson() => {'colour': colour.name, 'bands': bands};

  NoiseParams copyWith({NoiseColour? colour, List<double>? bands}) =>
      NoiseParams(colour: colour ?? this.colour, bands: bands ?? this.bands);

  /// A slider at 0 is this far down (−60 dB), not a hole in the spectrum.
  static const floor = 0.001;

  /// The band shaping at [hz]: levels interpolated in dB between octave
  /// centres on a log-frequency axis (smooth bell-shaped bands, like an
  /// equaliser), flat beyond the outer bands.
  double bandGain(double hz) {
    double level(int i) => math.log(math.max(bands[i], floor));
    if (hz <= bandCentres.first) return math.exp(level(0));
    if (hz >= bandCentres.last) return math.exp(level(bands.length - 1));
    final position = math.log(hz / bandCentres.first) / math.ln2;
    final i = position.floor();
    final t = position - i;
    return math.exp(level(i) * (1 - t) + level(i + 1) * t);
  }
}

// ---------------------------------------------------------------------------
// Oscillator layers

enum OscillatorWave { sine, triangle }

/// One oscillator voice of a generated layer.
class OscillatorPartial {
  const OscillatorPartial({
    required this.hz,
    required this.gain,
    this.wave = OscillatorWave.sine,
    this.pan = 0,
    this.left,
    this.right,
    this.swellPeriod,
    this.swellFloor = 1,
  });

  final double hz;

  /// Linear voice gain, before the layer's own volume.
  final double gain;
  final OscillatorWave wave;

  /// -1 left … 1 right. [left]/[right], when set, place it absolutely
  /// (binaural beats: one tone per ear, nothing crossing over).
  final double pan;
  final double? left;
  final double? right;

  /// Slow swell of this voice between [swellFloor] × gain and gain.
  final Duration? swellPeriod;
  final double swellFloor;

  @override
  bool operator ==(Object other) =>
      other is OscillatorPartial &&
      other.hz == hz &&
      other.gain == gain &&
      other.wave == wave &&
      other.pan == pan &&
      other.left == left &&
      other.right == right &&
      other.swellPeriod == swellPeriod &&
      other.swellFloor == swellFloor;

  @override
  int get hashCode =>
      Object.hash(hz, gain, wave, pan, left, right, swellPeriod, swellFloor);
}

/// Linear amplitude for [count] equal sines summing to [lufs] (a sine's
/// mean square is a²/2; K-weighting is about flat from 100 Hz to 1 kHz).
double _sineAmplitude(double lufs, int count) =>
    math.sqrt(2 * math.pow(10, (lufs + 0.691) / 10) / count);

// ---------------------------------------------------------------------------
// Drone

enum DroneTimbre { pure, warm, bright }

/// A held chord on a root: the root, its octave and fifth, slowly swelling.
class DroneParams {
  const DroneParams({
    this.rootHz = 110,
    this.timbre = DroneTimbre.warm,
    this.movement = 0.5,
  });

  /// Roots offered by the editor: A1 to A3 by fifths and fourths.
  static const roots = <String, double>{
    'A1': 55,
    'D2': 73.42,
    'E2': 82.41,
    'G2': 98,
    'A2': 110,
    'C3': 130.81,
    'D3': 146.83,
    'E3': 164.81,
    'A3': 220,
  };

  final double rootHz;
  final DroneTimbre timbre;

  /// 0 holds still; 1 swells most and fastest.
  final double movement;

  factory DroneParams.fromJson(Map<String, Object?> json) => DroneParams(
    rootHz: _num(json['rootHz'], 110, 40, 440),
    timbre: DroneTimbre.values.firstWhere(
      (t) => t.name == json['timbre'],
      orElse: () => DroneTimbre.warm,
    ),
    movement: _num(json['movement'], 0.5, 0, 1),
  );

  Map<String, Object?> toJson() => {
    'rootHz': rootHz,
    'timbre': timbre.name,
    'movement': movement,
  };

  DroneParams copyWith({
    double? rootHz,
    DroneTimbre? timbre,
    double? movement,
  }) => DroneParams(
    rootHz: rootHz ?? this.rootHz,
    timbre: timbre ?? this.timbre,
    movement: movement ?? this.movement,
  );

  /// The voices: (ratio to the root, relative weight, pan). A detuned twin
  /// of the root beats slowly against it; "warm" and "bright" add upper
  /// partials. Swell periods are incommensurate so the chord never repeats.
  List<OscillatorPartial> partials() {
    final spec = <(double, double, double)>[
      (1, 1, 0),
      (1.0015, 0.7, -0.4), // beats with the root about every 6 s at A2
      (2, 0.55, 0.35),
      (1.5, 0.35, -0.25),
      if (timbre != DroneTimbre.pure) ...[(3, 0.22, 0.3), (4, 0.14, -0.3)],
      if (timbre == DroneTimbre.bright) ...[(5, 0.1, 0.45), (6, 0.08, -0.45)],
    ];
    const periods = [29, 41, 53, 67, 37, 47, 59, 71];
    final weightSum = spec.fold<double>(0, (s, p) => s + p.$2 * p.$2);
    final unit = _sineAmplitude(kSynthTargetLufs, 1) / math.sqrt(weightSum);
    final floor = 1 - 0.6 * movement;
    return [
      for (var i = 0; i < spec.length; i++)
        OscillatorPartial(
          hz: rootHz * spec[i].$1,
          gain: unit * spec[i].$2,
          wave: timbre == DroneTimbre.bright && i == 2
              ? OscillatorWave.triangle
              : OscillatorWave.sine,
          pan: spec[i].$3,
          swellPeriod: movement == 0
              ? null
              : Duration(
                  milliseconds:
                      (periods[i % periods.length] * 1000 * (1.6 - movement))
                          .round(),
                ),
          swellFloor: floor,
        ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Binaural beats

/// Two tones, one per ear, [beatHz] apart around [carrierHz]. The beat is
/// made by the brain from the difference, so it needs headphones.
class BinauralParams {
  const BinauralParams({this.carrierHz = 200, this.beatHz = 6});

  static const minCarrier = 80.0;
  static const maxCarrier = 500.0;
  static const minBeat = 0.5;
  static const maxBeat = 30.0;

  final double carrierHz;
  final double beatHz;

  factory BinauralParams.fromJson(Map<String, Object?> json) => BinauralParams(
    carrierHz: _num(json['carrierHz'], 200, minCarrier, maxCarrier),
    beatHz: _num(json['beatHz'], 6, minBeat, maxBeat),
  );

  Map<String, Object?> toJson() => {'carrierHz': carrierHz, 'beatHz': beatHz};

  BinauralParams copyWith({double? carrierHz, double? beatHz}) =>
      BinauralParams(
        carrierHz: carrierHz ?? this.carrierHz,
        beatHz: beatHz ?? this.beatHz,
      );

  /// The usual names for a beat frequency's band.
  String get band => switch (beatHz) {
    < 4 => 'delta',
    < 8 => 'theta',
    < 13 => 'alpha',
    _ => 'beta',
  };

  List<OscillatorPartial> partials() {
    // Each ear hears one tone: per-ear loudness is that of one sine.
    final gain = _sineAmplitude(kSynthTargetLufs, 2);
    return [
      OscillatorPartial(
        hz: carrierHz - beatHz / 2,
        gain: gain,
        left: 1,
        right: 0,
      ),
      OscillatorPartial(
        hz: carrierHz + beatHz / 2,
        gain: gain,
        left: 0,
        right: 1,
      ),
    ];
  }
}
