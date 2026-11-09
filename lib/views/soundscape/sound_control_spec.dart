import 'package:intl/intl.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';

import 'sound_controls.dart';

/// Which controls each sound has (#71): curated, not set by the user, and
/// all drawn from the one vocabulary in `sound_controls.dart`.
///
/// Every layer, recording or generated, has the same two in the mix: its
/// volume (a range) and Swell (the toggle). A generated sound adds the
/// controls below behind Adjust. The pattern throughout: chips name the
/// usual choices; a finer control, where there is one, sits under them.
class SoundControlSpec {
  const SoundControlSpec({this.adjust = const [], this.headphones = false});

  /// What Adjust opens, top to bottom. Empty: no Adjust.
  final List<SoundControl> adjust;

  /// It only works on headphones, and says so.
  final bool headphones;

  bool get adjustable => adjust.isNotEmpty;
}

/// The controls of the sound [id].
SoundControlSpec soundControlSpec(String id) => switch (id) {
  kSynthNoiseId => noiseControls,
  kSynthDroneId => droneControls,
  kSynthBinauralId => binauralControls,
  // A recording is what it is: volume and Swell only.
  _ => const SoundControlSpec(),
};

String _hz(AppLocalizations l10n, double hz, {String pattern = '0.0#'}) =>
    '${NumberFormat(pattern, l10n.localeName).format(hz)} Hz';

String _bandLabel(double hz) =>
    hz >= 1000 ? '${(hz / 1000).round()}k' : '${hz.round()}';

// ---------------------------------------------------------------------------
// Noise: the colour, then a named shape; the ten bands fold under the shape
// for anyone who wants to draw their own curve.

