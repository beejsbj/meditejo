import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/player/repeat_mode.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/player/repeat_state_provider.dart';
import 'package:medito/services/audio/native_cue_controller.dart';
import 'package:medito/utils/logger.dart';

/// The sleep timer's choices, in minutes.
const sleepTimerMinutes = [5, 10, 15, 30];

/// The recording player's sleep timer: off, a time it pauses at, or the end
/// of the track.
class SleepTimerState {
  const SleepTimerState.off() : endsAt = null, endOfTrack = false;
  const SleepTimerState.at(DateTime this.endsAt) : endOfTrack = false;
  const SleepTimerState.endOfTrack() : endsAt = null, endOfTrack = true;

  final DateTime? endsAt;
  final bool endOfTrack;

  bool get isSet => endsAt != null || endOfTrack;

  /// What is left at [now]; null when not counting down.
  Duration? remaining(DateTime now) {
    final at = endsAt;
    if (at == null) return null;
    final left = at.difference(now);
    return left.isNegative ? Duration.zero : left;
  }
}

/// Where the pause happens. On Android the audio service keeps the time and
/// fades the voice itself, so it pauses with the screen off and Flutter
/// asleep.
abstract class SleepTimerEngine {
  Future<void> arm(Duration after);
  Future<void> cancel();

  /// Called when the Dart side's own timer runs out: an engine without a
  /// native clock pauses here.
  Future<void> expired();
}

class _NativeSleepEngine implements SleepTimerEngine {
  @override
  Future<void> arm(Duration after) => NativeCueController.sleep(after);

  @override
  Future<void> cancel() => NativeCueController.cancelSleep();

  @override
  Future<void> expired() async {}
}

/// iOS (shelved, decision 24) and desktop: the Dart timer pauses, without a
/// fade. shortcut: no fade and no native clock off Android; upgrade if iOS
/// ships.
class _DartSleepEngine implements SleepTimerEngine {
  _DartSleepEngine(this._ref);

  final Ref _ref;

  @override
  Future<void> arm(Duration after) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<void> expired() async {
    if (Platform.isIOS && iosAudioHandler.playing) {
      await iosAudioHandler.pause();
    } else if (!Platform.isIOS) {
      _ref.read(playerProvider.notifier).playPause();
    }
  }
}

final sleepTimerEngineProvider = Provider<SleepTimerEngine>(
  (ref) => Platform.isAndroid ? _NativeSleepEngine() : _DartSleepEngine(ref),
);

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
      SleepTimerNotifier.new,
    );

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _timer;

  /// The clock, for tests.
  DateTime Function() now = DateTime.now;

  @override
  SleepTimerState build() {
    ref.onDispose(() => _timer?.cancel());
    return const SleepTimerState.off();
  }

  SleepTimerEngine get _engine => ref.read(sleepTimerEngineProvider);

  /// Pauses the session [minutes] from now (the last seconds fade out).
  Future<void> setMinutes(int minutes) async {
    final after = Duration(minutes: minutes);
    _timer?.cancel();
    state = SleepTimerState.at(now().add(after));
    // The Dart timer only clears the button (and pauses where there is no
    // native clock); the service keeps the time that matters.
    _timer = Timer(after, _expired);
    await _guard(() => _engine.arm(after));
  }

  /// Plays to the end of this track, then stops: no repeat, no autoplay.
  Future<void> setEndOfTrack() async {
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState.endOfTrack();
    await _guard(_engine.cancel);
    if (ref.read(repeatStateProvider) != RepeatMode.none) {
      ref.read(repeatStateProvider.notifier).setRepeatMode(RepeatMode.none);
      ref.read(playerProvider.notifier).setRepeatMode(RepeatMode.none);
    }
  }

  Future<void> cancel() async {
    if (!state.isSet && _timer == null) return;
    final wasSet = state.isSet;
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState.off();
    if (wasSet) await _guard(_engine.cancel);
  }

  void _expired() {
    _timer = null;
    state = const SleepTimerState.off();
    unawaited(_guard(_engine.expired));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e, st) {
      AppLogger.e('PLAYER', 'Sleep timer', e, st);
    }
  }
}
