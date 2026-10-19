import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../../models/soundscape/synth.dart';
import '../../utils/logger.dart';
import 'synth/noise_generator.dart';

/// Where a layer's audio comes from.
sealed class LayerSource {
  const LayerSource();
}

/// A bundled recording, looped gaplessly. The loop seam is baked into the
/// file (see `tools/meditejo/sounds/`), so the engine only wraps around.
class AssetLoopSource extends LayerSource {
  const AssetLoopSource(this.asset);

  final String asset;

  @override
  bool operator ==(Object other) =>
      other is AssetLoopSource && other.asset == asset;

  @override
  int get hashCode => asset.hashCode;
}

/// Generated noise (see [generateNoise]), built off the UI isolate and
/// looped like a recording. Seamless by construction.
class NoiseLoopSource extends LayerSource {
  const NoiseLoopSource(this.spec);

  final NoiseSpec spec;

  @override
  bool operator ==(Object other) =>
      other is NoiseLoopSource &&
      other.spec.seed == spec.seed &&
      other.spec.log2Length == spec.log2Length &&
      other.spec.params.colour == spec.params.colour &&
      listEquals(other.spec.params.bands, spec.params.bands);

  @override
  int get hashCode => Object.hash(
    spec.seed,
    spec.params.colour,
    Object.hashAll(spec.params.bands),
  );
}

/// Oscillator voices (drone, binaural beats): continuous tones with no loop
/// to wrap. Frequencies change in place, phase-continuously.
class OscillatorSource extends LayerSource {
  const OscillatorSource(this.partials);

  final List<OscillatorPartial> partials;

  @override
  bool operator ==(Object other) =>
      other is OscillatorSource && listEquals(other.partials, partials);

  @override
  int get hashCode => Object.hashAll(partials);
}

/// A slow swell: the level drifts between [floor] × gain and gain over one
/// [period], on the engine's clock (it keeps going with Dart idle).
class LayerMotion {
  const LayerMotion({required this.period, this.floor = 0.55});

  final Duration period;
  final double floor;

  /// A period between 40 and 90 s, fixed per sound, so layers never swell in
  /// step with each other.
  factory LayerMotion.forSound(String soundId) {
    final seed = soundId.codeUnits.fold<int>(
      17,
      (h, c) => (h * 31 + c) & 0xffff,
    );
    return LayerMotion(period: Duration(seconds: 40 + seed % 51));
  }

  @override
  bool operator ==(Object other) =>
      other is LayerMotion && other.period == period && other.floor == floor;

  @override
  int get hashCode => Object.hash(period, floor);
}

/// Plays the layers of a mix. Gains are linear (0–1); the controller maps
/// slider positions to them. Every change fades: nothing a meditator hears
/// should click or jump.
abstract interface class SoundscapeEngine {
  /// Starts [key] from [source]. Returns false when it can't be played (a
  /// missing or undecodable asset); the controller marks the sound failed.
  Future<bool> start(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  });

  void setGain(String key, double gain, {LayerMotion? motion});

  /// Changes what [key] plays (a generated layer's settings) without a gap:
  /// a new noise loop crossfades in at the same position; oscillators move
  /// to their new frequencies in place.
  Future<bool> retune(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  });

  Future<void> stop(String key, {Duration fade});

  void setMaster(double gain, {Duration fade});

  void setPaused(bool paused);

  Future<void> stopAll({Duration fade});
}

/// [SoundscapeEngine] on flutter_soloud (SoLoud + miniaudio), 4.1.7.
///
/// Recordings load with [LoadMode.memory]: decoded once into RAM, they loop
/// sample-accurately (SoLoud wraps the read position inside the mix
/// callback), unlike a stream that has to reopen a decoder at the seam.
/// SoLoud mixes its own output stream, alongside the session player's
/// ExoPlayer stream; Android mixes the two.
///
/// A layer is one or more voices: one for a recording or a noise loop, one
/// per oscillator for a drone or binaural beats. A voice's level is the
/// layer gain times its weight.
class SoLoudSoundscapeEngine implements SoundscapeEngine {
  SoLoudSoundscapeEngine({math.Random? random})
    : _random = random ?? math.Random();

  static const _fadeIn = Duration(milliseconds: 1800);
  static const _fadeOut = Duration(milliseconds: 1200);
  static const _retune = Duration(milliseconds: 250);
  static const _crossfade = Duration(milliseconds: 1500);

