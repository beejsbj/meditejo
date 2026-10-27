import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// Records what the pickers audition, without touching a platform player.
class _FakePreview extends SessionBellPreview {
  final played = <(String, double)>[];
  int stops = 0;

  @override
  Future<void> play(double volume, {String asset = kSessionBellAsset}) async =>
      played.add((asset, volume));

  @override
  Future<void> stop() async => stops++;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  CueScope scope = const CueScope(CueKind.practice),
  bool isTimer = false,
  VoidCallback? onStart,
  int positionMs = 0,
  Size? size,
  double textScale = 1,
  bool reduceMotion = false,
  SessionBellPreview? preview,
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
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      if (preview != null)
        sessionBellPreviewProvider.overrideWithValue(preview),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
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

/// The slider in the row labelled [label].
Finder _sliderFor(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Row)).last,
  matching: find.byType(Slider),
);

Future<void> _drag(WidgetTester tester, String label, double value) async {
  await tester.ensureVisible(_sliderFor(label));
  tester.widget<Slider>(_sliderFor(label)).onChanged!(value);
  await tester.pumpAndSettle();
}

/// Opens (or folds) a section row by its title.
Future<void> _row(WidgetTester tester, String title) async {
  final row = find.text(title).first;
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

Finder _wheel(String label) => find.byKey(ValueKey('wheel_$label'));

/// Turns the wheel labelled [label] to the option shown as [option], the way
/// a tap, a fling or a screen reader's step ends: through the wheel's move.
Future<void> _turn(WidgetTester tester, String label, String option) async {
  await tester.ensureVisible(_wheel(label));
  final wheel = tester.widget<WheelPicker<dynamic>>(_wheel(label));
  final index = wheel.options.indexWhere((o) => o.label == option);
  expect(index, isNot(-1), reason: '$label has no "$option"');
  tester.state<WheelPickerState<dynamic>>(_wheel(label)).moveTo(index);
  await tester.pumpAndSettle();
}

/// Types [text] into the wheel labelled [label] (tap the centred value).
Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_wheel(label));
  final state = tester.state<WheelPickerState<dynamic>>(_wheel(label));
  final shown = tester
      .widget<WheelPicker<dynamic>>(_wheel(label))
      .options[state.selectedIndex]
      .label;
  await tester.tap(
    find.descendant(of: _wheel(label), matching: find.text(shown)),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('wheel_picker_entry')),
    text,
  );
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

