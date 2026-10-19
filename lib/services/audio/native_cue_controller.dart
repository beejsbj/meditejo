import 'package:flutter/services.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';

/// Native clocks and preloaded audio own cue execution while Flutter sleeps.
/// This channel configures them; no Dart timer drives Android cue playback.
class NativeCueController {
  static const channel = MethodChannel('meditejo/cues');
  static Future<void> configure(
    CueSettings settings,
    PlaybackRequest request, {
    bool update = false,
  }) async {
    await channel.invokeMethod<void>('configure', {
      ...settings.nativeConfiguration(
        durationMs: request.duration,
        isTimer: request.isTimer,
      ),
      'trackId': request.trackId,
      'fileId': request.fileId,
      'startPositionMs': request.startPositionMs,
      'update': update,
    });
  }

  static Future<void> holdInterlude(int seconds) =>
      channel.invokeMethod<void>('holdInterlude', {'seconds': seconds});

  static Future<void> skipCountdown() =>
      channel.invokeMethod<void>('skipCountdown');
  static Future<Map<Object?, Object?>> state() async =>
      await channel.invokeMapMethod<Object?, Object?>('state') ?? const {};

  static Future<int> countdownRemainingMs() async =>
      await channel.invokeMethod<int>('countdownRemainingMs') ?? 0;
  static Future<void> stop() => channel.invokeMethod<void>('stop');
}
