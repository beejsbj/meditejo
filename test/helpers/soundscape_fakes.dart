import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';
import 'package:medito/services/soundscape/soundscape_keep_alive.dart';

/// A silent [SoundscapeEngine] that records what it was asked to play.
class FakeSoundscapeEngine implements SoundscapeEngine {
  final playing = <String, double>{};
  double master = 1;
  bool paused = false;

  @override
  Future<bool> start(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    playing[key] = gain;
    return true;
  }

  final retuned = <String, LayerSource>{};

  @override
  Future<bool> retune(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    retuned[key] = source;
    playing[key] = gain;
    return true;
  }

  @override
  void setGain(String key, double gain, {LayerMotion? motion}) =>
      playing[key] = gain;

  @override
  Future<void> stop(String key, {Duration fade = Duration.zero}) async =>
      playing.remove(key);

  @override
  void setMaster(double gain, {Duration fade = Duration.zero}) => master = gain;

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  Future<void> stopAll({Duration fade = Duration.zero}) async =>
      playing.clear();

  int shutdowns = 0;

  @override
  Future<void> shutdown() async => shutdowns++;
}

/// The bundled library, read straight from disk: `rootBundle` hands an
/// asset this size to an isolate, which a widget test's fake clock never
/// lets finish.
final bundledSoundLibrary = SoundLibrary.fromJson(
  jsonDecode(File(kSoundLibraryAsset).readAsStringSync())
      as Map<String, Object?>,
);

/// Overrides that keep widget tests away from the audio device and the
/// Android keep-alive channel. The library is the bundled one.
List<Override> soundscapeTestOverrides(FakeSoundscapeEngine engine) => [
  soundLibraryProvider.overrideWith((ref) async => bundledSoundLibrary),
  soundscapeEngineProvider.overrideWithValue(engine),
  soundscapeKeepAliveProvider.overrideWithValue(
    const NoopSoundscapeKeepAlive(),
  ),
];
