import 'dart:math' as math;

/// One resonance of a bell: a sine at [f] Hz that decays with time constant
/// [tau] seconds (`Mode` in tools/meditejo/generate_bells.py).
///
/// [rise] > 0 lets the mode swell in. [beat] > 0 splits it into two sines
/// [beat] Hz apart, [split] being the upper half's share of the energy; the
/// ring wobbles at that rate. [glideDrop] and [glideTau] are a pitch that
/// settles after the strike (the wooden fish).
class BellMode {
  const BellMode(
    this.f,
    this.a,
    this.tau, {
    this.rise = 0,
    this.beat = 0,
    this.split = 0.45,
    this.phase = 0,
    this.glideDrop = 0,
    this.glideTau = 0,
  });

  final double f, a, tau, rise, beat, split, phase, glideDrop, glideTau;

  BellMode copyWith({double? f, double? a, double? tau, double? beat}) =>
      BellMode(
        f ?? this.f,
        a ?? this.a,
        tau ?? this.tau,
        rise: rise,
        beat: beat ?? this.beat,
        split: split,
        phase: phase,
        glideDrop: glideDrop,
        glideTau: glideTau,
      );
}

/// The strike: a short burst of noise through a two-pole low-pass at
/// [lowpass] Hz, [seconds] long, decaying with [tau] and opening over
/// [attack] (`strike()` in the generator).
class BellHit {
  const BellHit(this.lowpass, this.tau, this.level, this.attack, this.seconds);

  final double lowpass, tau, level, attack, seconds;
}

/// A soft wash of noise that blooms and fades under a gong.
class BellWash {
  const BellWash(this.lowpass, this.level, this.rise, this.tau);

  final double lowpass, level, rise, tau;
}

/// The five controls of a bell, in the units [BellFigure.knobs] gives them
/// (`KNOBS`): pitch in Hz, bright a 0..1 share of the ring's energy, ring a
/// decay time in seconds, strike 0 (soft mallet) to 1 (hard), shimmer a beat
/// in Hz.
class BellKnobs {
  const BellKnobs({
    required this.pitch,
    required this.bright,
    required this.ring,
    required this.strike,
    required this.shimmer,
  });

  factory BellKnobs.fromJson(Map<String, Object?> json) => BellKnobs(
    pitch: (json['pitch'] as num).toDouble(),
    bright: (json['bright'] as num).toDouble(),
    ring: (json['ring'] as num).toDouble(),
    strike: (json['strike'] as num).toDouble(),
    shimmer: (json['shimmer'] as num).toDouble(),
  );

  final double pitch, bright, ring, strike, shimmer;

  Map<String, double> toJson() => {
    'pitch': pitch,
    'bright': bright,
    'ring': ring,
    'strike': strike,
    'shimmer': shimmer,
  };

  BellKnobs copyWith({
    double? pitch,
    double? bright,
    double? ring,
    double? strike,
    double? shimmer,
  }) => BellKnobs(
    pitch: pitch ?? this.pitch,
    bright: bright ?? this.bright,
    ring: ring ?? this.ring,
    strike: strike ?? this.strike,
    shimmer: shimmer ?? this.shimmer,
  );

  double operator [](String name) => switch (name) {
    'pitch' => pitch,
    'bright' => bright,
    'ring' => ring,
    'strike' => strike,
    'shimmer' => shimmer,
    _ => throw ArgumentError.value(name, 'name'),
  };

  @override
  bool operator ==(Object other) =>
      other is BellKnobs &&
      other.pitch == pitch &&
      other.bright == bright &&
      other.ring == ring &&
      other.strike == strike &&
      other.shimmer == shimmer;

  @override
  int get hashCode => Object.hash(pitch, bright, ring, strike, shimmer);
}

/// A shipped bell's synthesis: its modes and strike, from
/// tools/meditejo/generate_bells.py (see `bell_recipes.dart`).
class BellRecipe {
  const BellRecipe({required this.modes, required this.hit, this.wash});

  final List<BellMode> modes;
  final BellHit hit;
  final BellWash? wash;

  /// The loudest mode, which the pitch, ring and shimmer controls read.
  BellMode get main => _mainOf(modes);

  /// The five controls this bell is made with (`bell_params.py`).
  BellKnobs get knobs {
    final m = main;
    return BellKnobs(
      pitch: m.f,
      bright: upperShare(modes),
      ring: m.tau,
      strike: hardnessOf(hit.lowpass),
      shimmer: m.beat,
    );
  }

  /// Where strike 0 and 1 sit: the strike's low-pass runs 300 Hz to 10 kHz,
  /// on a log scale.
  static const hardLo = 300.0, hardHi = 10000.0;

  static double hardnessOf(double lowpass) =>
      (math.log(lowpass / hardLo) / math.log(hardHi / hardLo)).clamp(0.0, 1.0);

  static double lowpassOf(double strike) =>
      hardLo * math.pow(hardHi / hardLo, strike);

  /// The share of the ring's energy (a² · tau) that sits above the loudest
  /// mode.
  static double upperShare(List<BellMode> modes) {
    final main = _mainOf(modes);
    double e(BellMode m) => m.a * m.a * m.tau;
    var total = 0.0, upper = 0.0;
    for (final m in modes) {
      total += e(m);
      if (m.f > main.f * 1.05) upper += e(m);
    }
    return total > 0 ? upper / total : 0;
  }

  static BellMode _mainOf(List<BellMode> modes) {
    var main = modes.first;
    for (final m in modes) {
      if (m.a > main.a) main = m;
    }
    return main;
  }
}
