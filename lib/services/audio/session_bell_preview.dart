import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/background_sounds/background_sounds_model.dart';

final sessionBellPreviewProvider = Provider<SessionBellPreview>((ref) {
  final preview = SessionBellPreview();
  ref.onDispose(preview.dispose);
  return preview;
});

/// Foreground audition only; never changes the meditation's cue schedule.
class SessionBellPreview {
  SessionBellPreview({AudioPlayer? player}) : _player = player;
  AudioPlayer? _player;
  int _generation = 0;

  Future<void> play(double volume, {String asset = kSessionBellAsset}) async {
    final generation = ++_generation;
    final player = _player ??= newPlayer();
    await player.setAsset(asset);
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