  final math.Random _random;
  final _layers = <String, _Layer>{};
  Future<void>? _ready;
  bool _paused = false;
  double _master = 1;
  int _generated = 0;

  SoLoud get _soloud => SoLoud.instance;

  /// Whether the native engine loaded. A build or host without it (a test
  /// machine, a missing ABI) plays nothing instead of throwing.
  late final bool _available = () {
    try {
      SoLoud.instance;
      return true;
    } catch (error) {
      AppLogger.e('SOUNDSCAPE', 'SoLoud is unavailable', error);
      return false;
    }
  }();

  Future<void> _ensureReady() => _ready ??= () async {
    if (!_soloud.isInitialized) {
      // 48 kHz: the rate of every bundled loop and of the phone's output,
      // so nothing is resampled. Ambience needs no low latency: the
      // power-saving AAudio mode and a larger buffer suit long screen-off
      // playback better.
      await _soloud.init(
        sampleRate: 48000,
        bufferSize: 4096,
        lowLatency: false,
      );
    }
    _soloud.setGlobalVolume(_master);
  }();

  @override
  Future<bool> start(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    if (!_available) return false;
    try {
      await _ensureReady();
      await stop(key, fade: Duration.zero);
      final layer = _Layer(source, await _open(source), gain, motion);
      _layers[key] = layer;
      _applyLayer(layer, fade: _fadeIn);
      return true;
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not start $key', error, stack);
      await stop(key, fade: Duration.zero);
      return false;
    }
  }

  /// Loads and starts (silent) the voices for [source].
  Future<List<_Voice>> _open(LayerSource source, {Duration? at}) async {
    switch (source) {
      case AssetLoopSource(:final asset):
        final audio = await _soloud.loadAsset(asset, mode: LoadMode.memory);
        return [_loopVoice(audio, at)];
      case NoiseLoopSource(:final spec):
        final wav = await compute(generateNoiseWav, spec);
        final audio = await _soloud.loadMem(
          'meditejo-noise-${_generated++}.wav',
          wav,
          mode: LoadMode.memory,
        );
        return [_loopVoice(audio, at)];
      case OscillatorSource(:final partials):
        final voices = <_Voice>[];
        for (final p in partials) {
          final audio = await _soloud.loadWaveform(
            p.wave == OscillatorWave.triangle
                ? WaveForm.triangle
                : WaveForm.sin,
            false,
            1,
            0,
          );
          _soloud.setWaveformFreq(audio, p.hz);
          final handle = _soloud.play(
            audio,
            volume: 0,
            pan: p.pan,
            paused: _paused,
          );
          if (p.left != null && p.right != null) {
            _soloud.setPanAbsolute(handle, p.left!, p.right!);
          }
          voices.add(
            _Voice(
              audio,
              handle,
              weight: p.gain,
              swell: p.swellPeriod == null
                  ? null
                  : LayerMotion(period: p.swellPeriod!, floor: p.swellFloor),
            ),
          );
        }
        return voices;
    }
  }

  _Voice _loopVoice(AudioSource audio, Duration? at) {
    final handle = _soloud.play(
      audio,
      volume: 0,
      looping: true,
      paused: _paused,
    );
    // Start somewhere in the loop, so a sound doesn't always open the same
    // way (or, retuning, where the old loop was).
    final length = _soloud.getLength(audio);
    if (at != null) {
      _soloud.seek(handle, at < length ? at : Duration.zero);
    } else if (length > const Duration(seconds: 2)) {
      _soloud.seek(
        handle,
        Duration(milliseconds: _random.nextInt(length.inMilliseconds - 1000)),
      );
    }
    return _Voice(audio, handle);
  }

  @override
  void setGain(String key, double gain, {LayerMotion? motion}) {
    final layer = _layers[key];
    if (layer == null) return;
    layer
      ..gain = gain
      ..motion = motion;
    _applyLayer(layer, fade: _retune);
  }

