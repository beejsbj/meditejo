import 'package:flutter/services.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pauses/pause_hold.dart';
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
    List<PauseHold> holds = const [],
  }) async {
    await channel.invokeMethod<void>('configure', {
      ...settings.nativeConfiguration(
        durationMs: request.duration,
        isTimer: request.isTimer,
        holds: holds,
      ),
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

  /// Ends the hold in the recording that is under way and carries on with the
  /// voice. False when no hold was under way.
  static Future<bool> skipHold() async =>
      await channel.invokeMethod<bool>('skipHold') ?? false;
  static Future<Map<Object?, Object?>> state() async =>
      await channel.invokeMapMethod<Object?, Object?>('state') ?? const {};

  static Future<int> countdownRemainingMs() async =>
      await channel.invokeMethod<int>('countdownRemainingMs') ?? 0;
  static Future<void> stop() => channel.invokeMethod<void>('stop');
}
