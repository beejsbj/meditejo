import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'dart:ui' show Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/identity/palettes.dart';
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
  int audioDurationMs = 20 * 60000,
  int? timerMinutes,
  Size? size,
  double textScale = 1,
  bool reduceMotion = false,
  SessionBellPreview? preview,
  Map<String, Object> prefsValues = const {},
  Locale? locale,
  ThemeData? theme,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  SharedPreferences.setMockInitialValues(prefsValues);
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
        locale: locale,
        theme: theme,
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
            audioDurationMs: audioDurationMs,
            positionMs: positionMs,
            onStart: onStart,
            timerMinutes: timerMinutes,
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

Finder _tile(String slot) => find.byKey(ValueKey('customize_slot_$slot'));
Finder _section(String slot) => find.byKey(ValueKey('customize_section_$slot'));

/// Opens (or folds) a slot's section by its tile: sound, bells, rhythm or
/// length.
Future<void> _slot(WidgetTester tester, String slot) async {
  await tester.ensureVisible(_tile(slot));
  await tester.tap(_tile(slot));
  await tester.pumpAndSettle();
}

/// What a tile says: its name, its value and, when it has one, its second
/// line.
List<String> _says(WidgetTester tester, String slot) => tester
    .widgetList<Text>(
      find.descendant(of: _tile(slot), matching: find.byType(Text)),
    )
    .map((t) => t.data!)
    .toList();

/// A tile is filled (changed from the defaults) rather than outlined.
bool _filled(WidgetTester tester, String slot) {
  final material = tester.widget<Material>(
    find.descendant(of: _tile(slot), matching: find.byType(Material)).first,
  );
  return material.color != Colors.transparent;
}

