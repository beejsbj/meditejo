import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

class TimerSettings {
  const TimerSettings({required this.mode, required this.minutes});

  final TimerMode mode;

  /// Countdown length. Kept while in stopwatch mode so switching back
  /// restores it.
  final int minutes;

  Duration get countdown => Duration(minutes: minutes);

  /// What a session started now would last.
  Duration get sessionDuration =>
      mode == TimerMode.stopwatch ? kStopwatchMaxDuration : countdown;

  bool get canStart => mode == TimerMode.stopwatch || minutes > 0;

  TimerSettings copyWith({TimerMode? mode, int? minutes}) =>
      TimerSettings(mode: mode ?? this.mode, minutes: minutes ?? this.minutes);
}

/// Whether the Timer is open-ended (∞ on its length wheel: the stopwatch
/// engine, counting up until ended) or counts down. Kept, like the length
/// (70% of timer sessions repeat the previous length, Sep 2026): ∞ is one
/// more place the wheel can rest, so the next visit finds it there.
final timerSettingsProvider =
    NotifierProvider.autoDispose<TimerSettingsNotifier, TimerSettings>(
      TimerSettingsNotifier.new,
    );

class TimerSettingsNotifier extends Notifier<TimerSettings> {
  static const _maxMinutes = kMaxTimerHours * 60 + 59;

  @override
  TimerSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final minutes = prefs.getInt(SharedPreferenceConstants.timerMinutes);
    final openEnded =
        prefs.getBool(SharedPreferenceConstants.timerOpenEnded) ?? false;
    return TimerSettings(
      mode: openEnded ? TimerMode.stopwatch : TimerMode.countdown,
      minutes: (minutes ?? kDefaultTimerMinutes).clamp(0, _maxMinutes),
    );
  }

  void setMode(TimerMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    ref
        .read(sharedPreferencesProvider)
        .setBool(
          SharedPreferenceConstants.timerOpenEnded,
          mode == TimerMode.stopwatch,
        );
  }

  void setMinutes(int minutes) {
    final clamped = minutes.clamp(0, _maxMinutes);
    if (clamped == state.minutes) return;
    state = state.copyWith(minutes: clamped);
    ref
        .read(sharedPreferencesProvider)
        .setInt(SharedPreferenceConstants.timerMinutes, clamped);
  }
}
