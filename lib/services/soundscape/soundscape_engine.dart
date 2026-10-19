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
  const AssetLoopSource(this.asset, {this.channels = 2});

  final String asset;

  /// Stereo loops play at unity in both channels; see [SoLoudSoundscapeEngine].
  final int channels;

  @override
  bool operator ==(Object other) =>
      other is AssetLoopSource &&
      other.asset == asset &&
      other.channels == channels;

  @override
  int get hashCode => Object.hash(asset, channels);
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
/// Levels: SoLoud pans with a constant-power law, so a centred stereo voice
/// plays each channel at 0.707 (−3 dB) while a mono one, spread to both,
/// keeps its loudness. Stereo loops (recordings, the noise) are therefore
/// set to unity in both channels, and every layer plays at the loudness it
/// was made at.
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

  /// Voices fading out (a stopped layer, the old side of a crossfade): they
  /// pause with the rest.
  final _fading = <_Voice>{};
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
    // SoLoud refuses new voices past 16 by default, counting paused and
    // fading ones too; a bright drone alone is 8.
    _soloud.setMaxActiveVoiceCount(64);
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

  /// Loads and starts (silent) the voices for [source]. [at] gives the
  /// position to start a loop at, read as late as possible (after a noise
  /// loop has been generated).
  Future<List<_Voice>> _open(
    LayerSource source, {
    Duration Function()? at,
  }) async {
    final voices = <_Voice>[];
    try {
      switch (source) {
        case AssetLoopSource(:final asset, :final channels):
          final audio = await _soloud.loadAsset(asset, mode: LoadMode.memory);
          voices.add(_loopVoice(audio, at?.call(), stereo: channels == 2));
        case NoiseLoopSource(:final spec):
          final wav = await compute(generateNoiseWav, spec);
          final audio = await _soloud.loadMem(
            'meditejo-noise-${_generated++}.wav',
            wav,
            mode: LoadMode.memory,
          );
          voices.add(_loopVoice(audio, at?.call(), stereo: true));
        case OscillatorSource(:final partials):
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
            final voice = _Voice(
              audio,
              handle,
              weight: p.gain,
              swell: p.swellPeriod == null
                  ? null
                  : LayerMotion(period: p.swellPeriod!, floor: p.swellFloor),
            );
            voices.add(voice);
            _checkPlaying(voice);
            if (p.left != null && p.right != null) {
              _soloud.setPanAbsolute(handle, p.left!, p.right!);
            }
          }
      }
      return voices;
    } catch (_) {
      // Nothing half-built keeps playing or holds memory.
      await _fadeAndDispose(voices, Duration.zero);
      rethrow;
    }
  }

  /// play() reports a refusal (the voice limit) with an invalid handle, not
  /// an exception.
  void _checkPlaying(_Voice voice) {
    if (!_soloud.getIsValidVoiceHandle(voice.handle)) {
      throw StateError('SoLoud refused to play a voice');
    }
  }

  _Voice _loopVoice(AudioSource audio, Duration? at, {required bool stereo}) {
    final handle = _soloud.play(
      audio,
      volume: 0,
      looping: true,
      paused: _paused,
    );
    final voice = _Voice(audio, handle);
    if (!_soloud.getIsValidVoiceHandle(handle)) {
      unawaited(_soloud.disposeSource(audio));
      throw StateError('SoLoud refused to play a loop');
    }
    if (stereo) _soloud.setPanAbsolute(handle, 1, 1);
    // Start somewhere in the loop, so a sound doesn't always open the same
    // way (or, retuning, near where the old loop was).
    final length = _soloud.getLength(audio);
    if (at != null) {
      _soloud.seek(handle, at < length ? at : Duration.zero);
    } else if (length > const Duration(seconds: 2)) {
      _soloud.seek(
        handle,
        Duration(milliseconds: _random.nextInt(length.inMilliseconds - 1000)),
      );
    }
    return voice;
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
      // A new noise loop starts near the old one's position (read after it
      // is generated). The two are not sample-aligned (SoLoud seeks to its
      // buffer), so they are crossfaded with equal power, not linearly.
      final first = layer.voices.firstOrNull;
      final voices = await _open(
        source,
        at: source is NoiseLoopSource && first != null
            ? () => _soloud.getPosition(first.handle)
            : null,
      );
      if (!identical(_layers[key], layer)) {
        // Stopped while the new voices were being made.
        await _fadeAndDispose(voices, Duration.zero);
        return true;
      }
      final outgoing = layer.voices;
      _cancelSwells(layer);
      layer
        ..source = source
        ..voices = voices
        ..gain = gain
        ..motion = motion;
      _crossfadeIn(layer, outgoing);
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

  /// Equal-power crossfade from [outgoing] to [layer]'s new voices, in
  /// steps (SoLoud's fades are linear), then the new voices take up their
  /// drift and swell.
  void _crossfadeIn(_Layer layer, List<_Voice> outgoing) {
    const steps = 6;
    final stepTime = _crossfade ~/ steps;
    final from = [for (final v in outgoing) _soloud.getVolume(v.handle)];
    for (final v in outgoing) {
      v.timer?.cancel();
      v.timer = null;
    }
    _fading.addAll(outgoing);
    var step = 0;
    Timer.periodic(stepTime, (timer) {
      if (_paused) return; // the voices' clocks are stopped too
      step++;
      final t = step / steps;
      final fadeIn = math.sin(t * math.pi / 2);
      final fadeOut = math.cos(t * math.pi / 2);
      for (var i = 0; i < outgoing.length; i++) {
        _soloud.fadeVolume(outgoing[i].handle, from[i] * fadeOut, stepTime);
      }
      if (_layers.containsValue(layer)) {
        for (final v in layer.voices) {
          _soloud.fadeVolume(
            v.handle,
            layer.gain * v.weight * fadeIn,
            stepTime,
          );
        }
      }
      if (step >= steps) {
        timer.cancel();
        if (_layers.containsValue(layer)) _applyLayer(layer, fade: _retune);
        unawaited(
          _fadeAndDispose(
            outgoing,
            stepTime,
          ).whenComplete(() => _fading.removeAll(outgoing)),
        );
      }
    });
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
      // to the midpoint first and hand over there without a step. Faders run
      // on the voice's clock, which stops while paused: hand over only when
      // playing (setPaused re-applies on resume).
      final floor = target * motion.floor;
      _soloud.fadeVolume(voice.handle, (floor + target) / 2, fade);
      if (_paused) continue;
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
    _fading.addAll(layer.voices);
    await _fadeAndDispose(layer.voices, fade);
    _fading.removeAll(layer.voices);
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
    if (_paused == paused) return;
    _paused = paused;
    if (!_available) return;
    for (final voice in [
      for (final layer in _layers.values) ...layer.voices,
      ..._fading,
    ]) {
      try {
        _soloud.setPause(voice.handle, paused);
      } catch (error) {
        // One bad voice (or a device that fails to restart) must not keep
        // the others paused or stop the controller's pass.
        AppLogger.e('SOUNDSCAPE', 'Could not (un)pause a voice', error);
      }
    }
    if (!paused) {
      // Drift and swell hand-overs were held while paused.
      for (final layer in [..._layers.values]) {
        _applyLayer(layer, fade: _retune);
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
