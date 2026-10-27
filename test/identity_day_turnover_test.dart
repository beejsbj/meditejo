import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/main.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/notification/reminder_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The resume handler clears the badge through reminderProvider before it
// refreshes the day. Building the real one initialises the notifications
// plugin, which has no platform in tests, so a stand-in does the badge.
class _QuietReminder implements ReminderProvider {
  @override
  Future<void> clearBadge() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// main.dart's once-a-minute day tick and its resume handler both call
// identityDayProvider.refresh(). These tests run the real ParentWidget past
// local midnight and check that the daily mark turns over, both ways.
void main() {
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 10, 27, 23, 58);
    identityClock = () => now;
  });
  tearDown(() => identityClock = DateTime.now);

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs =
        await tester.runAsync(SharedPreferences.getInstance) as SharedPreferences;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          reminderProvider.overrideWithValue(_QuietReminder()),
        ],
        child: const ParentWidget(),
      ),
    );
    // startFeedRefresh waits ten seconds before its first request; let it
    // run its delay now so no timer is left pending at teardown.
    await tester.pump(const Duration(seconds: 10));
    return tester.container();
  }

  testWidgets('the mark turns over at midnight on the minute tick', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(c.read(identityDayProvider), DateTime(2026, 10, 27));
    final before = c.read(dailyMarkProvider).seed;
    expect(before, DailyMark.forDay(DateTime(2026, 10, 27)).seed);

    // Midnight passes while the app is open; the next tick is the only
    // thing that can pick it up.
    now = DateTime(2026, 10, 28, 0, 0, 30);
    await tester.pump(const Duration(minutes: 1));

    expect(c.read(identityDayProvider), DateTime(2026, 10, 28));
    final after = c.read(dailyMarkProvider).seed;
    expect(after, DailyMark.forDay(DateTime(2026, 10, 28)).seed);
    expect(after, isNot(before));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mark turns over on resume after the app slept past midnight', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    final before = c.read(dailyMarkProvider).seed;

    // The app was in the background through midnight: no tick ran.
    now = DateTime(2026, 10, 28, 7);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(c.read(identityDayProvider), DateTime(2026, 10, 28));
    final after = c.read(dailyMarkProvider).seed;
    expect(after, DailyMark.forDay(DateTime(2026, 10, 28)).seed);
    expect(after, isNot(before));

    await tester.pumpWidget(const SizedBox());
  });
}
