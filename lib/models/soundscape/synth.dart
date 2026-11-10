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

  /// Linear SoLoud voice volume, before the layer's own volume. The voice
  /// comes out at [kSoLoudWaveAmplitude] × this.
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

/// Peak of SoLoud's sine and triangle waveforms at voice volume 1:
/// flutter_soloud 4.1.7 generates them at ±0.5, not full scale
/// (`soloud_misc.cpp`, `generateWaveform`), so a voice's volume is twice
/// its output amplitude.
const kSoLoudWaveAmplitude = 0.5;

/// Power response |H(f)|² of the BS.1770 K-weighting filter (the pre-filter
/// shelf and the RLB high-pass) with the standard 48 kHz coefficients.
double kWeightingPower(double hz) {
  final w = 2 * math.pi * hz / 48000;
  return _biquadPower(
        w,
        1.53512485958697,
        -2.69169618940638,
        1.19839281085285,
        -1.69065929318241,
        0.73248077421585,
      ) *
      _biquadPower(w, 1, -2, 1, -1.99004745483398, 0.99007225036621);
}

double _biquadPower(
  double w,
  double b0,
  double b1,
  double b2,
  double a1,
  double a2,
) {
  final c1 = math.cos(w), s1 = math.sin(w);
  final c2 = math.cos(2 * w), s2 = math.sin(2 * w);
  final nr = b0 + b1 * c1 + b2 * c2, ni = -(b1 * s1 + b2 * s2);
  final dr = 1 + a1 * c1 + a2 * c2, di = -(a1 * s1 + a2 * s2);
  return (nr * nr + ni * ni) / (dr * dr + di * di);
}

/// Mean square of a waveform of peak 1: a²/2 for a sine, a²/3 for a
/// triangle.
double _meanSquare(OscillatorWave wave) =>
    wave == OscillatorWave.triangle ? 1 / 3 : 1 / 2;

/// The K-weighted power, at voice volume 1, of one oscillator voice: what
/// it adds to BS.1770 loudness (summed over channels; SoLoud's pans keep a
/// mono voice's total power).
double _unitPower(double hz, OscillatorWave wave) =>
    kSoLoudWaveAmplitude *
    kSoLoudWaveAmplitude *
    _meanSquare(wave) *
    kWeightingPower(hz);

/// BS.1770 loudness (LUFS) to K-weighted power.
double _lufsPower(double lufs) => math.pow(10, (lufs + 0.691) / 10).toDouble();

// ---------------------------------------------------------------------------
// Drone

enum DroneTimbre { pure, warm, bright }

/// A held chord: up to [maxRoots] roots, each with its octave and fifth,
/// slowly swelling.
class DroneParams {
  const DroneParams({
    List<double> rootsHz = const [110],
    this.timbre = DroneTimbre.warm,
    this.movement = 0.5,
  }) : _given = rootsHz;

  /// Most roots a chord holds (#69).
  static const maxRoots = 3;

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

  final List<double> _given;

  /// The roots as given, tidied whatever they were: within the range,
  /// lowest first, no repeats, at most [maxRoots], and never empty (an
  /// empty list is the default 110 Hz).
  List<double> get rootsHz {
    final tidy = <double>{
      for (final hz in _given)
        if (hz.isFinite) hz.clamp(40, 440).toDouble(),
    }.toList()..sort();
    return tidy.isEmpty ? const [110] : tidy.take(maxRoots).toList();
  }

  /// The lowest root (the only one, before chords).
  double get rootHz => rootsHz.first;

  final DroneTimbre timbre;

  /// 0 holds still; 1 swells most and fastest.
  final double movement;

  /// Reads `rootsHz`, or the single `rootHz` that saved mixes and presets
  /// from before chords hold. Anything unreadable falls back to 110 Hz.
  factory DroneParams.fromJson(Map<String, Object?> json) {
    final list = json['rootsHz'];
    final chord = [
      if (list is List)
        for (final v in list)
          if (v is num) v.toDouble(),
    ];
    return DroneParams(
      rootsHz: chord.isNotEmpty ? chord : [_num(json['rootHz'], 110, 40, 440)],
      timbre: DroneTimbre.values.firstWhere(
        (t) => t.name == json['timbre'],
        orElse: () => DroneTimbre.warm,
      ),
      movement: _num(json['movement'], 0.5, 0, 1),
    );
  }

  /// One root saves as it always did (`rootHz`), so presets and mixes saved
  /// before chords still match what the editor writes back. A chord adds
  /// `rootsHz`, and keeps its lowest root as `rootHz` for a reader from
  /// before chords.
  Map<String, Object?> toJson() => {
    'rootHz': rootHz,
    if (rootsHz.length > 1) 'rootsHz': rootsHz,
    'timbre': timbre.name,
    'movement': movement,
  };

  DroneParams copyWith({
    List<double>? rootsHz,
    DroneTimbre? timbre,
    double? movement,
  }) => DroneParams(
    rootsHz: rootsHz == null || rootsHz.isEmpty ? this.rootsHz : rootsHz,
    timbre: timbre ?? this.timbre,
    movement: movement ?? this.movement,
  );

