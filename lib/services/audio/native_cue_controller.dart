import 'package:flutter/services.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/services/bells/custom_bell_store.dart';

/// Native clocks and preloaded audio own cue execution while Flutter sleeps.
/// This channel configures them; no Dart timer drives Android cue playback.
class NativeCueController {
  static const channel = MethodChannel('meditejo/cues');

  /// Where a bell the user made lives, by id. The native engine plays a path,
  /// not an id, so the id is swapped for the file's path on the way over.
  static Future<String?> Function(String id) bellFile =
      CustomBellStore.sharedFileFor;

  // Configurations go to the native engine in the order they were asked for,
  // even when one waits on a bell's file and a later one does not.
  static Future<void> _last = Future.value();

  static Future<void> configure(
    CueSettings settings,
    PlaybackRequest request, {
    bool update = false,
  }) {
    final turn = _last
        .catchError((Object _) {})
        .then((_) => _configure(settings, request, update: update));
    _last = turn;
    return turn;
  }

  static Future<void> _configure(
    CueSettings settings,
    PlaybackRequest request, {
    required bool update,
  }) async {
    final config = settings.nativeConfiguration(
      durationMs: request.duration,
      isTimer: request.isTimer,
    );
    for (final key in const ['startSound', 'intervalSound', 'endSound']) {
      final sound = config[key];
      if (sound is String) config[key] = await nativeBellSound(sound, bellFile);
    }
    await channel.invokeMethod<void>('configure', {
      ...config,
      'trackId': request.trackId,
      'fileId': request.fileId,
      'startPositionMs': request.startPositionMs,
      'update': update,
    });
  }

  /// Waits out the autoplay interlude. With autoplay configured it began at
  /// the session end, natively, so only the rest of it is waited for.
  static Future<void> holdInterlude(int seconds) =>
      channel.invokeMethod<void>('holdInterlude', {'seconds': seconds});

  /// No autoplay after all: the native side stops holding the interlude it
  /// began at the session end, once the end bell has rung out.
  static Future<void> endInterlude() =>
      channel.invokeMethod<void>('endInterlude');

  static Future<void> skipCountdown() =>
      channel.invokeMethod<void>('skipCountdown');
  static Future<Map<Object?, Object?>> state() async =>
      await channel.invokeMapMethod<Object?, Object?>('state') ?? const {};

  static Future<int> countdownRemainingMs() async =>
      await channel.invokeMethod<int>('countdownRemainingMs') ?? 0;
  static Future<void> stop() => channel.invokeMethod<void>('stop');
}
