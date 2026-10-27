import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/background_sounds/background_sounds_model.dart';
import '../../providers/cues/custom_bell_provider.dart';
import '../bells/custom_bell_id.dart';

final sessionBellPreviewProvider = Provider<SessionBellPreview>((ref) {
  final preview = SessionBellPreview(
    bellFile: (id) => ref.read(customBellStoreProvider).fileFor(id),
  );
  ref.onDispose(preview.dispose);
  return preview;
});

/// Foreground audition only; never changes the meditation's cue schedule.
class SessionBellPreview {
  SessionBellPreview({
    AudioPlayer? player,
    Future<String?> Function(String id)? bellFile,
  }) : _player = player,
       _bellFile = bellFile;
  AudioPlayer? _player;
  final Future<String?> Function(String id)? _bellFile;
  int _generation = 0;

  /// Rings [asset]: a bundled bell's asset path, or the id of a bell the user
  /// made (nothing rings for one that no longer exists).
  Future<void> play(double volume, {String asset = kSessionBellAsset}) async {
    final generation = ++_generation;
    final player = _player ??= newPlayer();
    if (isCustomBellId(asset)) {
      final path = await _bellFile?.call(asset);
      if (path == null || generation != _generation) return;
      await player.setFilePath(path);
    } else {
      await player.setAsset(asset);
    }
    if (generation != _generation) return;
    await player.setVolume(volume);
    if (generation != _generation) return;
    await player.play();
  }

  /// Rings the WAV at [path], a bell being made that is not saved yet.
  Future<void> playFile(String path, double volume) async {
    final generation = ++_generation;
    final player = _player ??= newPlayer();
    await player.setFilePath(path);
    if (generation != _generation) return;
    await player.setVolume(volume);
    if (generation != _generation) return;
    await player.play();
  }

  /// On Android a played preview must not request audio focus: the session's
  /// own player would hear it as another app taking focus, duck to 30% and
  /// leave the soundscape paused. Android plays a short sound without it; iOS
  /// needs the session activated.
  static AudioPlayer newPlayer() =>
      AudioPlayer(handleAudioSessionActivation: !Platform.isAndroid);

  Future<void> stop() async {
    _generation++;
    await _player?.stop();
  }

  Future<void> dispose() async {
    _generation++;
    await _player?.dispose();
  }
}
