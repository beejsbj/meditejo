import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_soloud/flutter_soloud.dart';

import '../../utils/logger.dart';

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
/// keeps its loudness. Stereo loops are therefore set to unity in both
/// channels, and every layer plays at the loudness it was made at.
class SoLoudSoundscapeEngine implements SoundscapeEngine {
  SoLoudSoundscapeEngine({math.Random? random})
    : _random = random ?? math.Random();

  static const _fadeIn = Duration(milliseconds: 1800);
  static const _fadeOut = Duration(milliseconds: 1200);
  static const _retune = Duration(milliseconds: 250);

  final math.Random _random;
  final _sources = <String, AudioSource>{};
  final _handles = <String, SoundHandle>{};
  final _motionTimers = <String, Timer>{};
  final _levels = <String, (double, LayerMotion?)>{};
  Future<void>? _ready;
  bool _paused = false;
  double _master = 1;

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
    // fading ones too.
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
      final audio = await switch (source) {
        AssetLoopSource(:final asset) => _soloud.loadAsset(
          asset,
          mode: LoadMode.memory,
        ),
      };
      _sources[key] = audio;
      final handle = _soloud.play(
        audio,
        volume: 0,
        looping: true,
        paused: _paused,
      );
      // play() reports a refusal (voice limit) with an invalid handle, not
      // an exception.
      if (!_soloud.getIsValidVoiceHandle(handle)) {
        throw StateError('SoLoud refused to play $key');
      }
      _handles[key] = handle;
      if (source.channels == 2) _soloud.setPanAbsolute(handle, 1, 1);
      // Start somewhere in the loop, so a sound doesn't always open the
      // same way.
      final length = _soloud.getLength(audio);
      if (length > const Duration(seconds: 2)) {
        _soloud.seek(
          handle,
          Duration(milliseconds: _random.nextInt(length.inMilliseconds - 1000)),
        );
      }
      _apply(key, gain, motion, fade: _fadeIn);
      return true;
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not start $key', error, stack);
      await stop(key, fade: Duration.zero);
      return false;
    }
  }

  @override
  void setGain(String key, double gain, {LayerMotion? motion}) {
    if (!_handles.containsKey(key)) return;
    _apply(key, gain, motion, fade: _retune);
  }

  void _apply(
    String key,
    double gain,
    LayerMotion? motion, {
    required Duration fade,
  }) {
    final handle = _handles[key];
    if (handle == null) return;
    _levels[key] = (gain, motion);
    _motionTimers.remove(key)?.cancel();
    if (motion == null) {
      _soloud.fadeVolume(handle, gain, fade);
      return;
    }
    // SoLoud's LFO starts at the midpoint of its range and rises, so fade to
    // the midpoint first and hand over there without a step. Faders run on
    // the voice's clock, which stops while paused: hand over only when
    // playing (setPaused re-applies on resume).
    final floor = gain * motion.floor;
    _soloud.fadeVolume(handle, (floor + gain) / 2, fade);
    if (_paused) return;
    _motionTimers[key] = Timer(fade, () {
      _motionTimers.remove(key);
      final h = _handles[key];
      if (h != null && _soloud.getIsValidVoiceHandle(h)) {
        _soloud.oscillateVolume(h, floor, gain, motion.period);
      }
    });
  }

  @override
  Future<void> stop(String key, {Duration fade = _fadeOut}) async {
    _motionTimers.remove(key)?.cancel();
    _levels.remove(key);
    final handle = _handles.remove(key);
    final source = _sources.remove(key);
    if (handle == null && source == null) return;
    try {
      if (handle != null && fade > Duration.zero && !_paused) {
        _soloud.fadeVolume(handle, 0, fade);
        await Future<void>.delayed(fade);
      }
      if (handle != null) await _soloud.stop(handle);
      if (source != null) await _soloud.disposeSource(source);
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not stop $key', error, stack);
    }
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
    for (final MapEntry(:key, value: handle) in [..._handles.entries]) {
      try {
        _soloud.setPause(handle, paused);
      } catch (error) {
        // One bad voice (or a device that fails to restart) must not keep
        // the others paused or stop the controller's pass.
        AppLogger.e('SOUNDSCAPE', 'Could not (un)pause $key', error);
      }
    }
    if (!paused) {
      // Drift hand-overs were held while paused.
      for (final MapEntry(:key, value: level) in [..._levels.entries]) {
        if (level.$2 != null) _apply(key, level.$1, level.$2, fade: _retune);
      }
    }
  }

  @override
  Future<void> stopAll({Duration fade = _fadeOut}) async {
    await Future.wait([
      for (final key in [..._handles.keys]) stop(key, fade: fade),
    ]);
  }
}
