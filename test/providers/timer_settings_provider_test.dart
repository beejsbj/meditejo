import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );

  test('first visit opens on a 10 minute countdown', () {
    final container = newContainer();
    addTearDown(container.dispose);
    final settings = container.read(timerSettingsProvider);
    expect(settings.mode, TimerMode.countdown);
    expect(settings.minutes, kDefaultTimerMinutes);
  });

  test('remembers the length, and ∞ like any place on its wheel', () {
    final first = newContainer();
    final sub = first.listen(timerSettingsProvider, (_, _) {});
    first.read(timerSettingsProvider.notifier)
      ..setMinutes(20)
      ..setMode(TimerMode.stopwatch);
    expect(first.read(timerSettingsProvider).mode, TimerMode.stopwatch);
    sub.close();
    first.dispose();

    final next = newContainer();
    addTearDown(next.dispose);
    final settings = next.read(timerSettingsProvider);
    expect(settings.mode, TimerMode.stopwatch);
    expect(settings.minutes, 20, reason: 'the length ∞ was turned from');
    // And back to the countdown, which is kept too.
    next.read(timerSettingsProvider.notifier).setMode(TimerMode.countdown);
    final again = newContainer();
    addTearDown(again.dispose);
    expect(again.read(timerSettingsProvider).mode, TimerMode.countdown);
  });
}