  /// The voices: (ratio to the root, relative weight, pan). A detuned twin
  /// of the root beats slowly against it; "warm" and "bright" add upper
  /// partials. Swell periods are incommensurate so the chord never repeats.
  List<OscillatorPartial> partials() {
    final one = <(double, double, double)>[
      (1, 1, 0),
      (1.0015, 0.7, -0.4), // beats with the root about every 6 s at A2
      (2, 0.55, 0.35),
      (1.5, 0.35, -0.25),
      if (timbre != DroneTimbre.pure) ...[(3, 0.22, 0.3), (4, 0.14, -0.3)],
      if (timbre == DroneTimbre.bright) ...[(5, 0.1, 0.45), (6, 0.08, -0.45)],
    ];
    // Every root brings the same voices. Voices on one frequency (A1's
    // octave is A2's root) are one voice, their weights added: two
    // oscillators started apart would sit at an arbitrary phase and add or
    // cancel from one play to the next. "Same" is within 1 part in 10 000,
    // so D2's octave and D3 merge too.
    bool near(double a, double b) => (a - b).abs() <= 1e-4 * math.max(a, b);
    // Only the bright octave is a triangle, and a triangle cannot merge
    // into a sine: where it would land on another root's sine voice, it is
    // a sine too.
    bool octaveIsTriangle(double root) =>
        timbre == DroneTimbre.bright &&
        !rootsHz.any(
          (other) =>
              other != root &&
              [
                for (var j = 0; j < one.length; j++)
                  if (j != 2) one[j].$1,
              ].any((ratio) => near(other * ratio, root * one[2].$1)),
        );
    final voices = <(double, double, double, OscillatorWave)>[];
    for (final root in rootsHz) {
      final triangle = octaveIsTriangle(root);
      for (var i = 0; i < one.length; i++) {
        final hz = root * one[i].$1;
        final w = one[i].$2, pan = one[i].$3;
        final wave = triangle && i == 2
            ? OscillatorWave.triangle
            : OscillatorWave.sine;
        final at = voices.indexWhere((v) => v.$4 == wave && near(v.$1, hz));
        if (at < 0) {
          voices.add((hz, w, pan, wave));
        } else {
          final v = voices[at];
          final sum = v.$2 + w;
          voices[at] = (v.$1, sum, (v.$3 * v.$2 + pan * w) / sum, wave);
        }
      }
    }
    // No two voices share a frequency now, so their powers add: scale
    // the weights so the K-weighted sum of the whole chord lands on the
    // target. A chord is no louder than a single root.
    var power = 0.0;
    var left = 0.0, right = 0.0;
    for (final v in voices) {
      power += v.$2 * v.$2 * _unitPower(v.$1, v.$4);
      left += v.$2 * kSoLoudWaveAmplitude * math.cos((v.$3 + 1) * math.pi / 4);
      right += v.$2 * kSoLoudWaveAmplitude * math.sin((v.$3 + 1) * math.pi / 4);
    }
    var unit = math.sqrt(_lufsPower(kSynthTargetLufs) / power);
    // Low roots weigh little in K-weighting, so a tight low chord needs
    // more gain to reach the target and could peak (every voice in phase)
    // above the bound. Whatever the stored roots, hold it under: that chord
    // plays a little quieter than the target instead.
    final peak = unit * math.max(left, right);
    if (peak > kSynthPeakBound) unit *= 0.98 * kSynthPeakBound / peak;
    final floor = 1 - 0.6 * movement;
    return [
      for (var i = 0; i < voices.length; i++)
        OscillatorPartial(
          hz: voices[i].$1,
          gain: unit * voices[i].$2,
          wave: voices[i].$4,
          pan: voices[i].$3,
          swellPeriod: movement == 0
              ? null
              : Duration(
                  milliseconds:
                      (_swellSeconds[i % _swellSeconds.length] *
                              1000 *
                              (1.6 - movement))
                          .round(),
                ),
          swellFloor: floor,
        ),
    ];
  }
}

/// Swell periods (s), one per voice, all different: the first eight as the
/// single root always had them; the rest for a chord's extra voices.
const _swellSeconds = [
  29, 41, 53, 67, 37, 47, 59, 71, //
  31, 43, 61, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127, 131, 137,
];

/// The most one generated layer may reach in a channel at full volume, every
/// voice in phase: -12 dBFS. Normal roots stay well under it.
const kSynthPeakBound = 0.25;

// ---------------------------------------------------------------------------
// Binaural beats

/// The usual names for a beat frequency's band, from [low] up to (not
/// including) [high]; beta runs to the top of the range.
enum BeatBand {
  delta(BinauralParams.minBeat, 4, 2),
  theta(4, 8, 6),
  alpha(8, 13, 10),
  beta(13, BinauralParams.maxBeat, 16);

  const BeatBand(this.low, this.high, this.centre);

  final double low;
  final double high;

  /// Where choosing the band puts the beat.
  final double centre;

  static BeatBand of(double hz) =>
      values.firstWhere((b) => hz < b.high, orElse: () => beta);

  /// Half-hertz steps from [low] to just under [high] (to [high] itself in
  /// the top band): what the fine control under the band offers.
  List<double> get steps => [
    for (var hz = low; this == beta ? hz <= high : hz < high; hz += 0.5) hz,
  ];
}

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

  /// The band the beat is in.
  BeatBand get band => BeatBand.of(beatHz);

  List<OscillatorPartial> partials() {
    // Each ear hears one tone, carrying half the target power.
    double gain(double hz) => math.sqrt(
      _lufsPower(kSynthTargetLufs) / 2 / _unitPower(hz, OscillatorWave.sine),
    );
    final low = carrierHz - beatHz / 2;
    final high = carrierHz + beatHz / 2;
    return [
      OscillatorPartial(hz: low, gain: gain(low), left: 1, right: 0),
      OscillatorPartial(hz: high, gain: gain(high), left: 0, right: 1),
    ];
  }
}