  @override
  Future<bool> retune(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    final layer = _layers[key];
    if (layer == null) {
      return start(key, source, gain: gain, motion: motion);
    }
    if (layer.source == source) {
      setGain(key, gain, motion: motion);
      return true;
    }
    try {
      final old = layer.source;
      if (old is OscillatorSource &&
          source is OscillatorSource &&
          _sameShape(old.partials, source.partials)) {
        // Same voices, new tuning: move them in place.
        for (var i = 0; i < source.partials.length; i++) {
          final p = source.partials[i];
          final v = layer.voices[i];
          _soloud.setWaveformFreq(v.source, p.hz);
          v
            ..weight = p.gain
            ..swell = p.swellPeriod == null
                ? null
                : LayerMotion(period: p.swellPeriod!, floor: p.swellFloor);
        }
        layer
          ..source = source
          ..gain = gain
          ..motion = motion;
        _applyLayer(layer, fade: _retune);
        return true;
      }
      // A new noise loop (same phases, new shape) crossfades in at the old
      // loop's position; anything else crossfades from wherever it is.
      final position = layer.voices.length == 1 && source is NoiseLoopSource
          ? _soloud.getPosition(layer.voices.single.handle)
          : null;
      final voices = await _open(source, at: position);
      final outgoing = layer.voices;
      _cancelSwells(layer);
      layer
        ..source = source
        ..voices = voices
        ..gain = gain
        ..motion = motion;
      _applyLayer(layer, fade: _crossfade);
      unawaited(_fadeAndDispose(outgoing, _crossfade));
      return true;
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not retune $key', error, stack);
      return false;
    }
  }

  bool _sameShape(List<OscillatorPartial> a, List<OscillatorPartial> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].wave != b[i].wave ||
          a[i].pan != b[i].pan ||
          a[i].left != b[i].left ||
          a[i].right != b[i].right) {
        return false;
      }
    }
    return true;
  }

  void _applyLayer(_Layer layer, {required Duration fade}) {
    _cancelSwells(layer);
    for (final voice in layer.voices) {
      final target = layer.gain * voice.weight;
      final motion = voice.swell ?? layer.motion;
      if (motion == null) {
        _soloud.fadeVolume(voice.handle, target, fade);
        continue;
      }
      // SoLoud's LFO starts at the midpoint of its range and rises, so fade
      // to the midpoint first and hand over there without a step.
      final floor = target * motion.floor;
      _soloud.fadeVolume(voice.handle, (floor + target) / 2, fade);
      voice.timer = Timer(fade, () {
        voice.timer = null;
        if (_soloud.getIsValidVoiceHandle(voice.handle)) {
          _soloud.oscillateVolume(voice.handle, floor, target, motion.period);
        }
      });
    }
  }

  void _cancelSwells(_Layer layer) {
    for (final voice in layer.voices) {
      voice.timer?.cancel();
      voice.timer = null;
    }
  }

  Future<void> _fadeAndDispose(List<_Voice> voices, Duration fade) async {
    try {
      if (fade > Duration.zero && !_paused) {
        for (final v in voices) {
          v.timer?.cancel();
          _soloud.fadeVolume(v.handle, 0, fade);
        }
        await Future<void>.delayed(fade);
      }
      for (final v in voices) {
        v.timer?.cancel();
        await _soloud.stop(v.handle);
        await _soloud.disposeSource(v.source);
      }
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not release voices', error, stack);
    }
  }

  @override
  Future<void> stop(String key, {Duration fade = _fadeOut}) async {
    final layer = _layers.remove(key);
    if (layer == null) return;
    await _fadeAndDispose(layer.voices, fade);
  }

  @override
  void setMaster(double gain, {Duration fade = _retune}) {
    _master = gain;
    // Before the first layer starts there is no engine yet; [_ensureReady]
    // applies it.
    if (!_available || !_soloud.isInitialized) return;
    if (fade == Duration.zero) {
      _soloud.setGlobalVolume(gain);
    } else {
      _soloud.fadeGlobalVolume(gain, fade);
    }
  }

  @override
  void setPaused(bool paused) {
    _paused = paused;
    if (!_available) return;
    for (final layer in _layers.values) {
      for (final voice in layer.voices) {
        _soloud.setPause(voice.handle, paused);
      }
    }
  }

  @override
  Future<void> stopAll({Duration fade = _fadeOut}) async {
    await Future.wait([
      for (final key in [..._layers.keys]) stop(key, fade: fade),
    ]);
  }
}

class _Layer {
  _Layer(this.source, this.voices, this.gain, this.motion);

  LayerSource source;
  List<_Voice> voices;
  double gain;
  LayerMotion? motion;
}

class _Voice {
  _Voice(this.source, this.handle, {this.weight = 1, this.swell});

  final AudioSource source;
  final SoundHandle handle;
  double weight;

  /// The voice's own swell (drone partials), over the layer's drift.
  LayerMotion? swell;
  Timer? timer;
}