/// The value line of the row titled [title].
String _value(WidgetTester tester, String title) {
  final texts = tester
      .widgetList<Text>(
        find.descendant(
          of: find
              .ancestor(
                of: find.text(title).first,
                matching: find.byType(Column),
              )
              .first,
          matching: find.byType(Text),
        ),
      )
      .map((t) => t.data)
      .toList();
  return texts[texts.indexOf(title) + 1]!;
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

  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(ChoiceChip, label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('sections show every value at a glance, with the finish time', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('All practice'), findsOneWidget);
    expect(find.text('Finishes at 9:20 AM'), findsOneWidget);
    for (final section in ['Bells', 'Rhythm', 'Time', 'Sound', 'Flow']) {
      await tester.scrollUntilVisible(
        find.text(section),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(section), findsOneWidget);
    }
    // The brief's order for a session: Bells, Rhythm, Time, Sound, Flow.
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(y('Bells'), lessThan(y('Rhythm')));
    expect(_value(tester, 'Starting bell'), 'Swell bell');
    expect(_value(tester, 'Interval bell'), 'Off');
    expect(_value(tester, 'Ending bell'), 'Swell bell');
    expect(_value(tester, 'Pulse'), 'Off');
    expect(_value(tester, 'Countdown'), 'Off');
    expect(_value(tester, 'Extend with silence'), 'Off');
    expect(_value(tester, 'Background sound'), 'Off');
    expect(_value(tester, 'Autoplay'), 'Off');
    // Folded: no wheels until a row opens, and one row at a time.
    expect(find.byType(WheelPicker<int>), findsNothing);
    await _row(tester, 'Countdown');
    expect(_wheel('Countdown'), findsOneWidget);
    await _row(tester, 'Extend with silence');
    expect(_wheel('Countdown'), findsNothing);
    expect(_wheel('Extra minutes'), findsOneWidget);
    await _row(tester, 'Extend with silence');
    expect(_wheel('Extra minutes'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('every control writes the same settings as before', (
    tester,
  ) async {
    // Regression for the redesign: each wheel, list, switch and slider sets
    // exactly the field its old slider, chip or sub-sheet set.
    final preview = _FakePreview();
    final container = await _pump(tester, preview: preview);
    const bowl = 'assets/audio/bell_bowl_deep.wav';
    const chime = 'assets/audio/bell_chime.wav';
    const gong = 'assets/audio/bell_gong.wav';

    Future<void> bell(String row, String name) async {
      await _row(tester, row);
      final pick = find.text(name).last;
      await tester.ensureVisible(pick);
      await tester.tap(pick);
      await tester.pumpAndSettle();
      await _row(tester, row);
    }

    await bell('Starting bell', 'Singing bowl, deep');
    await bell('Ending bell', 'Gong');

    await _row(tester, 'Interval bell');
    await _turn(tester, 'Every', '30 min');
    await _turn(tester, 'Random window', '± 20 min');
    final pick = find.text('Chime').last;
    await tester.ensureVisible(pick);
    await tester.tap(pick);
    await tester.pumpAndSettle();
    await _row(tester, 'Interval bell');
    await _drag(tester, 'Bell volume', 0.8);

    await _row(tester, 'Pulse');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heartbeat'));
    await tester.pumpAndSettle();
    await _turn(tester, 'Rate', '90 BPM');
    await _turn(tester, 'Slow down over', '10 min');
    await _turn(tester, 'Ends at', '30 BPM');
    await _drag(tester, 'Pulse volume', 0.6);
    await _row(tester, 'Pulse');

    await _row(tester, 'Countdown');
    await _turn(tester, 'Countdown', '10 sec');
    await _row(tester, 'Countdown');
    await _row(tester, 'Extend with silence');
    await _type(tester, 'Extra minutes', '12');
    await _row(tester, 'Extend with silence');

    await _row(tester, 'Autoplay');
    await tester.tap(find.text('Play the next session automatically'));
    await tester.pumpAndSettle();
    await _turn(tester, 'Interlude before the next session', '30 sec');
    await _row(tester, 'Autoplay');
    final hide = find.text('Hide these settings before practice');
    await tester.ensureVisible(hide);
    await tester.tap(hide);
    await tester.pumpAndSettle();

    expect(
      _read(container).toJson(),
      CueSettings.defaults(CueKind.practice)
          .copyWith(
            startSound: bowl,
            endSound: gong,
            intervalSound: chime,
            intervalMinutes: 30,
            randomWindowMinutes: 20,
            bellVolume: 0.8,
            pulseSound: cuePulseSounds['Heartbeat'],
            pulseBpm: 90,
            pulseRampMinutes: 10,
            pulseEndBpm: 30,
            pulseVolume: 0.6,
            countdownSeconds: 10,
            extendMinutes: 12,
            autoplay: true,
            interludeSeconds: 30,
            hideBeforePractice: true,
          )
          .toJson(),
    );
    // Each bell was heard once, at the bell volume of the moment.
    expect(preview.played, [(bowl, 0.5), (gong, 0.5), (chime, 0.5)]);
    // The folded rows say it all.
    expect(_value(tester, 'Interval bell'), 'Every 30 min ± 20 · Chime');
    expect(_value(tester, 'Pulse'), 'Heartbeat · 90→30 BPM');
    expect(_value(tester, 'Extend with silence'), '+12 min');
    expect(_value(tester, 'Autoplay'), 'On · 30 sec pause');
    // 9:00, a 10 s countdown, 20 min of audio and 12 min of silence.
    expect(find.text('Finishes at 9:32 AM'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the interval can be halfway, and back to every N minutes', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _row(tester, 'Interval bell');
    expect(_wheel('Random window'), findsNothing);
    await _turn(tester, 'Every', '6 min');
    expect(_read(container).intervalMinutes, 6);
    expect(_wheel('Random window'), findsOneWidget);
    await _turn(tester, 'Every', 'Halfway');
    expect(_read(container).intervalHalfway, isTrue);
    expect(_read(container).intervalMinutes, 6, reason: 'kept for later');
    expect(_read(container).hasIntervalBell, isTrue);
    expect(_wheel('Random window'), findsNothing, reason: 'one bell');
    expect(_value(tester, 'Interval bell'), 'Halfway · Swell bell');
    await _turn(tester, 'Every', '6 min');
    expect(_read(container).intervalHalfway, isFalse);
    await _turn(tester, 'Every', 'Off');
    expect(_read(container).intervalMinutes, 0);
    expect(_read(container).hasIntervalBell, isFalse);
    expect(_value(tester, 'Interval bell'), 'Off');
    await _unmount(tester);
  });

  testWidgets(
    'the wheel turns the interval bell back on after the list said Off',
    (tester) async {
      final container = await _pump(tester);
      await _row(tester, 'Interval bell');
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            CueSettings.defaults(
              CueKind.practice,
            ).copyWith(intervalSound: '', intervalMinutes: 10),
          );
      await tester.pumpAndSettle();
      expect(_value(tester, 'Interval bell'), 'Off');
      await _turn(tester, 'Every', 'Halfway');
      expect(_read(container).hasIntervalBell, isTrue);
      expect(_value(tester, 'Interval bell'), 'Halfway · Swell bell');
      await _unmount(tester);
    },
  );

  testWidgets('shrinking the interval pulls the random window in', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _row(tester, 'Interval bell');
    await _turn(tester, 'Every', '30 min');
    await _turn(tester, 'Random window', '± 20 min');
    expect(_read(container).randomWindowMinutes, 20);
    await _type(tester, 'Every', '10');
    expect(_read(container).intervalMinutes, 10);
    expect(_read(container).randomWindowMinutes, 10);
    final window = tester.widget<WheelPicker<dynamic>>(_wheel('Random window'));
    expect(window.options.last.label, '± 10 min');
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('a bell row plays its bell; the list previews and saves', (
    tester,
  ) async {
    final preview = _FakePreview();
    final container = await _pump(tester, preview: preview);
    // Folded, the row has its own play button.
    await tester.tap(find.byKey(const ValueKey('customize_play_startBell')));
    await tester.pumpAndSettle();
    expect(preview.played.single, (kSessionBellAsset, 0.5));
    expect(_read(container).startSound, kSessionBellAsset, reason: 'unchanged');

    // Every bell is listed, the chosen one marked.
    await _row(tester, 'Ending bell');
    for (final name in cueBellSounds.keys) {
      await tester.ensureVisible(find.text(name).last);
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Each bell carries its icon, drawn from its sound.
    for (final asset in cueBellSounds.values.where((a) => a.isNotEmpty)) {
      expect(find.byKey(ValueKey('bell_icon_$asset')), findsOneWidget);
    }
    // Off is silent: it stops the preview rather than playing anything.
    final before = preview.played.length;
    final off = find.descendant(
      of: find.byKey(const ValueKey('customize_endBell')),
      matching: find.text('Off'),
    );
    await tester.ensureVisible(off);
    await tester.tap(off);
    await tester.pumpAndSettle();
    expect(_read(container).endSound, '');
    expect(preview.played.length, before);
    expect(
      find.byKey(const ValueKey('customize_play_endBell')),
      findsNothing,
      reason: 'nothing to play',
    );
    // Folding the list silences a bell still ringing.
    final stops = preview.stops;
    await _row(tester, 'Ending bell');
    expect(preview.stops, greaterThan(stops));
    await _unmount(tester);
  });

  testWidgets('the timer leads with its duration, typed or turned', (
    tester,
  ) async {
    final container = await _pump(tester, isTimer: true, onStart: () {});
    expect(find.text('Timer · all practice'), findsOneWidget);
    expect(find.text('Autoplay'), findsNothing);
    expect(find.text('Extend with silence'), findsNothing);
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(y('Time'), lessThan(y('Bells')));
    expect(_value(tester, 'Duration'), '10 min');
    await _row(tester, 'Duration');
    await _type(tester, 'Duration', '95');
    expect(_read(container).durationMinutes, 95);
    expect(_value(tester, 'Duration'), '1 h 35 min');
    expect(find.text('Finishes at 10:35 AM'), findsOneWidget);
    await _turn(tester, 'Duration', '20 min');
    expect(_read(container).durationMinutes, 20);
    // Out of range is refused, with the range.
    final wheel = tester.state<WheelPickerState<dynamic>>(_wheel('Duration'));
    await tester.tap(
      find.descendant(of: _wheel('Duration'), matching: find.text('20 min')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wheel_picker_entry')),
      '300',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('1 to 299 minutes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(wheel.selectedIndex, 19);
    expect(_read(container).durationMinutes, 20);
    await _unmount(tester);
  });

  testWidgets('typing starts from the value, not the label\'s digits', (
    tester,
  ) async {
    // "1 h 35 min" must open as 95, not 135: pressing OK unchanged keeps it.
    final container = await _pump(tester, isTimer: true, onStart: () {});
    await _row(tester, 'Duration');
    await _type(tester, 'Duration', '95');
    await tester.tap(
      find.descendant(
        of: _wheel('Duration'),
        matching: find.text('1 h 35 min'),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('wheel_picker_entry'));
    expect(tester.widget<TextField>(field).controller!.text, '95');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(_read(container).durationMinutes, 95);

    // Halfway has no number to start from.
    await _row(tester, 'Interval bell');
    await _turn(tester, 'Every', 'Halfway');
    await tester.tap(
      find.descendant(of: _wheel('Every'), matching: find.text('Halfway')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, '');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_read(container).intervalHalfway, isTrue);
    await _unmount(tester);
  });

  testWidgets('background sound chooses from the library for the kind', (
    tester,
  ) async {
    final container = await _pump(tester);
    SoundscapeSessionDefault practice() => container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.practice);
    // Practice starts with nothing chosen (decision 17).
    expect(practice().enabled, isFalse);
    await _row(tester, 'Background sound');
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Off'))
          .selected,
      isTrue,
    );
    expect(find.text('Volume'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'Rain on the forest'), findsOne);
    expect(find.text('Rain'), findsOneWidget);
    final river = bundledSoundLibrary['river']!;
    expect(find.widgetWithText(ChoiceChip, river.title), findsOneWidget);

    // A kind-wide pick is the mixer's default, not a second copy.
    await tapChip(tester, 'Night');
    expect(practice().enabled, isTrue);
    expect(
      practice().selection,
      const SoundscapeSelection.preset('starter-night'),
    );
    expect(_read(container).soundscape, '');
    await tapChip(tester, river.title);
    expect(practice().selection, const SoundscapeSelection.sound('river'));
    expect(_value(tester, 'Background sound'), river.title);

    // The volume is the mixer's level for the kind.
    await _drag(tester, 'Volume', 0.8);
    expect(practice().volume, closeTo(0.8, 1e-9));

    await tapChip(tester, 'Off');
    expect(practice().enabled, isFalse);
    expect(find.text('Volume'), findsNothing);
    expect(_value(tester, 'Background sound'), 'Off');
    await _unmount(tester);
  });

  testWidgets('background sound opens the Sounds screen to edit the mix', (
    tester,
  ) async {
    await _pump(tester);
    await _row(tester, 'Background sound');
    final edit = find.byKey(const ValueKey('customize_open_sounds'));
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    // Full height, over the sheet, not another drawer.
    expect(find.byType(SoundsView), findsOneWidget);
    expect(tester.widget<SoundsView>(find.byType(SoundsView)).standalone, true);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(SoundsView), findsNothing);
    expect(edit, findsOneWidget, reason: 'back to the choice');
    await _unmount(tester);
  });

  testWidgets('talks are off, and a course keeps its own choice', (
    tester,
  ) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    const kind = CueScope(CueKind.talks);
    final container = await _pump(tester, scope: course);
    final store = container.read(cueSettingsStoreProvider);
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Use these only for this course',
    );
    expect(find.text('Changes apply to all talks'), findsOneWidget);
    expect(find.text('All talks'), findsOneWidget);
    expect(_value(tester, 'Background sound'), 'Off');

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Changes apply to this course'), findsOneWidget);
    expect(find.text('For this course'), findsOneWidget);
    await _row(tester, 'Background sound');
    await tapChip(tester, 'Shore');
    expect(store.read(course).soundscape, 'preset:starter-shore');
    expect(store.read(kind).soundscape, '');
    expect(
      container
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.talks)
          .enabled,
      isFalse,
      reason: 'the talks default is untouched',
    );
    expect(_value(tester, 'Background sound'), 'Shore');

    // Back to the kind's settings: the course inherits Off again.
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_read(container, course).soundscape, '');
    await _unmount(tester);
  });

  testWidgets('a playlist says playlist', (tester) async {
    await _pump(
      tester,
      scope: const CueScope(CueKind.practice, courseId: 'my-course-abc'),
    );
    expect(find.text('Use these only for this playlist'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a deleted preset shows as the current mix it plays', (
    tester,
  ) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    final container = await _pump(tester, scope: course);
    await container
        .read(cueSettingsProvider(course).notifier)
        .update(
          const CueSettings(soundscape: 'preset:user-deleted'),
          courseOverride: true,
        );
    await tester.pumpAndSettle();
    expect(_value(tester, 'Background sound'), 'Current mix');
    await _unmount(tester);
  });

  group('Start during a wheel fling', () {
    // The Timer's Duration wheel, flung toward longer: it is still turning
    // when Start is tapped.
    Future<ProviderContainer> flung(
      WidgetTester tester,
      void Function(int minutes) onStart,
    ) async {
      late ProviderContainer container;
      container = await _pump(
        tester,
        isTimer: true,
        onStart: () => onStart(_read(container).durationMinutes),
      );
      await _row(tester, 'Duration');
      await tester.fling(
        find.byType(ListWheelScrollView),
        const Offset(0, -300),
        1200,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(_read(container).durationMinutes, 10, reason: 'still turning');
      return container;
    }

    testWidgets('waits for the wheel to land and starts with that value', (
      tester,
    ) async {
      final started = <int>[];
      final container = await flung(tester, started.add);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(started, isEmpty, reason: 'the wheel has not landed yet');
      await tester.pumpAndSettle();
      final landed = tester
          .state<WheelPickerState<dynamic>>(_wheel('Duration'))
          .selectedIndex;
      expect(landed, greaterThan(9), reason: 'the fling moved the wheel');
      expect(started, [landed + 1], reason: 'started on the landed minutes');
      expect(_read(container).durationMinutes, landed + 1);
      await _unmount(tester);
    });

    testWidgets('a second tap while waiting does not start twice', (
      tester,
    ) async {
      final started = <int>[];
      await flung(tester, started.add);
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(started, hasLength(1));
      await _unmount(tester);
    });

    testWidgets('a wheel held by a finger does not hold Start for ever', (
      tester,
    ) async {
      final started = <int>[];
      await _pump(tester, isTimer: true, onStart: () => started.add(1));
      await _row(tester, 'Duration');
      final hold = await tester.startGesture(
        tester.getCenter(find.byType(ListWheelScrollView)),
      );
      await hold.moveBy(const Offset(0, -30));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump(const Duration(seconds: 1));
      expect(started, isEmpty);
      await tester.pump(WheelSettleGroup.patience);
      expect(started, hasLength(1));
      await hold.up();
      await tester.pumpAndSettle();
      await _unmount(tester);
    });

    testWidgets('leaving the sheet while waiting starts nothing', (
      tester,
    ) async {
      final started = <int>[];
      await flung(tester, started.add);
      await tester.tap(find.text('Start'));
      await tester.pump();
      await _unmount(tester);
      await tester.pumpAndSettle();
      expect(started, isEmpty);
    });
  });

  testWidgets('Start button calls back', (tester) async {
    var started = false;
    await _pump(tester, onStart: () => started = true);
    await tester.tap(find.text('Start'));
    expect(started, isTrue);
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
      await _row(tester, 'Countdown');
      await _turn(tester, 'Countdown', label);
      await _row(tester, 'Countdown');
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

  testWidgets('rows are buttons that say their value and whether open', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('customize_countdown'))),
      isNotNull,
    );
    expect(find.semantics.byLabel('Countdown, Off'), findsOne);
    await _row(tester, 'Countdown');
    final node = tester.getSemantics(
      find.descendant(
        of: find.byKey(const ValueKey('customize_countdown')),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Countdown, Off',
        ),
      ),
    );
    expect(node.flagsCollection.isExpanded, Tristate.isTrue);
    // The play buttons are their own controls, named by their tooltip.
    expect(find.byTooltip('Play Swell bell'), findsNWidgets(2));
    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('with reduced motion a row opens in one step', (tester) async {
    final container = await _pump(tester, reduceMotion: true);
    await _row(tester, 'Countdown');
    expect(_wheel('Countdown'), findsOneWidget);
    await _turn(tester, 'Countdown', '5 sec');
    expect(_read(container).countdownSeconds, 5);
    await _row(tester, 'Countdown');
    expect(_wheel('Countdown'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits a 360 dp phone at ${scale}x text', (tester) async {
      const scope = CueScope(CueKind.talks, courseId: 'c1');
      final container = await _pump(
        tester,
        scope: scope,
        onStart: () {},
        size: const Size(360, 720),
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
        lessThanOrEqualTo(720),
      );
      final last = find.text('Hide these settings before practice');
      await tester.scrollUntilVisible(
        last,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(last, findsOneWidget);
      expect(tester.takeException(), isNull);

      // The open rows with the most wheels lay out too.
      await _row(tester, 'Interval bell');
      expect(_wheel('Every'), findsOneWidget);
      expect(_wheel('Random window'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _row(tester, 'Pulse');
      await tester.ensureVisible(_wheel('Ends at'));
      expect(_wheel('Rate'), findsOneWidget);
      await tester.ensureVisible(_sliderFor('Pulse volume'));
      expect(tester.takeException(), isNull);
      // Wheels sit side by side at 1x, stacked at 2x.
      // (Measured at the labels: the test font is wide enough to wrap one.)
      final rate = tester.getTopLeft(find.text('Rate'));
      final slow = tester.getTopLeft(find.text('Slow down over'));
      if (scale == 1) {
        expect(rate.dy, slow.dy);
      } else {
        expect(slow.dy, greaterThan(rate.dy));
      }
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
