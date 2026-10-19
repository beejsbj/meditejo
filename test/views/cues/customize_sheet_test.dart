import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CueScope scope = const CueScope(CueKind.practice),
  bool isTimer = false,
  VoidCallback? onStart,
  List<BackgroundSoundsModel> sounds = const [],
  int positionMs = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      customizeBackgroundSoundsProvider.overrideWithValue(sounds),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: CustomizeSheet(
            scope: scope,
            isTimer: isTimer,
            audioDurationMs: 20 * 60000,
            positionMs: positionMs,
            onStart: onStart,
            clock: () => DateTime(2026, 1, 1, 9, 0),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  test('finish time accounts for countdown, speed and extension', () {
    final s = const CueSettings().copyWith(
      countdownSeconds: 10,
      extendMinutes: 5,
    );
    final now = DateTime(2026, 1, 1, 9);
    expect(
      customizeFinishesAt(now, s,
          isTimer: false, audioDurationMs: 20 * 60000, positionMs: 0, speed: 0.5),
      now.add(const Duration(minutes: 45, seconds: 10)),
    );
    // Playing: countdown is already spent, only the remainder counts.
    expect(
      customizeFinishesAt(now, s,
          isTimer: false, audioDurationMs: 20 * 60000, positionMs: 10 * 60000),
      now.add(const Duration(minutes: 15)),
    );
    expect(
      customizeFinishesAt(now, s,
          isTimer: true, audioDurationMs: 0, positionMs: 0, timerMinutes: 12),
      now.add(const Duration(minutes: 12, seconds: 10)),
    );
  });

  testWidgets('rows show values and a pick persists as the kind default', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(find.text('Finishes at 9:20 AM'), findsOneWidget);
    expect(find.text('Countdown'), findsOneWidget);
    await tester.tap(find.text('Countdown'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 sec'));
    await tester.pumpAndSettle();
    expect(
      container.read(cueSettingsProvider(const CueScope(CueKind.practice))).countdownSeconds,
      10,
    );
  });

  testWidgets('empty catalog explains itself', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Background sound'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ambient sounds'), findsOneWidget);
  });

  testWidgets('course scope offers an override and the timer hides autoplay', (
    tester,
  ) async {
    await _pump(
      tester,
      scope: const CueScope(CueKind.talks, courseId: 'c1'),
      isTimer: true,
    );
    expect(find.text('Use these only for this course'), findsOneWidget);
    expect(find.text('Autoplay'), findsNothing);
  });

  testWidgets('Start button calls back', (tester) async {
    var started = false;
    await _pump(tester, onStart: () => started = true);
    await tester.tap(find.text('Start'));
    expect(started, isTrue);
  });
}