/// Opens (or folds) a row of an open section by its title.
Future<void> _row(WidgetTester tester, String title) async {
  final row = find.text(title).first;
  await tester.ensureVisible(row);
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// The mixer drawer's library list.
Finder get _drawerLibrary => find
    .descendant(
      of: find.byKey(const PageStorageKey('sounds_library')),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls [card] into the open drawer, clear of the mix docked at its
/// foot, and taps it.
Future<void> _tapInDrawer(WidgetTester tester, Finder card) async {
  await tester.scrollUntilVisible(card, 200, scrollable: _drawerLibrary);
  await tester.pumpAndSettle();
  for (var i = 0; i < 8 && card.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(_drawerLibrary, const Offset(0, -80));
    await tester.pumpAndSettle();
  }
  await tester.tap(card.hitTestable());
  await tester.pumpAndSettle();
}

/// Taps the library card for [soundId] in the open mixer drawer.
Future<void> _tapCard(WidgetTester tester, String soundId) =>
    _tapInDrawer(tester, find.byKey(ValueKey('sound_$soundId')));

/// Taps the preset card [presetId] in the open mixer drawer.
Future<void> _tapPreset(WidgetTester tester, String presetId) async {
  final card = find.byKey(ValueKey('preset_$presetId'));
  await tester.scrollUntilVisible(
    card,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const PageStorageKey('sounds_presets')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(card);
  await tester.pumpAndSettle();
}

/// Done in the mixer drawer.
Future<void> _closeDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('sounds_chooser_done')));
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

const _showBefore = ValueKey('customize_show_before');

/// Whether the footer's "Show before each session" is on.
bool _shownBefore(WidgetTester tester) => tester
    .widget<SwitchListTile>(
      find.descendant(
        of: find.byKey(_showBefore),
        matching: find.byType(SwitchListTile),
      ),
    )
    .value;

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

  testWidgets('opens on the four slot tiles, each with its value', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('All practice'), findsOneWidget);
    expect(find.text('Finishes at 9:20 AM'), findsOneWidget);
    // Sound and Bells, then Rhythm and Length: a 2×2 grid.
    double x(String s) => tester.getTopLeft(_tile(s)).dx;
    double y(String s) => tester.getTopLeft(_tile(s)).dy;
    expect(y('sound'), y('bells'));
    expect(x('sound'), lessThan(x('bells')));
    expect(y('rhythm'), y('length'));
    expect(y('rhythm'), greaterThan(y('sound')));
    expect(x('rhythm'), x('sound'));
    expect(_says(tester, 'sound'), ['Sound', 'Off']);
    expect(_says(tester, 'bells'), ['Bells', 'Swell bell', 'Start · End']);
    expect(_says(tester, 'rhythm'), ['Rhythm', 'Off']);
    // A recording sets its own length: shown, not set.
    expect(_says(tester, 'length'), ['Length', '20 min', 'Set by the session']);
    // At the defaults every tile is outlined.
    for (final slot in ['sound', 'bells', 'rhythm', 'length']) {
      expect(_filled(tester, slot), isFalse, reason: slot);
    }
    // Folded: no section, no wheels, and none of the old sections.
    for (final slot in ['sound', 'bells', 'rhythm', 'length']) {
      expect(_section(slot), findsNothing);
    }
    expect(find.byType(WheelPicker<int>), findsNothing);
    for (final gone in ['Flow', 'Time', 'Autoplay', 'Countdown', 'Pulse']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('Extend with silence'), findsNothing);
    expect(find.text('Hide these settings before practice'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a tile opens its section, one at a time', (tester) async {
    await _pump(tester);
    await _slot(tester, 'bells');
    expect(_section('bells'), findsOneWidget);
    for (final row in [
      'Starting bell',
      'Interval bell',
      'Ending bell',
      'Bell volume',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    // The bells' own parts: the countdown with the starting bell, the
    // silence with the ending bell.
    await _row(tester, 'Starting bell');
    expect(_wheel('Countdown'), findsOneWidget);
    await _row(tester, 'Ending bell');
    expect(_wheel('Countdown'), findsNothing);
    expect(_wheel('Extra minutes'), findsOneWidget);

    await _slot(tester, 'rhythm');
    expect(_section('bells'), findsNothing);
    expect(_section('rhythm'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Heartbeat'), findsOneWidget);

    // Sound is the mixer itself, in its drawer (#66): no section here.
    await _slot(tester, 'sound');
    expect(_section('sound'), findsNothing);
    expect(find.byType(SoundsView), findsOneWidget);
    await _closeDrawer(tester);
    expect(_section('rhythm'), findsOneWidget, reason: 'rhythm stayed open');

    // A recording's Length does not open.
    await tester.tap(_tile('length'));
    await tester.pumpAndSettle();
    expect(_section('length'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('every control writes the same settings as before', (
    tester,
  ) async {
    // Regression for the regroup: each wheel, list, switch and slider sets
    // exactly the field it set before it moved. Autoplay is the player's now.
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

    await _slot(tester, 'bells');
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

    await _row(tester, 'Starting bell');
    await _turn(tester, 'Countdown', '10 sec');
    await _row(tester, 'Starting bell');
    await _row(tester, 'Ending bell');
    await _type(tester, 'Extra minutes', '12');
    await _row(tester, 'Ending bell');

    await _slot(tester, 'rhythm');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heartbeat'));
    await tester.pumpAndSettle();
    await _turn(tester, 'Rate', '90 BPM');
    await _turn(tester, 'Slow down over', '10 min');
    await _turn(tester, 'Ends at', '30 BPM');
    await _drag(tester, 'Pulse volume', 0.6);
    await _slot(tester, 'rhythm');

    await tester.tap(find.byKey(_showBefore));
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
            hideBeforePractice: true,
          )
          .toJson(),
    );
    // Each bell was heard once, at the bell volume of the moment.
    expect(preview.played, [(bowl, 0.5), (gong, 0.5), (chime, 0.5)]);
    // The tiles and the folded rows say it all.
    expect(_says(tester, 'bells'), [
      'Bells',
      'Singing bowl, deep',
      'Start · Every 30 min · End',
    ]);
    expect(_says(tester, 'rhythm'), [
      'Rhythm',
      'Heartbeat',
      '90',
      'over 10 min',
      '30 BPM',
    ]);
    expect(_says(tester, 'length'), ['Length', '20 min', '+ 12 min silence']);
    expect(_filled(tester, 'bells'), isTrue);
    expect(_filled(tester, 'rhythm'), isTrue);
    expect(_filled(tester, 'sound'), isFalse);
    await _slot(tester, 'bells');
    expect(
      _value(tester, 'Starting bell'),
      '10 sec countdown · Singing bowl, deep',
    );
    expect(_value(tester, 'Interval bell'), 'Every 30 min ± 20 · Chime');
    expect(_value(tester, 'Ending bell'), '12 min silence · Gong');
    // 9:00, a 10 s countdown, 20 min of audio and 12 min of silence.
    expect(find.text('Finishes at 9:32 AM'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a tile is filled only while it differs from the defaults', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _slot(tester, 'rhythm');
    await tapChip(tester, 'Soft click');
    expect(_filled(tester, 'rhythm'), isTrue);
    // Its rate kept, but off is the default again.
    await tapChip(tester, 'Off');
    expect(_read(container).pulseSound, '');
    expect(_filled(tester, 'rhythm'), isFalse);

    await _slot(tester, 'bells');
    await _row(tester, 'Interval bell');
    await _turn(tester, 'Every', '6 min');
    expect(_filled(tester, 'bells'), isTrue);
    await _turn(tester, 'Every', 'Off');
    expect(_filled(tester, 'bells'), isFalse);
    await _unmount(tester);
  });

  testWidgets('a course is measured against its kind, not the app', (
    tester,
  ) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    const kind = CueScope(CueKind.talks);
    final container = await _pump(tester, scope: course);
    // The talks defaults ring a gong; the course has its own copy of them.
    await container
        .read(cueSettingsProvider(kind).notifier)
        .update(
          CueSettings.defaults(
            CueKind.talks,
          ).copyWith(startSound: 'assets/audio/bell_gong.wav'),
        );
    await tester.pumpAndSettle();
    expect(_filled(tester, 'bells'), isTrue, reason: 'the gong is a change');
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Use these only for this course'),
    );
    await tester.pumpAndSettle();
    expect(_filled(tester, 'bells'), isFalse, reason: 'same as its kind');
    await _slot(tester, 'bells');
    await _row(tester, 'Starting bell');
    await _turn(tester, 'Countdown', '5 sec');
    expect(_filled(tester, 'bells'), isTrue);
    expect(_read(container, kind).countdownSeconds, 0);
    await _unmount(tester);
  });

  group('"Show before each session"', () {
    testWidgets('is a footer switch, on until switched off', (tester) async {
      final container = await _pump(tester, onStart: () {});
      final toggle = find.byKey(_showBefore);
      expect(toggle, findsOneWidget);
      expect(
        find.descendant(
          of: toggle,
          matching: find.text('Show before each session'),
        ),
        findsOneWidget,
      );
      expect(_shownBefore(tester), isTrue);
      // In the footer: under the list, just above Start, and still there
      // with a section open.
      expect(
        tester.getBottomLeft(toggle).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('Start')).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customize_list')),
          matching: toggle,
        ),
        findsNothing,
      );
      await _slot(tester, 'bells');
      await _row(tester, 'Ending bell');
      expect(tester.getRect(toggle).bottom, lessThanOrEqualTo(600));

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_read(container).hideBeforePractice, isTrue);
      expect(_read(container).showBeforeSession, isFalse);
      final stored = container.read(cueSettingsStoreProvider).read(_practice);
      expect(stored.hideBeforePractice, isTrue, reason: 'saved for the kind');
      expect(_shownBefore(tester), isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(_read(container).showBeforeSession, isTrue);
      await _unmount(tester);
    });

    testWidgets('reads a stored "hide" as off', (tester) async {
      await _pump(
        tester,
        prefsValues: {'cues.v1.practice': '{"hideBeforePractice":true}'},
      );
      expect(_shownBefore(tester), isFalse);
      await _unmount(tester);
    });

    testWidgets('is not on the timer, whose screen is this sheet', (
      tester,
    ) async {
      await _pump(tester, isTimer: true, onStart: () {});
      expect(find.byKey(_showBefore), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a course saves it with the course when overridden', (
      tester,
    ) async {
      const course = CueScope(CueKind.talks, courseId: 'c1');
      final container = await _pump(tester, scope: course);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Use these only for this course'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_showBefore));
      await tester.pumpAndSettle();
      final store = container.read(cueSettingsStoreProvider);
      expect(store.read(course).showBeforeSession, isFalse);
      expect(store.read(const CueScope(CueKind.talks)).showBeforeSession, true);
      await _unmount(tester);
    });
  });

  testWidgets('the interval can be halfway, and back to every N minutes', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _slot(tester, 'bells');
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
    expect(_says(tester, 'bells').last, 'Start · Halfway · End');
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
      await _slot(tester, 'bells');
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
    await _slot(tester, 'bells');
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
    await _slot(tester, 'bells');
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
    final off = find
        .descendant(
          of: find.byKey(const ValueKey('customize_endBell')),
          // The bell list's Off, after the silence wheel's.
          matching: find.text('Off'),
        )
        .last;
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
    expect(_says(tester, 'bells').last, 'Start');
    // Folding a bell list silences a bell still ringing; so does leaving
    // the bells for another slot.
    var stops = preview.stops;
    await _row(tester, 'Ending bell');
    expect(preview.stops, greaterThan(stops));
    stops = preview.stops;
    await _slot(tester, 'rhythm');
    expect(preview.stops, greaterThan(stops));
    await _unmount(tester);
  });

  testWidgets('the timer sets its length on the Length tile, typed or turned', (
    tester,
  ) async {
    final container = await _pump(tester, isTimer: true, onStart: () {});
    expect(find.text('Timer · all practice'), findsOneWidget);
    expect(_says(tester, 'length'), ['Length', '10 min']);
    expect(_filled(tester, 'length'), isFalse);
    await _slot(tester, 'length');
    await _type(tester, 'Duration', '95');
    expect(_read(container).durationMinutes, 95);
    expect(_says(tester, 'length'), ['Length', '1 h 35 min']);
    expect(_filled(tester, 'length'), isTrue);
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

    // A timer's ending bell has no silence before it: its length is its own.
    await _slot(tester, 'bells');
    await _row(tester, 'Ending bell');
    expect(_wheel('Extra minutes'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('a stopwatch has no length to set', (tester) async {
    await _pump(tester, isTimer: true, onStart: () {}, timerMinutes: 0);
    expect(_says(tester, 'length'), ['Length', 'Counts up']);
    await tester.tap(_tile('length'));
    await tester.pumpAndSettle();
    expect(_section('length'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('typing starts from the value, not the label\'s digits', (
    tester,
  ) async {
    // "1 h 35 min" must open as 95, not 135: pressing OK unchanged keeps it.
    final container = await _pump(tester, isTimer: true, onStart: () {});
    await _slot(tester, 'length');
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
    await _slot(tester, 'bells');
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

  testWidgets('the Sound tile opens the mixer drawer, which chooses for the '
      'kind', (tester) async {
    final container = await _pump(tester, size: const Size(412, 915));
    SoundscapeSessionDefault practice() => container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.practice);
    // Practice starts with nothing chosen (decision 17).
    expect(practice().enabled, isFalse);
    expect(_says(tester, 'sound'), ['Sound', 'Off']);
    expect(find.byKey(const ValueKey('customize_sound_art')), findsNothing);

    await _slot(tester, 'sound');
    // The mixer as a drawer, saying whose sound this is, and nothing in it.
    expect(find.byType(SoundsView), findsOneWidget);
    expect(find.text('Plays under practice'), findsOneWidget);
    expect(container.read(soundscapeProvider).mix.isEmpty, isTrue);

    // Choosing is editing the mix: two sounds layer up, and are heard.
    await _tapCard(tester, 'river');
    await _tapCard(tester, 'night-insects');
    final mixer = container.read(soundscapeProvider);
    expect(mixer.mix.layers.map((l) => l.soundId), ['river', 'night-insects']);
    expect(mixer.playing, isTrue, reason: 'auditioned as it is made');

    await _closeDrawer(tester);
    // Kept for the kind, in the mixer, not as a second copy here.
    expect(practice().enabled, isTrue);
    expect(
      practice().selection,
      SoundscapeSelection.layers(mixer.mix),
      reason: 'the layers themselves',
    );
    expect(_read(container).soundscape, '');
    final river = bundledSoundLibrary['river']!.title;
    expect(_says(tester, 'sound'), ['Sound', '$river, Night insects']);
    expect(_filled(tester, 'sound'), isTrue);
    expect(find.byKey(const ValueKey('customize_sound_art')), findsOneWidget);
    // Nothing plays on once the drawer is closed outside a session.
    expect(container.read(soundscapeProvider).playing, isFalse);
    expect(container.read(soundscapeProvider).active, isFalse);
    await _unmount(tester);
  });

  testWidgets('a preset chosen in the drawer is kept as that preset', (
    tester,
  ) async {
    final container = await _pump(tester, size: const Size(412, 915));
    await _slot(tester, 'sound');
    await _tapPreset(tester, 'starter-night');
    await _closeDrawer(tester);
    expect(
      container
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.practice)
          .selection,
      const SoundscapeSelection.preset('starter-night'),
    );
    expect(_says(tester, 'sound'), ['Sound', 'Night']);
    await _unmount(tester);
  });

  testWidgets('an emptied drawer is Off, and leaving it alone changes '
      'nothing', (tester) async {
    final container = await _pump(
      tester,
      size: const Size(412, 915),
      prefsValues: {
        'soundscape_session_defaults':
            '{"practice":{"enabled":true,"selection":"preset:starter-night",'
            '"volume":0.5}}',
        'soundscape_session_defaults_version': 2,
      },
    );
    SoundscapeSessionDefault practice() => container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.practice);
    expect(_says(tester, 'sound'), ['Sound', 'Night']);

    // Opened and closed again: the choice stands.
    await _slot(tester, 'sound');
    await _closeDrawer(tester);
    expect(practice().enabled, isTrue);
    expect(
      practice().selection,
      const SoundscapeSelection.preset('starter-night'),
    );

    // Cleared: nothing plays under practice, and the kind is switched off.
    await _slot(tester, 'sound');
    await tester.tap(find.byKey(const ValueKey('sounds_clear')));
    await tester.pumpAndSettle();
    await _closeDrawer(tester);
    expect(practice().enabled, isFalse);
    expect(_says(tester, 'sound'), ['Sound', 'Off']);
    await _unmount(tester);
  });

  testWidgets('the drawer never changes the Sounds tab\'s own mix', (
    tester,
  ) async {
    final container = await _pump(tester, size: const Size(412, 915));
    final mixer = container.read(soundscapeProvider.notifier);
    mixer.toggleSound('river');
    await tester.pumpAndSettle();
    final tabMix = container.read(soundscapeProvider).mix;
    expect(container.read(soundscapeProvider).playing, isTrue);

    await _slot(tester, 'sound');
    await _tapPreset(tester, 'starter-night');
    expect(container.read(soundscapeProvider).mix, isNot(tabMix));
    await _closeDrawer(tester);
    // Back to the mix the Sounds tab had, playing as it was.
    expect(container.read(soundscapeProvider).mix, tabMix);
    expect(container.read(soundscapeProvider).playing, isTrue);
    await _unmount(tester);
  });

  testWidgets('talks are off, and a course keeps its own choice', (
    tester,
  ) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    const kind = CueScope(CueKind.talks);
    final container = await _pump(
      tester,
      scope: course,
      size: const Size(412, 915),
    );
    final store = container.read(cueSettingsStoreProvider);
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Use these only for this course',
    );
    expect(find.text('Changes apply to all talks'), findsOneWidget);
    expect(find.text('All talks'), findsOneWidget);
    expect(_says(tester, 'sound'), ['Sound', 'Off']);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Changes apply to this course'), findsOneWidget);
    expect(find.text('For this course'), findsOneWidget);
    await _slot(tester, 'sound');
    expect(find.text('Plays under talks'), findsOneWidget);
    await _tapPreset(tester, 'starter-shore');
    await _closeDrawer(tester);
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
    expect(_says(tester, 'sound'), ['Sound', 'Shore']);
    expect(_filled(tester, 'sound'), isTrue, reason: 'its kind plays nothing');

    // Back to the kind's settings: the course inherits Off again.
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_read(container, course).soundscape, '');
    await _unmount(tester);
  });

  testWidgets('a course\'s own choice, made during an unrelated sit, '
      'leaves the sit\'s sound playing', (tester) async {
    const course = CueScope(CueKind.practice, courseId: 'c1');
    final container = await _pump(
      tester,
      scope: course,
      size: const Size(412, 915),
    );
    // A practice sit runs elsewhere, playing the kind's default.
    final mixer = container.read(soundscapeProvider.notifier);
    mixer.setSessionDefault(
      SoundscapeSessionKind.practice,
      const SoundscapeSessionDefault(enabled: true),
    );
    await mixer.startSession(SoundscapeSessionKind.practice);
    await tester.pumpAndSettle();
    final sitMix = container.read(soundscapeProvider).mix;

    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Use these only for this course'),
    );
    await tester.pumpAndSettle();
    await _slot(tester, 'sound');
    await _tapPreset(tester, 'starter-night');
    await _closeDrawer(tester);

    expect(
      container.read(cueSettingsStoreProvider).read(course).soundscape,
      'preset:starter-night',
    );
    final state = container.read(soundscapeProvider);
    expect(state.owner, SoundscapeOwner.session);
    expect(state.mix, sitMix, reason: 'the sit plays what it played');
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
    expect(_says(tester, 'sound'), ['Sound', 'Current mix']);
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
      await _slot(tester, 'length');
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
      await _slot(tester, 'length');
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

    testWidgets('a sheet dismissed while Start waits starts nothing', (
      tester,
    ) async {
      // A real route: the sheet stays mounted through its exit animation, so
      // `mounted` alone would still be true when the wheel lands.
      var started = 0;
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...soundscapeTestOverrides(FakeSoundscapeEngine()),
        ],
      );
      addTearDown(container.dispose);
      late BuildContext host;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  host = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      unawaited(
        showModalBottomSheet<void>(
          context: host,
          isScrollControlled: true,
          builder: (_) => CustomizeSheet(
            scope: _practice,
            isTimer: true,
            onStart: () => started++,
            clock: () => DateTime(2026, 1, 1, 9, 0),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _slot(tester, 'length');
      await tester.fling(
        find.byType(ListWheelScrollView),
        const Offset(0, -300),
        1200,
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('Start'));
      await tester.pump();
      Navigator.of(host).pop();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
      expect(started, 0);
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

    await _slot(tester, 'bells');
    Future<void> setCountdown(String label) async {
      await _row(tester, 'Starting bell');
      await _turn(tester, 'Countdown', label);
      await _row(tester, 'Starting bell');
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

  testWidgets('tiles and rows are buttons that say their value and state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(
      find.semantics.byLabel('Bells, Swell bell, Start · End, default'),
      findsOne,
    );
    SemanticsNode node(Finder of, String label) => tester.getSemantics(
      find.descendant(
        of: of,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
      ),
    );
    final bells = node(
      _tile('bells'),
      'Bells, Swell bell, Start · End, default',
    );
    expect(bells.flagsCollection.isExpanded, Tristate.isFalse);
    expect(bells.flagsCollection.isButton, isTrue);
    await _slot(tester, 'bells');
    expect(
      node(
        _tile('bells'),
        'Bells, Swell bell, Start · End, default',
      ).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    // A recording's Length is read, not pressed.
    expect(
      node(
        _tile('length'),
        'Length, 20 min, Set by the session',
      ).flagsCollection.isButton,
      isFalse,
    );
    // A change is said as well as shown.
    await _row(tester, 'Interval bell');
    await _turn(tester, 'Every', 'Halfway');
    expect(
      find.semantics.byLabel(
        'Bells, Swell bell, Start · Halfway · End, changed',
      ),
      findsOne,
    );
    await _row(tester, 'Interval bell');
    // The rows inside open the same way.
    expect(find.semantics.byLabel('Starting bell, Swell bell'), findsOne);
    await _row(tester, 'Starting bell');
    expect(
      node(
        find.byKey(const ValueKey('customize_startBell')),
        'Starting bell, Swell bell',
      ).flagsCollection.isExpanded,
      Tristate.isTrue,
    );
    // The play buttons are their own controls, named by their tooltip: one
    // for each bell that rings (the interval bell is on now).
    expect(find.byTooltip('Play Swell bell'), findsNWidgets(3));
    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('with reduced motion a section and a row open in one step', (
    tester,
  ) async {
    final container = await _pump(tester, reduceMotion: true);
    await _slot(tester, 'bells');
    await _row(tester, 'Starting bell');
    expect(_wheel('Countdown'), findsOneWidget);
    await _turn(tester, 'Countdown', '5 sec');
    expect(_read(container).countdownSeconds, 5);
    await _row(tester, 'Starting bell');
    expect(_wheel('Countdown'), findsNothing);
    await _slot(tester, 'bells');
    expect(_section('bells'), findsNothing);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('an opened section is brought into view under its tile', (
    tester,
  ) async {
    await _pump(
      tester,
      scope: const CueScope(CueKind.talks, courseId: 'c1'),
      onStart: () {},
      size: const Size(360, 640),
    );
    await _slot(tester, 'bells');
    await _slot(tester, 'rhythm');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heartbeat'));
    await tester.pumpAndSettle();
    // The open tile at the top of the list, its section right under it.
    final list = tester.getRect(find.byKey(const ValueKey('customize_list')));
    expect(tester.getTopLeft(_tile('rhythm')).dy, lessThan(list.top + 40));
    expect(
      tester.getTopLeft(_section('rhythm')).dy,
      lessThan(list.bottom),
      reason: 'the section starts on screen',
    );
    await _unmount(tester);
  });

  testWidgets('the tiles speak the app\'s language', (tester) async {
    await _pump(tester, locale: const Locale('de'));
    expect(_says(tester, 'sound'), ['Klang', 'Aus']);
    expect(_says(tester, 'rhythm'), ['Rhythmus', 'Aus']);
    expect(_says(tester, 'length').first, 'Dauer');
    await _unmount(tester);
  });

  testWidgets('the current mix is named in the app\'s language', (
    tester,
  ) async {
    const course = CueScope(CueKind.talks, courseId: 'c1');
    final container = await _pump(
      tester,
      scope: course,
      locale: const Locale('de'),
    );
    await container
        .read(cueSettingsProvider(course).notifier)
        .update(const CueSettings(soundscape: 'mix'), courseOverride: true);
    await tester.pumpAndSettle();
    expect(_says(tester, 'sound'), ['Klang', 'Aktueller Mix']);
    await _unmount(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('a read-only Length tile keeps its text readable, '
        '${brightness.name}', (tester) async {
      final theme = meditejoTheme(brightness, IdentityPalettes.byId(null));
      await _pump(tester, theme: theme);
      final sheet = theme.colorScheme.surfaceContainerLow;
      double ratio(Color a, Color b) {
        final (hi, lo) = a.computeLuminance() > b.computeLuminance()
            ? (a, b)
            : (b, a);
        return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
      }

      for (final text in ['Length', '20 min', 'Set by the session']) {
        final shown = find.descendant(
          of: _tile('length'),
          matching: find.text(text),
        );
        final style = tester.widget<Text>(shown).style!;
        expect(
          ratio(style.color!, sheet),
          greaterThanOrEqualTo(3),
          reason: text,
        );
      }
      // Nothing fades it: no Opacity over the tile.
      expect(
        find.ancestor(of: find.text('20 min'), matching: find.byType(Opacity)),
        findsNothing,
      );
      await _unmount(tester);
    });
  }

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
              countdownSeconds: 10,
              extendMinutes: 60,
              startSound: 'assets/audio/bell_bowl_small.wav',
            ),
          );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Start and the footer switch stay pinned on screen while the list
      // scrolls under them.
      expect(
        tester.getBottomLeft(find.text('Start')).dy,
        lessThanOrEqualTo(720),
      );
      // The course card gives the tiles room: at 2x it is one line, after
      // them.
      expect(
        find.text('Changes apply to all talks'),
        scale == 1 ? findsOneWidget : findsNothing,
      );
      final list = tester.getRect(find.byKey(const ValueKey('customize_list')));
      expect(
        tester.getTopLeft(_tile('sound')).dy,
        lessThan(list.bottom - 48),
        reason: 'the first tiles are on screen as the sheet opens',
      );
      // Pinned at 1x; several lines at 2x, it ends the list instead.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customize_list')),
          matching: find.byKey(_showBefore),
        ),
        scale == 1 ? findsNothing : findsOneWidget,
      );
      for (final slot in ['sound', 'bells', 'rhythm', 'length']) {
        await tester.ensureVisible(_tile(slot));
        expect(tester.takeException(), isNull, reason: slot);
      }

      // The open rows with the most wheels lay out too.
      await _slot(tester, 'bells');
      await _row(tester, 'Interval bell');
      expect(_wheel('Every'), findsOneWidget);
      expect(_wheel('Random window'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _row(tester, 'Ending bell');
      expect(_wheel('Extra minutes'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _slot(tester, 'rhythm');
      await tester.ensureVisible(_wheel('Ends at'));
      expect(_wheel('Rate'), findsOneWidget);
      await tester.ensureVisible(_sliderFor('Pulse volume'));
      expect(tester.takeException(), isNull);
      // Wheels sit side by side at 1x, stacked at 2x.
      // (Measured at the labels: the test font is wide enough to wrap one.)
      final rate = tester.getTopLeft(find.text('Rate'));
      final slow = tester.getTopLeft(find.text('Over'));
      if (scale == 1) {
        expect(rate.dy, slow.dy);
      } else {
        expect(slow.dy, greaterThan(rate.dy));
      }
      await _unmount(tester);
    });
  }

  // #73: Rate · over · Ends at as one row of wheels, the ramp on the tile
  // as an arrow. #91: the wheels stand between scroll gutters, and a wheel's
  // change can be undone.
  group('Rhythm wheels and scroll gutters', () {
    final ramp = CueSettings.defaults(CueKind.practice).copyWith(
      pulseSound: cuePulseSounds['Heartbeat'],
      pulseBpm: 60,
      pulseEndBpm: 40,
      pulseRampMinutes: 20,
    );
    const undoBar = ValueKey('customize_undo');
    const undoButton = ValueKey('customize_undo_button');

    Future<ProviderContainer> pumpWith(
      WidgetTester tester,
      CueSettings settings, {
      Size? size,
    }) async {
      final c = await _pump(tester, size: size);
      await c.read(cueSettingsProvider(_practice).notifier).update(settings);
      await tester.pumpAndSettle();
      return c;
    }

    WheelPicker<dynamic> picker(WidgetTester tester, String label) =>
        tester.widget<WheelPicker<dynamic>>(_wheel(label));

    testWidgets('Rate, Over and Ends at sit in one row; Ends at waits, '
        'dimmed, while the ramp is off', (tester) async {
      final c = await pumpWith(tester, ramp.copyWith(pulseRampMinutes: 0));
      await _slot(tester, 'rhythm');
      await tester.ensureVisible(_wheel('Rate'));
      await tester.pumpAndSettle();
      final rate = tester.getRect(_wheel('Rate'));
      final over = tester.getRect(_wheel('Slow down over'));
      final ends = tester.getRect(_wheel('Ends at'));
      expect(over.top, rate.top);
      expect(ends.top, rate.top);
      expect(rate.right, lessThan(over.left));
      expect(over.right, lessThan(ends.left));
      for (final label in ['Rate', 'Over', 'Ends at']) {
        expect(
          find.descendant(of: _section('rhythm'), matching: find.text(label)),
          findsOneWidget,
          reason: label,
        );
      }
      expect(picker(tester, 'Rate').enabled, isTrue);
      expect(picker(tester, 'Slow down over').enabled, isTrue);
      expect(picker(tester, 'Ends at').enabled, isFalse);
      // A drag on it scrolls past it rather than turning it.
      await tester.drag(
        _wheel('Ends at'),
        const Offset(0, -80),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(_read(c).pulseEndBpm, 40);

      await _turn(tester, 'Slow down over', '20 min');
      expect(picker(tester, 'Ends at').enabled, isTrue);
      await _turn(tester, 'Ends at', '45 BPM');
      expect(_read(c).pulseEndBpm, 45);
      await _unmount(tester);
    });

    testWidgets('the Rhythm tile reads 60 ⟶ 40 BPM, "over 20 min" set '
        'small above the arrow', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpWith(tester, ramp);
      expect(_says(tester, 'rhythm'), [
        'Rhythm',
        'Heartbeat',
        '60',
        'over 20 min',
        '40 BPM',
      ]);
      Rect at(String text) => tester.getRect(
        find.descendant(of: _tile('rhythm'), matching: find.text(text)),
      );
      final from = at('60'), over = at('over 20 min'), to = at('40 BPM');
      // Above the line, between the two rates, over the arrow.
      expect(over.center.dy, lessThan(from.top));
      expect(over.left, greaterThan(from.right));
      expect(over.right, lessThan(to.left));
      expect(to.bottom, closeTo(from.bottom, 0.5));
      final arrow = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('customize_rhythm_ramp')),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(arrow.top, greaterThanOrEqualTo(over.bottom - 0.5));
      // Set small: a smaller size than the rates either side.
      double size(String text) => DefaultTextStyle.of(
        tester.element(find.text(text)),
      ).style.merge(tester.widget<Text>(find.text(text)).style).fontSize!;
      expect(size('over 20 min'), lessThan(size('60')));
      expect(size('40 BPM'), size('60'));
      // A screen reader hears words, not an arrow.
      expect(
        find.semantics.byLabel(
          'Rhythm, Heartbeat, 60 to 40 BPM over 20 min, changed',
        ),
        findsOne,
      );
      // Without a ramp, the plain rate.
      await c
          .read(cueSettingsProvider(_practice).notifier)
          .update(_read(c).copyWith(pulseRampMinutes: 0));
      await tester.pumpAndSettle();
      expect(_says(tester, 'rhythm'), ['Rhythm', 'Heartbeat', '60 BPM']);
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('a vertical drag in a gutter scrolls the sheet and turns '
        'no wheel', (tester) async {
      final c = await pumpWith(tester, ramp, size: const Size(411, 640));
      await _slot(tester, 'rhythm');
      final stored = _read(c).toJson();
      final list = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('customize_list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(list.maxScrollExtent, greaterThan(100), reason: 'it scrolls');
      final section = tester.getRect(_section('rhythm'));
      // Inside the section's inset, 28 dp at least each side of the row.
      final firstRate = tester.getRect(_wheel('Rate'));
      final firstEnds = tester.getRect(_wheel('Ends at'));
      expect(firstRate.left - section.left, greaterThanOrEqualTo(16 + 28));
      // The spare room goes mostly right, where a right thumb scrolls.
      expect(section.right - firstEnds.right, greaterThanOrEqualTo(16 + 48));
      // The left gutter, the gaps between the wheels, the right gutter
      // (where a right thumb lands).
      for (final x in <double Function(Rect, Rect, Rect)>[
        (rate, over, ends) => (section.left + rate.left) / 2,
        (rate, over, ends) => (rate.right + over.left) / 2,
        (rate, over, ends) => (over.right + ends.left) / 2,
        (rate, over, ends) => (ends.right + section.right) / 2,
      ]) {
        await tester.ensureVisible(_wheel('Rate'));
        await tester.pumpAndSettle();
        final rate = tester.getRect(_wheel('Rate'));
        final at = Offset(
          x(
            rate,
            tester.getRect(_wheel('Slow down over')),
            tester.getRect(_wheel('Ends at')),
          ),
          rate.center.dy,
        );
        final from = list.pixels;
        final dy = from > list.minScrollExtent + 50 ? 100.0 : -100.0;
        await tester.dragFrom(at, Offset(0, dy));
        await tester.pumpAndSettle();
        expect(list.pixels, isNot(from), reason: 'the sheet scrolled at $at');
        expect(_read(c).toJson(), stored, reason: 'no wheel turned at $at');
        expect(find.byKey(undoBar), findsNothing);
      }
      await _unmount(tester);
    });

    testWidgets('a drag on a wheel turns it and offers Undo, which puts it '
        'back', (tester) async {
      final c = await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      await tester.ensureVisible(_wheel('Slow down over'));
      await tester.pumpAndSettle();
      await tester.drag(_wheel('Slow down over'), const Offset(0, -80));
      await tester.pumpAndSettle();
      final turned = _read(c).pulseRampMinutes;
      expect(turned, greaterThan(20));
      expect(_read(c).pulseBpm, 60, reason: 'only that wheel');
      expect(find.byKey(undoBar), findsOneWidget);
      expect(find.text('Slow down over: $turned min'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseRampMinutes, 20);
      expect(find.byKey(undoBar), findsNothing);
      // The wheel follows the value put back, and saving it is not a new
      // change to undo.
      expect(
        tester
            .state<WheelPickerState<dynamic>>(_wheel('Slow down over'))
            .selectedIndex,
        20,
      );
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Undo leaves alone what has changed since', (tester) async {
      final c = await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      // Another control after the wheel: its change stays.
      await _turn(tester, 'Slow down over', '30 min');
      await _drag(tester, 'Pulse volume', 0.6);
      expect(find.text('Slow down over: 30 min'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseRampMinutes, 20);
      expect(_read(c).pulseVolume, 0.6);

      // The same setting changed again elsewhere before Undo: kept.
      await _turn(tester, 'Rate', '90 BPM');
      await c
          .read(cueSettingsProvider(_practice).notifier)
          .update(_read(c).copyWith(pulseBpm: 70));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseBpm, 70);
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Undo puts back every field a wheel set', (tester) async {
      // The interval's wheel also turns the bell on and pulls the random
      // window in: Undo puts all of it back.
      final c = await pumpWith(
        tester,
        CueSettings.defaults(
          CueKind.practice,
        ).copyWith(intervalSound: '', intervalMinutes: 10),
      );
      final before = _read(c).toJson();
      await _slot(tester, 'bells');
      await _row(tester, 'Interval bell');
      await _turn(tester, 'Every', 'Halfway');
      expect(_read(c).intervalHalfway, isTrue);
      expect(_read(c).intervalSound, isNotEmpty);
      expect(find.text('Every: Halfway'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).toJson(), before);
      await _unmount(tester);
    });

    testWidgets('the Undo bar goes by itself, and when a section folds', (
      tester,
    ) async {
      await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '30 min');
      expect(find.byKey(undoBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(undoBar), findsNothing);

      await _turn(tester, 'Slow down over', '40 min');
      expect(find.byKey(undoBar), findsOneWidget);
      await _slot(tester, 'rhythm');
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('steps of one wheel are one change: Undo goes back to '
        'before the first', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      // Over 20 → 30 → 40, then Undo: 20, not 30.
      await _turn(tester, 'Slow down over', '30 min');
      await _turn(tester, 'Slow down over', '40 min');
      expect(find.text('Slow down over: 40 min'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseRampMinutes, 20);

      // A screen reader's three steps up the Rate, then Undo: 60, not 62.
      for (var i = 0; i < 3; i++) {
        tester.semantics.increase(find.semantics.byLabel('Rate'));
        await tester.pumpAndSettle();
      }
      expect(_read(c).pulseBpm, 63);
      expect(find.text('Rate: 63 BPM'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseBpm, 60);

      // Another wheel starts a change of its own.
      await _turn(tester, 'Rate', '70 BPM');
      await _turn(tester, 'Slow down over', '25 min');
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).pulseRampMinutes, 20);
      expect(_read(c).pulseBpm, 70);

      // Turned back to where it started: the bar goes.
      await _turn(tester, 'Slow down over', '30 min');
      expect(find.byKey(undoBar), findsOneWidget);
      await _turn(tester, 'Slow down over', '20 min');
      expect(find.byKey(undoBar), findsNothing);
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('with the bar up, the list scrolls what it covers clear', (
      tester,
    ) async {
      await pumpWith(tester, ramp, size: const Size(411, 640));
      await _slot(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '30 min');
      expect(find.byKey(undoBar), findsOneWidget);
      final list = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('customize_list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      list.jumpTo(list.maxScrollExtent);
      await tester.pumpAndSettle();
      final slider = find.descendant(
        of: _section('rhythm'),
        matching: find.byType(Slider),
      );
      expect(
        tester.getRect(find.byKey(undoBar)).overlaps(tester.getRect(slider)),
        isFalse,
      );
      final hit = tester.hitTestOnBinding(tester.getCenter(slider));
      final target = tester.renderObject(slider);
      expect(hit.path.any((entry) => entry.target == target), isTrue);
      await _unmount(tester);
    });

    testWidgets('a step adds only what it changed: a bell chosen between '
        'two turns of Every is kept by Undo', (tester) async {
      final c = await pumpWith(
        tester,
        CueSettings.defaults(
          CueKind.practice,
        ).copyWith(intervalSound: '', intervalMinutes: 10),
      );
      await _slot(tester, 'bells');
      await _row(tester, 'Interval bell');
      // Off → 5 min also turns the bell on with the default sound.
      await _turn(tester, 'Every', '5 min');
      expect(_read(c).intervalSound, isNotEmpty);
      final bowl = find.text('Singing bowl').first;
      await tester.ensureVisible(bowl);
      await tester.tap(bowl);
      await tester.pumpAndSettle();
      final chosen = _read(c).intervalSound;
      await _turn(tester, 'Every', '7 min');
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      // The interval goes back; the bell chosen by hand stays.
      expect(_read(c).intervalMinutes, 10);
      expect(_read(c).intervalSound, chosen);
      await _unmount(tester);
    });

    testWidgets('the room under the list stays when the bar goes, until '
        'the section folds', (tester) async {
      await pumpWith(tester, ramp, size: const Size(411, 760));
      await _slot(tester, 'rhythm');
      final list = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const ValueKey('customize_list')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final before = list.maxScrollExtent;
      await _turn(tester, 'Slow down over', '30 min');
      expect(list.maxScrollExtent, greaterThan(before));
      list.jumpTo(list.maxScrollExtent);
      await tester.pumpAndSettle();
      final top = tester.getRect(_wheel('Rate')).top;
      final pixels = list.pixels;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(undoBar), findsNothing);
      // Nothing moved under the thumb.
      expect(list.pixels, pixels);
      expect(tester.getRect(_wheel('Rate')).top, top);
      // Folding the section gives the room back.
      await _slot(tester, 'rhythm');
      await _slot(tester, 'rhythm');
      expect(list.maxScrollExtent, before);
      await _unmount(tester);
    });

    testWidgets('a step that lands after its section folded brings no bar', (
      tester,
    ) async {
      final c = await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      final landing = tester
          .widget<WheelPicker<int>>(_wheel('Slow down over'))
          .onChanged;
      await _slot(tester, 'rhythm');
      await _slot(tester, 'bells');
      landing(30);
      await tester.pumpAndSettle();
      expect(_read(c).pulseRampMinutes, 30, reason: 'still saved');
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Undo saves where the wheel saved, and flipping "only for '
        'this course" takes the bar away', (tester) async {
      const course = CueScope(CueKind.talks, courseId: 'c1');
      const kind = CueScope(CueKind.talks);
      const courseKey = 'cues.v1.talks.course.c1';
      const kindKey = 'cues.v1.talks';
      final c = await _pump(tester, scope: course);
      final prefs = c.read(sharedPreferencesProvider);
      final store = c.read(cueSettingsStoreProvider);
      final start = store.read(kind).countdownSeconds;
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Use these only for this course',
      );
      Future<void> flip() async {
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }

      await _slot(tester, 'bells');
      await _row(tester, 'Starting bell');

      // The kind's defaults: the wheel and its Undo write the kind's key.
      await _turn(tester, 'Countdown', '10 sec');
      expect(prefs.containsKey(courseKey), isFalse);
      expect(store.read(kind).countdownSeconds, 10);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(store.read(kind).countdownSeconds, start);
      expect(prefs.containsKey(courseKey), isFalse);

      // The course's own: the wheel and its Undo write the course's key,
      // and the kind's is left alone.
      await flip();
      expect(prefs.containsKey(courseKey), isTrue);
      final kindSaved = prefs.getString(kindKey);
      await _turn(tester, 'Countdown', '5 sec');
      expect(store.read(course).countdownSeconds, 5);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(store.read(course).countdownSeconds, start);
      expect(prefs.getString(kindKey), kindSaved);

      // A bar from the course's settings goes when the switch is flipped:
      // its Undo no longer has anywhere to apply.
      await _turn(tester, 'Countdown', '10 sec');
      expect(find.byKey(undoBar), findsOneWidget);
      await flip();
      expect(find.byKey(undoBar), findsNothing);
      expect(store.hasOverride(course), isFalse);
      expect(store.read(kind).countdownSeconds, start);
      // And on again: no bar was left behind to put anything back.
      await flip();
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a wheel that lands where it was offers nothing to undo', (
      tester,
    ) async {
      await pumpWith(tester, ramp);
      await _slot(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '20 min');
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the timer\'s length wheel stands centred between gutters', (
      tester,
    ) async {
      final c = await _pump(tester, isTimer: true, onStart: () {});
      await _slot(tester, 'length');
      final wheel = tester.getRect(_wheel('Duration'));
      final section = tester.getRect(_section('length'));
      expect(wheel.left - section.left, greaterThanOrEqualTo(16 + 28));
      expect(section.right - wheel.right, greaterThanOrEqualTo(16 + 28));
      expect(wheel.center.dx, closeTo(section.center.dx, 0.5));
      // A drag beside it changes nothing; on it, it turns, with Undo.
      final minutes = _read(c).durationMinutes;
      await tester.dragFrom(
        Offset((section.left + wheel.left) / 2, wheel.center.dy),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(_read(c).durationMinutes, minutes);
      await tester.ensureVisible(_wheel('Duration'));
      await tester.pumpAndSettle();
      await tester.drag(_wheel('Duration'), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(_read(c).durationMinutes, greaterThan(minutes));
      expect(find.textContaining('Duration: '), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).durationMinutes, minutes);
      await _unmount(tester);
    });
  });

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
