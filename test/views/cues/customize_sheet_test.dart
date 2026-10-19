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
  Size? size,
  double textScale = 1,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

/// Drops the sheet so its 30 second refresh timer is cancelled.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

const _practice = CueScope(CueKind.practice);

/// The slider belonging to the labelled tile (the nearest enclosing column).
Finder _sliderFor(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(Slider),
);

Future<void> _drag(WidgetTester tester, String label, double value) async {
  tester.widget<Slider>(_sliderFor(label)).onChanged!(value);
  await tester.pumpAndSettle();
}

Future<void> _closeSub(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

CueSettings _read(ProviderContainer c, [CueScope scope = _practice]) =>
    c.read(cueSettingsProvider(scope));

void main() {
  test('finish time accounts for countdown, speed and extension', () {
    final s = const CueSettings().copyWith(
      countdownSeconds: 10,
      extendMinutes: 5,
    );
    final now = DateTime(2026, 1, 1, 9);
    expect(
      customizeFinishesAt(
        now,
        s,
        isTimer: false,
        audioDurationMs: 20 * 60000,
        positionMs: 0,
        speed: 0.5,
      ),
      now.add(const Duration(minutes: 45, seconds: 10)),
    );
    // Playing: countdown is already spent, only the remainder counts.
    expect(
      customizeFinishesAt(
        now,
        s,
        isTimer: false,
        audioDurationMs: 20 * 60000,
        positionMs: 10 * 60000,
      ),
      now.add(const Duration(minutes: 15)),
    );
    expect(
      customizeFinishesAt(
        now,
        s,
        isTimer: true,
        audioDurationMs: 0,
        positionMs: 0,
        timerMinutes: 12,
      ),
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
      container
          .read(cueSettingsProvider(const CueScope(CueKind.practice)))
          .countdownSeconds,
      10,
    );
    await _unmount(tester);
  });

  testWidgets('empty catalog explains itself', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Background sound'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No ambient sounds'), findsOneWidget);
    await _unmount(tester);
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
    await _unmount(tester);
  });

  testWidgets('Start button calls back', (tester) async {
    var started = false;
    await _pump(tester, onStart: () => started = true);
    await tester.tap(find.text('Start'));
    expect(started, isTrue);
    await _unmount(tester);
  });

  testWidgets('pulse sound, rate, ramp and volume are saved', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Pulse'));
    await tester.pumpAndSettle();
    // No sound yet: only the sound choice is offered.
    expect(find.text('Rate'), findsNothing);
    await tester.tap(find.text('Heartbeat'));
    await tester.pumpAndSettle();
    expect(_read(container).pulseSound, cuePulseSounds['Heartbeat']);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Ends at'), findsNothing);

    await _drag(tester, 'Rate', 90);
    await tester.pumpAndSettle();
    expect(_read(container).pulseBpm, 90);

    await _drag(tester, 'Slow down over', 10);
    await tester.pumpAndSettle();
    expect(_read(container).pulseRampMinutes, 10);
    expect(find.text('Ends at'), findsOneWidget);

    await _drag(tester, 'Ends at', 30);
    await _drag(tester, 'Volume', 0.8);
    await tester.pumpAndSettle();
    expect(_read(container).pulseEndBpm, 30);
    expect(_read(container).pulseVolume, 0.8);
    expect(find.text('Heartbeat · 90→30 BPM'), findsOneWidget);

    // Back to no ramp hides the end rate again; Off hides everything.
    await _drag(tester, 'Slow down over', 0);
    await tester.pumpAndSettle();
    expect(find.text('Ends at'), findsNothing);
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(_read(container).pulseSound, '');
    expect(find.text('Rate'), findsNothing);
    await _closeSub(tester);
    await _unmount(tester);
  });

  testWidgets('shrinking the interval pulls the random window in', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Interval bell'));
    await tester.pumpAndSettle();
    expect(find.text('Random window ±'), findsNothing);

    await _drag(tester, 'Every', 30);
    await tester.pumpAndSettle();
    await _drag(tester, 'Random window ±', 20);
    await tester.pumpAndSettle();
    expect(_read(container).randomWindowMinutes, 20);

    await _drag(tester, 'Every', 10);
    await tester.pumpAndSettle();
    expect(_read(container).intervalMinutes, 10);
    expect(_read(container).randomWindowMinutes, 10);
    expect(tester.widget<Slider>(_sliderFor('Random window ±')).max, 10);
    expect(tester.takeException(), isNull);

    await _drag(tester, 'Every', 0);
    await tester.pumpAndSettle();
    expect(_read(container).randomWindowMinutes, 0);
    expect(find.text('Random window ±'), findsNothing);
    await _closeSub(tester);
    await _unmount(tester);
  });

  testWidgets('course override saves and clears real defaults', (tester) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    const kind = CueScope(CueKind.talks);
    final container = await _pump(tester, scope: course);
    final store = container.read(cueSettingsStoreProvider);
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Use these only for this course',
    );

    Future<void> setCountdown(String label) async {
      await tester.tap(find.text('Countdown'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await _closeSub(tester);
    }

    await setCountdown('5 sec');
    expect(store.hasOverride(course), isFalse);
    expect(store.read(kind).countdownSeconds, 5);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.hasOverride(course), isTrue);

    await setCountdown('10 sec');
    expect(store.read(course).countdownSeconds, 10);
    expect(store.read(kind).countdownSeconds, 5);

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(store.hasOverride(course), isFalse);
    expect(store.read(course).countdownSeconds, 5);
    expect(_read(container, course).countdownSeconds, 5);
    await _unmount(tester);
  });

  testWidgets('hide toggle is reachable in the manual sheet and reversible', (
    tester,
  ) async {
    final container = await _pump(tester);
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Hide these settings before practice',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_read(container).hideBeforePractice, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_read(container).hideBeforePractice, isFalse);
    await _unmount(tester);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('scrolls on a narrow screen at ${scale}x text', (tester) async {
      const scope = CueScope(CueKind.talks, courseId: 'c1');
      final container = await _pump(
        tester,
        scope: scope,
        onStart: () {},
        size: const Size(280, 480),
        textScale: scale,
      );
      await container
          .read(cueSettingsProvider(scope).notifier)
          .update(
            const CueSettings().copyWith(
              pulseSound: cuePulseSounds['Soft click'],
              pulseRampMinutes: 20,
              pulseBpm: 120,
              pulseEndBpm: 20,
              intervalMinutes: 60,
              randomWindowMinutes: 60,
            ),
          );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Start stays pinned on screen while the list scrolls under it.
      expect(
        tester.getBottomLeft(find.text('Start')).dy,
        lessThanOrEqualTo(480),
      );
      final last = find.text('Use these only for this course');
      await tester.scrollUntilVisible(last, 200);
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);

      // Sub-sheets scroll too.
      await tester.ensureVisible(find.text('Pulse'));
      await tester.tap(find.text('Pulse'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Volume'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Volume'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _closeSub(tester);
      await _unmount(tester);
    });
  }
  test(
    'active finish time uses the native extension remainder and spent countdown',
    () {
      final now = DateTime(2026, 1, 1, 9);
      const settings = CueSettings(countdownSeconds: 10, extendMinutes: 5);
      expect(
        customizeFinishesAt(
          now,
          settings,
          isTimer: false,
          audioDurationMs: 1200000,
          positionMs: 1200000,
          isActive: true,
          extensionRemainingMs: 120000,
        ),
        now.add(const Duration(minutes: 2)),
      );
      expect(
        customizeFinishesAt(
          now,
          settings,
          isTimer: false,
          audioDurationMs: 1200000,
          positionMs: 0,
          isActive: true,
        ),
        now.add(const Duration(minutes: 25)),
      );
    },
  );
}