final noiseControls = SoundControlSpec(
  adjust: [
    SoundChips<NoiseColour>(
      id: 'noise_colour',
      title: (l) => l.noiseColour,
      choices: [
        SoundChoice(NoiseColour.white, 'white', (l) => l.noiseWhite),
        SoundChoice(NoiseColour.pink, 'pink', (l) => l.noisePink),
        SoundChoice(NoiseColour.brown, 'brown', (l) => l.noiseBrown),
      ],
      read: (p) => {NoiseParams.fromJson(p).colour},
      write: (p, s) =>
          NoiseParams.fromJson(p).copyWith(colour: s.single).toJson(),
    ),
    SoundChips<NoiseShape>(
      id: 'noise_shape',
      title: (l) => l.noiseShape,
      choices: [
        SoundChoice(NoiseShape.even, 'even', (l) => l.noiseShapeEven),
        SoundChoice(NoiseShape.soft, 'soft', (l) => l.noiseShapeSoft),
        SoundChoice(NoiseShape.deep, 'deep', (l) => l.noiseShapeDeep),
        SoundChoice(NoiseShape.airy, 'airy', (l) => l.noiseShapeAiry),
      ],
      read: (p) => {?NoiseParams.fromJson(p).shape},
      write: (p, s) =>
          NoiseParams.fromJson(p).copyWith(bands: s.single.bands).toJson(),
      otherLabel: (l) => l.noiseShapeCustom,
      // The curve drawn by hand comes back; the colour stays as now.
      restoreOther: (p, custom) => NoiseParams.fromJson(
        p,
      ).copyWith(bands: NoiseParams.fromJson(custom).bands).toJson(),
      fineFolds: true,
      fine: SoundRanges(
        id: 'noise_bands',
        title: (l) => l.noiseBands,
        count: NoiseParams.bandCentres.length,
        label: (i) => _bandLabel(NoiseParams.bandCentres[i]),
        partId: (i) => 'noise_band_$i',
        read: (p, i) => NoiseParams.fromJson(p).bands[i],
        write: (p, i, v) {
          final params = NoiseParams.fromJson(p);
          return params.copyWith(bands: [...params.bands]..[i] = v).toJson();
        },
      ),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Drone: the root, the timbre, how much it moves.

/// The root chips: up to [DroneParams.maxRoots] together, a chord (#69).
/// At least one stays chosen (the chips ignore a tap that would clear it).
final droneRoots = SoundChips<double>(
  id: 'drone_root',
  title: (l) => l.droneRoot,
  maxSelected: DroneParams.maxRoots,
  caption: (l, _) => l.droneRootHint,
  choices: [
    for (final MapEntry(key: name, value: hz) in DroneParams.roots.entries)
      SoundChoice(hz, name, (_) => name),
  ],
  read: (p) => DroneParams.fromJson(p).rootsHz.map(_snapToChip).toSet(),
  // A root saved off the chips (a stored mix) gets a chip of its own, so it
  // can be seen and turned off; it counts toward the three.
  extraChoices: (p) => [
    for (final hz in DroneParams.fromJson(p).rootsHz)
      if (_snapToChip(hz) == hz && !DroneParams.roots.containsValue(hz))
        SoundChoice(hz, '$hz', (l) => _hz(l, hz, pattern: '0.##')),
  ],
  write: (p, s) =>
      DroneParams.fromJson(p).copyWith(rootsHz: s.toList()).toJson(),
);

/// The chip's own value for a root within 0.01 Hz of it, else [hz].
double _snapToChip(double hz) => DroneParams.roots.values.firstWhere(
  (r) => (r - hz).abs() < 0.01,
  orElse: () => hz,
);

final droneControls = SoundControlSpec(
  adjust: [
    droneRoots,
    SoundChips<DroneTimbre>(
      id: 'drone_timbre',
      title: (l) => l.droneTimbre,
      choices: [
        SoundChoice(DroneTimbre.pure, 'pure', (l) => l.dronePure),
        SoundChoice(DroneTimbre.warm, 'warm', (l) => l.droneWarm),
        SoundChoice(DroneTimbre.bright, 'bright', (l) => l.droneBright),
      ],
      read: (p) => {DroneParams.fromJson(p).timbre},
      write: (p, s) =>
          DroneParams.fromJson(p).copyWith(timbre: s.single).toJson(),
    ),
    SoundRange(
      id: 'drone_movement',
      title: (l) => l.droneMovement,
      read: (p) => DroneParams.fromJson(p).movement,
      write: (p, v) => DroneParams.fromJson(p).copyWith(movement: v).toJson(),
    ),
  ],
);

// ---------------------------------------------------------------------------
// Binaural beats: the beat's band, its exact rate under it, then the tone.

final binauralControls = SoundControlSpec(
  headphones: true,
  adjust: [
    SoundChips<BeatBand>(
      id: 'binaural_band',
      title: (l) => l.binauralBeat,
      choices: [
        SoundChoice(BeatBand.delta, 'delta', (l) => l.binauralDelta),
        SoundChoice(BeatBand.theta, 'theta', (l) => l.binauralTheta),
        SoundChoice(BeatBand.alpha, 'alpha', (l) => l.binauralAlpha),
        SoundChoice(BeatBand.beta, 'beta', (l) => l.binauralBeta),
      ],
      read: (p) => {BinauralParams.fromJson(p).band},
      // Choosing a band moves the beat to its middle; the wheel refines it.
      write: (p, s) =>
          BinauralParams.fromJson(p).copyWith(beatHz: s.single.centre).toJson(),
      caption: (l, p) {
        final band = BinauralParams.fromJson(p).band;
        final low = NumberFormat('0.#', l.localeName).format(band.low);
        final high = NumberFormat('0.#', l.localeName).format(band.high);
        return '$low–$high Hz';
      },
      fine: SoundWheel<double>(
        id: 'binaural_beat',
        title: (l) => l.binauralBeat,
        options: (l, p) {
          final beat = BinauralParams.fromJson(p).beatHz;
          final steps = BinauralParams.fromJson(p).band.steps;
          // A beat saved off the half-hertz steps (the old slider's 6.37)
          // keeps its place on the wheel until it is turned.
          final values = steps.any((s) => (s - beat).abs() < 1e-9)
              ? steps
              : ([...steps, beat]..sort());
          return [
            for (final hz in values)
              WheelOption(hz, _hz(l, hz), semanticsLabel: _hz(l, hz)),
          ];
        },
        read: (p) {
          final beat = BinauralParams.fromJson(p).beatHz;
          // Match the step the options hold, not a float a hair off it.
          for (final s in BinauralParams.fromJson(p).band.steps) {
            if ((s - beat).abs() < 1e-9) return s;
          }
          return beat;
        },
        write: (p, v) =>
            BinauralParams.fromJson(p).copyWith(beatHz: v).toJson(),
      ),
    ),
    SoundRange(
      id: 'binaural_carrier',
      title: (l) => l.binauralCarrier,
      min: BinauralParams.minCarrier,
      max: BinauralParams.maxCarrier,
      readout: (l, v) => _hz(l, v, pattern: '0'),
      read: (p) => BinauralParams.fromJson(p).carrierHz,
      write: (p, v) =>
          BinauralParams.fromJson(p).copyWith(carrierHz: v).toJson(),
    ),
  ],
);
