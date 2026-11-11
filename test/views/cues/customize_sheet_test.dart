import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/cues/bell_list.dart';
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
  bool openEnded = false,
  bool isActive = false,
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
            openEnded: openEnded,
            isActive: isActive,
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

Finder _tile(String card) => find.byKey(ValueKey('customize_tile_$card'));
Finder _card(String card) => find.byKey(ValueKey('customize_card_$card'));
final _sound = find.byKey(const ValueKey('customize_sound'));
final _dial = find.byKey(const ValueKey('customize_dial'));
final _infinity = find.byKey(const ValueKey('customize_infinity'));
final _back = find.byKey(const ValueKey('customize_card_back'));

/// Opens a tile's card: startBell, intervalBell, endBell or rhythm.
Future<void> _open(WidgetTester tester, String card) async {
  await tester.ensureVisible(_tile(card));
  await tester.pumpAndSettle();
  await tester.tap(_tile(card));
  await tester.pumpAndSettle();
}

/// Back, from a card to the dial and the tiles.
Future<void> _goBack(WidgetTester tester) async {
  await tester.tap(_back);
  await tester.pumpAndSettle();
}

/// What a tile says: its name, its value and, when it has one, its second
/// line.
List<String> _says(WidgetTester tester, String card) => tester
    .widgetList<Text>(
      find.descendant(of: _tile(card), matching: find.byType(Text)),
    )
    .map((t) => t.data!)
    .toList();

/// What the header's Sound button names.
String _soundSays(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _sound, matching: find.byType(Text)))
    .data!;

bool _isFilled(WidgetTester tester, Finder of) {
  final material = tester.widget<Material>(
    find.descendant(of: of, matching: find.byType(Material)).first,
  );
  return material.color != Colors.transparent;
}

/// A tile is filled (changed from the defaults) rather than outlined.
bool _filled(WidgetTester tester, String card) =>
    _isFilled(tester, _tile(card));

/// Opens the mixer drawer from the header's Sound button.
Future<void> _openSound(WidgetTester tester) async {
  await tester.tap(_sound);
  await tester.pumpAndSettle();
}

/// The scroll position of the dial-and-tiles list, or of the open card.
ScrollPosition _scroll(WidgetTester tester, {bool card = false}) => tester
    .state<ScrollableState>(
      // The list's own: the presets row inside it scrolls sideways.
      find
          .descendant(
            of: find.byKey(
              ValueKey(card ? 'customize_card_list' : 'customize_list'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

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

  testWidgets('opens on the dial and the four tiles, each with its value', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Customize'), findsOneWidget);
    expect(find.text('All practice'), findsOneWidget);
    expect(find.text('Finishes at 9:20 AM'), findsOneWidget);
    // The dial: Extend, outside any tile, with the recording's length.
    expect(
      find.descendant(of: _dial, matching: _wheel('Extend')),
      findsOneWidget,
    );
    expect(find.byType(WheelPicker<int>), findsOneWidget);
    expect(find.text('Adds silence to the session.'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('customize_total'))).data,
      '20 min',
    );
    // Under it the bells, then the ending bell and the rhythm: a 2×2 grid.
    double x(String s) => tester.getTopLeft(_tile(s)).dx;
    double y(String s) => tester.getTopLeft(_tile(s)).dy;
    expect(y('startBell'), greaterThan(tester.getRect(_dial).bottom));
    expect(y('startBell'), y('intervalBell'));
    expect(x('startBell'), lessThan(x('intervalBell')));
    expect(y('endBell'), y('rhythm'));
    expect(y('endBell'), greaterThan(y('startBell')));
    expect(x('endBell'), x('startBell'));
    expect(_says(tester, 'startBell'), ['Starting bell', 'Session bell']);
    expect(_says(tester, 'intervalBell'), ['Interval bell', 'Off']);
    expect(_says(tester, 'endBell'), ['Ending bell', 'Session bell']);
    expect(_says(tester, 'rhythm'), ['Rhythm', 'Off']);
    // At the defaults every tile is outlined, and so is the Sound button.
    for (final card in ['startBell', 'intervalBell', 'endBell', 'rhythm']) {
      expect(_filled(tester, card), isFalse, reason: card);
      expect(_card(card), findsNothing);
    }
    // Sound is the header's button, level with the title, not a tile.
    expect(_soundSays(tester), 'Off');
    expect(_isFilled(tester, _sound), isFalse);
    expect(
      tester.getRect(_sound).bottom,
      lessThan(tester.getRect(_dial).top + 1),
    );
    for (final gone in [
      'Sound',
      'Bells',
      'Length',
      'Flow',
      'Time',
      'Autoplay',
      'Countdown',
      'Pulse',
      'Stopwatch',
      'Set by the session',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await _unmount(tester);
  });

  testWidgets('a tile opens its card in place of the dial and the tiles, and '
      'Back returns to them where they were', (tester) async {
    // Short enough that the dial and the tiles scroll.
    await _pump(
      tester,
      scope: const CueScope(CueKind.talks, courseId: 'c1'),
      onStart: () {},
      size: const Size(411, 640),
    );
    final list = _scroll(tester);
    expect(list.maxScrollExtent, greaterThan(60));
    list.jumpTo(list.maxScrollExtent - 20);
    await tester.pumpAndSettle();
    final left = list.pixels;
    final tileAt = tester.getTopLeft(_tile('rhythm'));

    await tester.tap(_tile('rhythm'));
    await tester.pumpAndSettle();
    expect(_card('rhythm'), findsOneWidget);
    // Its own header: Back at the top left, then the tile's name.
    final back = tester.getRect(_back);
    final title = find.descendant(
      of: _card('rhythm'),
      matching: find.text('Rhythm'),
    );
    expect(back.left, lessThan(24));
    expect(tester.getRect(title).left, greaterThan(back.right));
    expect(tester.getRect(title).center.dy, closeTo(back.center.dy, 4));
    expect(find.widgetWithText(ChoiceChip, 'Heartbeat'), findsOneWidget);
    // The dial, the tiles and the sheet's own header are out of the way.
    expect(_tile('rhythm').hitTestable(), findsNothing);
    expect(_sound.hitTestable(), findsNothing);
    expect(find.text('Customize').hitTestable(), findsNothing);
    // Start stays.
    expect(find.text('Start').hitTestable(), findsOneWidget);

    await _goBack(tester);
    expect(_card('rhythm'), findsNothing);
    expect(_tile('rhythm').hitTestable(), findsOneWidget);
    expect(list.pixels, left, reason: 'the same scroll position');
    expect(tester.getTopLeft(_tile('rhythm')), tileAt);
    await _unmount(tester);
  });

  testWidgets('each card holds what belongs to its tile', (tester) async {
    await _pump(tester);
    Finder inCard(String card, Finder what) =>
        find.descendant(of: _card(card), matching: what);

    // The starting bell: its countdown, the bells ("Make a bell" last), and
    // the volume all bells share.
    await _open(tester, 'startBell');
    expect(inCard('startBell', find.text('Starting bell')), findsOneWidget);
    expect(inCard('startBell', _wheel('Countdown')), findsOneWidget);
    final bells = tester
        .widgetList<Text>(
          inCard(
            'startBell',
            find.descendant(
              of: find.byType(BellList),
              matching: find.byType(Text),
            ),
          ),
        )
        .map((t) => t.data)
        .toList();
    expect(bells.first, 'Off');
    expect(bells.last, 'Make a bell');
    expect(inCard('startBell', find.text('Bell volume')), findsOneWidget);
    await _goBack(tester);

    // The interval bell: how often, and the same list.
    await _open(tester, 'intervalBell');
    expect(_card('startBell'), findsNothing);
    expect(inCard('intervalBell', _wheel('Every')), findsOneWidget);
    expect(inCard('intervalBell', find.byType(BellList)), findsOneWidget);
    expect(inCard('intervalBell', find.text('Bell volume')), findsOneWidget);
    await _goBack(tester);

    // The ending bell: the silence before it, shortly captioned.
    await _open(tester, 'endBell');
    expect(inCard('endBell', _wheel('Countdown')), findsNothing);
    expect(
      inCard('endBell', _wheel('Silence after the audio')),
      findsOneWidget,
    );
    expect(find.text('Silence before the ending bell.'), findsOneWidget);
    expect(inCard('endBell', find.byType(BellList)), findsOneWidget);
    await _goBack(tester);

    await _open(tester, 'rhythm');
    expect(inCard('rhythm', find.byType(ChoiceChip)), findsWidgets);
    expect(inCard('rhythm', find.byType(BellList)), findsNothing);
    await _goBack(tester);

    // Sound is the mixer itself, in its drawer (#66): no card here.
    await _openSound(tester);
    expect(find.byType(SoundsView), findsOneWidget);
    await _closeDrawer(tester);
    expect(_tile('rhythm').hitTestable(), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('system back closes an open card before it closes the sheet', (
    tester,
  ) async {
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
      showCustomizeModal<void>(
        host,
        (_) => CustomizeSheet(
          scope: _practice,
          clock: () => DateTime(2026, 1, 1, 9, 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _open(tester, 'endBell');
    expect(_card('endBell'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_card('endBell'), findsNothing);
    expect(find.byType(CustomizeSheet), findsOneWidget, reason: 'still open');
    expect(_tile('endBell').hitTestable(), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CustomizeSheet), findsNothing);
  });

  testWidgets('every control writes the same settings as before', (
    tester,
  ) async {
    // Regression for the reshape: each wheel, list, switch and slider sets
    // exactly the field it set before it moved. Autoplay is the player's.
    final preview = _FakePreview();
    final container = await _pump(tester, preview: preview);
    const bowl = 'assets/audio/bell_bowl_deep.wav';
    const chime = 'assets/audio/bell_chime.wav';
    const gong = 'assets/audio/bell_gong.wav';

    Future<void> pick(String name) async {
      final bell = find.text(name).last;
      await tester.ensureVisible(bell);
      await tester.tap(bell);
      await tester.pumpAndSettle();
    }

    await _open(tester, 'startBell');
    await pick('Singing bowl, deep');
    await _turn(tester, 'Countdown', '10 sec');
    await _goBack(tester);

    await _open(tester, 'intervalBell');
    await _turn(tester, 'Every', '30 min');
    await _turn(tester, 'Random window', '± 20 min');
    await pick('Chime');
    await _goBack(tester);

    await _open(tester, 'endBell');
    await pick('Gong');
    await _type(tester, 'Silence after the audio', '12');
    await _drag(tester, 'Bell volume', 0.8);
    await _goBack(tester);

    await _type(tester, 'Extend', '3');

    await _open(tester, 'rhythm');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Heartbeat'));
    await tester.pumpAndSettle();
    await _turn(tester, 'Rate', '90 BPM');
    await _turn(tester, 'Slow down over', '10 min');
    await _turn(tester, 'Ends at', '30 BPM');
    await _drag(tester, 'Pulse volume', 0.6);
    await _goBack(tester);

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
            extendMinutes: 3,
            endSilenceMinutes: 12,
            hideBeforePractice: true,
          )
          .toJson(),
    );
    // Each bell was heard once, at the bell volume of the moment.
    expect(preview.played, [(bowl, 0.5), (chime, 0.5), (gong, 0.5)]);
    // The tiles say it all.
    expect(_says(tester, 'startBell'), [
      'Starting bell',
      'Singing bowl, deep',
      '10 sec countdown',
    ]);
    expect(_says(tester, 'intervalBell'), [
      'Interval bell',
      'Every 30 min ± 20',
      'Chime',
    ]);
    expect(_says(tester, 'endBell'), ['Ending bell', 'Gong', '12 min silence']);
    expect(_says(tester, 'rhythm'), [
      'Rhythm',
      'Heartbeat',
      '90',
      'over 10 min',
      '30 BPM',
    ]);
    for (final card in ['startBell', 'intervalBell', 'endBell', 'rhythm']) {
      expect(_filled(tester, card), isTrue, reason: card);
    }
    expect(_isFilled(tester, _sound), isFalse);
    // Under the dial: the recording, Extend and the ending bell's silence,
    // and what they come to.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('customize_total'))).data,
      '20 min + 3 min + 12 min = 35 min',
    );
    // 9:00, a 10 s countdown, 20 min of audio, 3 min of Extend and 12 of
    // the Ending bell's silence.
    expect(find.text('Finishes at 9:35 AM'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a tile is filled only while it differs from the defaults', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _open(tester, 'rhythm');
    await tapChip(tester, 'Soft click');
    expect(_filled(tester, 'rhythm'), isTrue);
    // Its rate kept, but off is the default again.
    await tapChip(tester, 'Off');
    expect(_read(container).pulseSound, '');
    expect(_filled(tester, 'rhythm'), isFalse);
    await _goBack(tester);

    await _open(tester, 'intervalBell');
    await _turn(tester, 'Every', '6 min');
    expect(_filled(tester, 'intervalBell'), isTrue);
    await _turn(tester, 'Every', 'Off');
    expect(_filled(tester, 'intervalBell'), isFalse);
    // The volume all bells share marks no one tile.
    await _drag(tester, 'Bell volume', 0.9);
    expect(_read(container).bellVolume, 0.9);
    for (final card in ['startBell', 'intervalBell', 'endBell']) {
      expect(_filled(tester, card), isFalse, reason: card);
    }
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
    expect(_filled(tester, 'startBell'), isTrue, reason: 'the gong is new');
    final toggle = find.widgetWithText(
      SwitchListTile,
      'Use these only for this course',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(_filled(tester, 'startBell'), isFalse, reason: 'same as its kind');
    await _open(tester, 'startBell');
    await _turn(tester, 'Countdown', '5 sec');
    expect(_filled(tester, 'startBell'), isTrue);
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
      // with a card open.
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
      await _open(tester, 'endBell');
      expect(toggle.hitTestable(), findsOneWidget);
      expect(tester.getRect(toggle).bottom, lessThanOrEqualTo(600));
      await _goBack(tester);

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

    testWidgets('is not on the timer, which always opens on this sheet', (
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
      final toggle = find.widgetWithText(
        SwitchListTile,
        'Use these only for this course',
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
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
    await _open(tester, 'intervalBell');
    expect(_wheel('Random window'), findsNothing);
    await _turn(tester, 'Every', '6 min');
    expect(_read(container).intervalMinutes, 6);
    expect(_wheel('Random window'), findsOneWidget);
    expect(_says(tester, 'intervalBell'), [
      'Interval bell',
      'Every 6 min',
      'Session bell',
    ]);
    await _turn(tester, 'Every', 'Halfway');
    expect(_read(container).intervalHalfway, isTrue);
    expect(_read(container).intervalMinutes, 6, reason: 'kept for later');
    expect(_read(container).hasIntervalBell, isTrue);
    expect(_wheel('Random window'), findsNothing, reason: 'one bell');
    expect(_says(tester, 'intervalBell'), [
      'Interval bell',
      'Halfway',
      'Session bell',
    ]);
    await _turn(tester, 'Every', '6 min');
    expect(_read(container).intervalHalfway, isFalse);
    await _turn(tester, 'Every', 'Off');
    expect(_read(container).intervalMinutes, 0);
    expect(_read(container).hasIntervalBell, isFalse);
    expect(_says(tester, 'intervalBell'), ['Interval bell', 'Off']);
    await _unmount(tester);
  });

  testWidgets(
    'the wheel turns the interval bell back on after the list said Off',
    (tester) async {
      final container = await _pump(tester);
      await _open(tester, 'intervalBell');
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            CueSettings.defaults(
              CueKind.practice,
            ).copyWith(intervalSound: '', intervalMinutes: 10),
          );
      await tester.pumpAndSettle();
      expect(_says(tester, 'intervalBell'), ['Interval bell', 'Off']);
      await _turn(tester, 'Every', 'Halfway');
      expect(_read(container).hasIntervalBell, isTrue);
      expect(_says(tester, 'intervalBell'), [
        'Interval bell',
        'Halfway',
        'Session bell',
      ]);
      await _unmount(tester);
    },
  );

  testWidgets('shrinking the interval pulls the random window in', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _open(tester, 'intervalBell');
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

  testWidgets('a bell card lists the bells; a tap previews and saves', (
    tester,
  ) async {
    final preview = _FakePreview();
    final container = await _pump(tester, preview: preview);
    await _open(tester, 'endBell');
    // Every bell is listed, the chosen one marked.
    for (final name in cueBellSounds.keys) {
      await tester.ensureVisible(find.text(name).last);
    }
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // Each bell carries its icon, drawn from its sound.
    for (final asset in cueBellSounds.values.where((a) => a.isNotEmpty)) {
      expect(find.byKey(ValueKey('bell_icon_$asset')), findsOneWidget);
    }
    final gong = find.text('Gong').last;
    await tester.ensureVisible(gong);
    await tester.tap(gong);
    await tester.pumpAndSettle();
    expect(preview.played.single, ('assets/audio/bell_gong.wav', 0.5));
    expect(_read(container).endSound, 'assets/audio/bell_gong.wav');
    // Off is silent: it stops the preview rather than playing anything.
    final before = preview.played.length;
    final off = find.descendant(
      of: find.byType(BellList),
      matching: find.text('Off'),
    );
    await tester.ensureVisible(off);
    await tester.tap(off);
    await tester.pumpAndSettle();
    expect(_read(container).endSound, '');
    expect(preview.played.length, before);
    expect(_says(tester, 'endBell'), ['Ending bell', 'Off']);
    // Leaving the card silences a bell still ringing.
    final stops = preview.stops;
    await _goBack(tester);
    expect(preview.stops, greaterThan(stops));
    await _unmount(tester);
  });

  group('the timer', () {
    bool openEnded(ProviderContainer c) =>
        c.read(timerSettingsProvider).mode == TimerMode.stopwatch;
    int selected(WidgetTester tester) => tester
        .state<WheelPickerState<dynamic>>(_wheel('Duration'))
        .selectedIndex;

    testWidgets('sets its length on the dial, typed or turned', (tester) async {
      final container = await _pump(tester, isTimer: true, onStart: () {});
      expect(find.text('Timer · all practice'), findsOneWidget);
      // The dial is there as the sheet opens, outside any tile.
      expect(
        find.descendant(of: _dial, matching: _wheel('Duration')),
        findsOneWidget,
      );
      expect(_wheel('Extend'), findsNothing);
      expect(find.text('Finishes at 9:10 AM'), findsOneWidget);
      await _type(tester, 'Duration', '95');
      expect(_read(container).durationMinutes, 95);
      expect(find.text('Finishes at 10:35 AM'), findsOneWidget);
      await _turn(tester, 'Duration', '20 min');
      expect(_read(container).durationMinutes, 20);
      // Out of range is refused, with the range.
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
      // ∞ is the wheel's first place, so 20 min is its twenty-first.
      expect(selected(tester), 20);
      expect(_read(container).durationMinutes, 20);

      // A timer's ending bell has no silence before it: its length is its
      // own.
      await _open(tester, 'endBell');
      expect(_wheel('Silence after the audio'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the ∞ button turns the wheel to ∞, and back to the length '
        'it left', (tester) async {
      final container = await _pump(tester, isTimer: true, onStart: () {});
      await _turn(tester, 'Duration', '25 min');
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      // At the dial's top right.
      final dial = tester.getRect(_dial);
      final button = tester.getRect(_infinity);
      expect(button.top, closeTo(dial.top, 1));
      expect(button.right, closeTo(dial.right, 1));
      expect(
        button.left,
        greaterThan(tester.getRect(_wheel('Duration')).right),
      );
      expect(openEnded(container), isFalse);

      await tester.tap(_infinity);
      await tester.pumpAndSettle();
      expect(openEnded(container), isTrue);
      expect(selected(tester), 0, reason: 'the wheel went there');
      expect(
        find.descendant(of: _wheel('Duration'), matching: find.text('∞')),
        findsOneWidget,
      );
      // No end to show; the length it left is kept.
      expect(find.textContaining('Finishes at'), findsNothing);
      expect(find.text('Counts up'), findsOneWidget);
      expect(_read(container).durationMinutes, 25);
      expect(tester.widget<IconButton>(_infinity).isSelected, isTrue);

      await tester.tap(_infinity);
      await tester.pumpAndSettle();
      expect(openEnded(container), isFalse);
      expect(selected(tester), 25);
      expect(find.text('Finishes at 9:25 AM'), findsOneWidget);
      expect(_read(container).durationMinutes, 25);
      // Its own way back: no Undo bar.
      expect(find.byKey(const ValueKey('customize_undo')), findsNothing);
      await _unmount(tester);
    });

    testWidgets('∞ is the wheel\'s first place, above 1 min; turning there '
        'can be undone', (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await _pump(tester, isTimer: true, onStart: () {});
      final wheel = tester.widget<WheelPicker<dynamic>>(_wheel('Duration'));
      expect(wheel.options.first.label, '∞');
      expect(wheel.options.first.semanticsLabel, 'Open-ended');
      expect(wheel.options[1].label, '1 min');
      await _turn(tester, 'Duration', '∞');
      expect(openEnded(container), isTrue);
      expect(_read(container).durationMinutes, 10, reason: 'kept');
      expect(find.text('Duration: ∞'), findsOneWidget);
      expect(find.semantics.byValue('Open-ended'), findsOne);
      await tester.tap(find.byKey(const ValueKey('customize_undo_button')));
      await tester.pumpAndSettle();
      expect(openEnded(container), isFalse);
      expect(selected(tester), 10);
      // And from ∞ to a length, back to ∞.
      await tester.tap(_infinity);
      await tester.pumpAndSettle();
      await _turn(tester, 'Duration', '3 min');
      expect(openEnded(container), isFalse);
      expect(_read(container).durationMinutes, 3);
      await tester.tap(find.byKey(const ValueKey('customize_undo_button')));
      await tester.pumpAndSettle();
      expect(openEnded(container), isTrue);
      expect(_read(container).durationMinutes, 10);
      semantics.dispose();
      await _unmount(tester);
    });

    testWidgets('the word Stopwatch is nowhere, in any language', (
      tester,
    ) async {
      for (final (locale, word) in [
        (const Locale('en'), 'Stopwatch'),
        (const Locale('de'), 'Stoppuhr'),
        (const Locale('es'), 'Cronómetro'),
      ]) {
        await _pump(
          tester,
          isTimer: true,
          onStart: () {},
          locale: locale,
          prefsValues: {'timer_open_ended': true},
        );
        await tester.pumpAndSettle();
        expect(find.text('∞'), findsOneWidget, reason: '$locale');
        expect(find.textContaining(word), findsNothing, reason: '$locale');
        await _unmount(tester);
      }
    });

    testWidgets('under way, its length is shown and not set', (tester) async {
      await _pump(
        tester,
        isTimer: true,
        isActive: true,
        audioDurationMs: 25 * 60000,
        positionMs: 5 * 60000,
      );
      expect(find.byType(WheelPicker<int>), findsNothing);
      expect(_infinity, findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('customize_length')))
            .data,
        '25 min',
      );
      expect(find.text('Finishes at 9:20 AM'), findsOneWidget);
      await _unmount(tester);

      // Open-ended: no length and no end to show.
      await _pump(
        tester,
        isTimer: true,
        isActive: true,
        openEnded: true,
        audioDurationMs: 5 * 60 * 60000,
        positionMs: 5 * 60000,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('customize_length')))
            .data,
        '∞',
      );
      expect(find.textContaining('Finishes at'), findsNothing);
      await _unmount(tester);
    });
  });

  testWidgets('typing starts from the value, not the label\'s digits', (
    tester,
  ) async {
    // "1 h 35 min" must open as 95, not 135: pressing OK unchanged keeps it.
    final container = await _pump(tester, isTimer: true, onStart: () {});
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
    await _open(tester, 'intervalBell');
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

  testWidgets('the Sound button opens the mixer drawer, which chooses for the '
      'kind', (tester) async {
    final container = await _pump(tester, size: const Size(412, 915));
    SoundscapeSessionDefault practice() => container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.practice);
    // Practice starts with nothing chosen (decision 17).
    expect(practice().enabled, isFalse);
    expect(_soundSays(tester), 'Off');
    expect(find.byKey(const ValueKey('customize_sound_art')), findsNothing);

    await _openSound(tester);
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
    expect(_soundSays(tester), '$river, Night insects');
    expect(_isFilled(tester, _sound), isTrue);
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
    await _openSound(tester);
    await _tapPreset(tester, 'starter-night');
    await _closeDrawer(tester);
    expect(
      container
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.practice)
          .selection,
      const SoundscapeSelection.preset('starter-night'),
    );
    expect(_soundSays(tester), 'Night');
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
    expect(_soundSays(tester), 'Night');

    // Opened and closed again: the choice stands.
    await _openSound(tester);
    await _closeDrawer(tester);
    expect(practice().enabled, isTrue);
    expect(
      practice().selection,
      const SoundscapeSelection.preset('starter-night'),
    );

    // Cleared: nothing plays under practice, and the kind is switched off.
    await _openSound(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_clear')));
    await tester.pumpAndSettle();
    await _closeDrawer(tester);
    expect(practice().enabled, isFalse);
    expect(_soundSays(tester), 'Off');
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

    await _openSound(tester);
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
    expect(_soundSays(tester), 'Off');

    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Changes apply to this course'), findsOneWidget);
    expect(find.text('For this course'), findsOneWidget);
    await _openSound(tester);
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
    expect(_soundSays(tester), 'Shore');
    expect(_isFilled(tester, _sound), isTrue, reason: 'its kind plays nothing');

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

    final toggle = find.widgetWithText(
      SwitchListTile,
      'Use these only for this course',
    );
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await _openSound(tester);
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
    expect(_soundSays(tester), 'Current mix');
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
      // ∞ is the wheel's first place: index N is N minutes.
      expect(landed, greaterThan(10), reason: 'the fling moved the wheel');
      expect(started, [landed], reason: 'started on the landed minutes');
      expect(_read(container).durationMinutes, landed);
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

    Future<void> setCountdown(String label) async {
      await _open(tester, 'startBell');
      await _turn(tester, 'Countdown', label);
      await _goBack(tester);
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

  testWidgets('tiles, the Sound button and a card\'s header say what they '
      'are to a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    SemanticsNode node(Finder of, String label) => tester.getSemantics(
      find.descendant(
        of: of,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
      ),
    );
    final start = node(
      _tile('startBell'),
      'Starting bell, Session bell, default',
    );
    expect(start.flagsCollection.isButton, isTrue);
    expect(find.semantics.byLabel('Interval bell, Off, default'), findsOne);
    expect(find.semantics.byLabel('Rhythm, Off, default'), findsOne);
    expect(node(_sound, 'Sound, Off').flagsCollection.isButton, isTrue);
    // The dial is one adjustable control.
    expect(find.semantics.byLabel('Extend'), findsOne);

    // A change is said as well as shown.
    await _open(tester, 'intervalBell');
    // On a card the tiles under it are not read; its header is, with Back.
    expect(find.semantics.byLabel('Rhythm, Off, default'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    final title = tester.getSemantics(
      find.descendant(
        of: _card('intervalBell'),
        matching: find.text('Interval bell'),
      ),
    );
    expect(title.flagsCollection.isHeader, isTrue);
    await _turn(tester, 'Every', 'Halfway');
    await _goBack(tester);
    expect(
      find.semantics.byLabel('Interval bell, Halfway, Session bell, changed'),
      findsOne,
    );
    await _open(tester, 'startBell');
    await _turn(tester, 'Countdown', '5 sec');
    await _goBack(tester);
    expect(
      find.semantics.byLabel(
        'Starting bell, Session bell, 5 sec countdown, changed',
      ),
      findsOne,
    );
    semantics.dispose();
    await _unmount(tester);
  });

  testWidgets('with reduced motion a card opens and closes in one step', (
    tester,
  ) async {
    final container = await _pump(tester, reduceMotion: true);
    await tester.tap(_tile('startBell'));
    await tester.pump();
    expect(_card('startBell'), findsOneWidget);
    expect(_tile('startBell').hitTestable(), findsNothing);
    expect(_wheel('Countdown').hitTestable(), findsOneWidget);
    await _turn(tester, 'Countdown', '5 sec');
    expect(_read(container).countdownSeconds, 5);
    await tester.tap(_back);
    await tester.pump();
    expect(_card('startBell'), findsNothing);
    expect(_tile('startBell').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('with motion a card comes in as the tiles go, and goes as '
      'they return', (tester) async {
    await _pump(tester);
    await tester.tap(_tile('rhythm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Both on their way: neither is fully there.
    double opacity(Finder of) => tester
        .widget<Opacity>(
          find.ancestor(of: of, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(opacity(_card('rhythm')), inExclusiveRange(0, 1));
    expect(opacity(_dial), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(opacity(_card('rhythm')), 1);
    expect(opacity(_dial), 0);
    await tester.tap(_back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(_card('rhythm'), findsOneWidget, reason: 'leaving');
    await tester.pumpAndSettle();
    expect(_card('rhythm'), findsNothing);
    expect(opacity(_dial), 1);
    await _unmount(tester);
  });

  testWidgets('the tiles speak the app\'s language', (tester) async {
    await _pump(tester, locale: const Locale('de'));
    expect(_soundSays(tester), 'Aus');
    expect(_says(tester, 'startBell').first, 'Anfangsglocke');
    expect(_says(tester, 'intervalBell'), ['Intervallglocke', 'Aus']);
    expect(_says(tester, 'endBell').first, 'Schlussglocke');
    expect(_says(tester, 'rhythm'), ['Rhythmus', 'Aus']);
    expect(find.text('Fügt der Sitzung Stille hinzu.'), findsOneWidget);
    await _unmount(tester);
    await _pump(tester, locale: const Locale('es'));
    expect(_says(tester, 'startBell').first, 'Campana inicial');
    expect(_says(tester, 'endBell').first, 'Campana final');
    expect(find.text('Añade silencio a la sesión.'), findsOneWidget);
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
    expect(_soundSays(tester), 'Aktueller Mix');
    await _unmount(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('an outlined tile and the dial\'s lines keep their text '
        'readable, ${brightness.name}', (tester) async {
      final theme = meditejoTheme(brightness, IdentityPalettes.byId(null));
      await _pump(tester, theme: theme);
      final sheet = theme.colorScheme.surfaceContainerLow;
      double ratio(Color a, Color b) {
        final (hi, lo) = a.computeLuminance() > b.computeLuminance()
            ? (a, b)
            : (b, a);
        return (hi.computeLuminance() + 0.05) / (lo.computeLuminance() + 0.05);
      }

      for (final text in [
        'Starting bell',
        'Session bell',
        'Adds silence to the session.',
        '20 min',
      ]) {
        final style = tester.widget<Text>(find.text(text).first).style!;
        expect(
          ratio(style.color!, sheet),
          greaterThanOrEqualTo(4.5),
          reason: text,
        );
      }
      await _unmount(tester);
    });
  }

  testWidgets('on the S23+ the dial and all four tiles are there at once, '
      'before a course\'s session', (tester) async {
    await _pump(
      tester,
      scope: const CueScope(CueKind.talks, courseId: 'c1'),
      onStart: () {},
      size: const Size(411, 890),
    );
    final list = tester.getRect(find.byKey(const ValueKey('customize_list')));
    expect(tester.getRect(_dial).top, greaterThanOrEqualTo(list.top));
    for (final card in ['startBell', 'intervalBell', 'endBell', 'rhythm']) {
      expect(
        tester.getRect(_tile(card)).bottom,
        lessThan(list.bottom),
        reason: card,
      );
    }
    // The dial is the tallest thing on it.
    expect(
      tester.getRect(_wheel('Extend')).height,
      greaterThan(tester.getRect(_tile('rhythm')).height),
    );
    await _unmount(tester);
  });

  for (final (size, scale) in [
    (const Size(360, 640), 1.0),
    (const Size(360, 640), 2.0),
    (const Size(411, 890), 1.0),
  ]) {
    testWidgets('fits ${size.width.round()} × ${size.height.round()} at '
        '${scale}x text', (tester) async {
      const scope = CueScope(CueKind.talks, courseId: 'c1');
      final container = await _pump(
        tester,
        scope: scope,
        onStart: () {},
        size: size,
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
      // Start stays pinned on screen while the list scrolls under it.
      expect(
        tester.getBottomLeft(find.text('Start')).dy,
        lessThanOrEqualTo(size.height),
      );
      // The dial is what the sheet opens on.
      final list = tester.getRect(find.byKey(const ValueKey('customize_list')));
      expect(tester.getRect(_wheel('Extend')).top, lessThan(list.bottom - 48));
      // The footer switch is pinned at 1x; several lines at 2x, it ends the
      // list instead, and the course switch is one line.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customize_list')),
          matching: find.byKey(_showBefore),
        ),
        scale == 1 ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Changes apply to all talks'),
        scale == 1 ? findsOneWidget : findsNothing,
      );
      // Everything can be reached.
      for (final target in [
        _wheel('Extend'),
        for (final card in ['startBell', 'intervalBell', 'endBell', 'rhythm'])
          _tile(card),
        find.byKey(const ValueKey('customize_scope_card')),
        find.byKey(_showBefore),
      ]) {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(target.hitTestable(), findsOneWidget, reason: '$target');
      }

      // The cards with the most wheels lay out too, and scroll to their
      // ends.
      await _open(tester, 'intervalBell');
      expect(_wheel('Every'), findsOneWidget);
      expect(_wheel('Random window'), findsOneWidget);
      await tester.ensureVisible(_sliderFor('Bell volume'));
      await tester.pumpAndSettle();
      expect(_sliderFor('Bell volume').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _goBack(tester);
      await _open(tester, 'endBell');
      expect(_wheel('Silence after the audio'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _goBack(tester);
      await _open(tester, 'rhythm');
      await tester.ensureVisible(_wheel('Ends at'));
      expect(_wheel('Rate'), findsOneWidget);
      await tester.ensureVisible(_sliderFor('Pulse volume'));
      await tester.pumpAndSettle();
      expect(_sliderFor('Pulse volume').hitTestable(), findsOneWidget);
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
  // change can be undone. On the Rhythm card, and on the dial.
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
      await _open(tester, 'rhythm');
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
          find.descendant(of: _card('rhythm'), matching: find.text(label)),
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
      final c = await pumpWith(tester, ramp, size: const Size(411, 420));
      await _open(tester, 'rhythm');
      final stored = _read(c).toJson();
      final list = _scroll(tester, card: true);
      expect(list.maxScrollExtent, greaterThan(100), reason: 'it scrolls');
      final section = tester.getRect(_card('rhythm'));
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
      await _open(tester, 'rhythm');
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
      await _open(tester, 'rhythm');
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
      await _open(tester, 'intervalBell');
      await _turn(tester, 'Every', 'Halfway');
      expect(_read(c).intervalHalfway, isTrue);
      expect(_read(c).intervalSound, isNotEmpty);
      expect(find.text('Every: Halfway'), findsOneWidget);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(_read(c).toJson(), before);
      await _unmount(tester);
    });

    testWidgets('the Undo bar goes by itself, and when its card is left', (
      tester,
    ) async {
      await pumpWith(tester, ramp);
      await _open(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '30 min');
      expect(find.byKey(undoBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(undoBar), findsNothing);

      await _turn(tester, 'Slow down over', '40 min');
      expect(find.byKey(undoBar), findsOneWidget);
      await _goBack(tester);
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('steps of one wheel are one change: Undo goes back to '
        'before the first', (tester) async {
      final semantics = tester.ensureSemantics();
      final c = await pumpWith(tester, ramp);
      await _open(tester, 'rhythm');
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
      await pumpWith(tester, ramp, size: const Size(411, 420));
      await _open(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '30 min');
      expect(find.byKey(undoBar), findsOneWidget);
      final list = _scroll(tester, card: true);
      list.jumpTo(list.maxScrollExtent);
      await tester.pumpAndSettle();
      final slider = find.descendant(
        of: _card('rhythm'),
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
      await _open(tester, 'intervalBell');
      // Off → 5 min also turns the bell on with the default sound.
      await _turn(tester, 'Every', '5 min');
      expect(_read(c).intervalSound, isNotEmpty);
      final bowl = find.text('Singing bowl').last;
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
        'the card is left', (tester) async {
      await pumpWith(tester, ramp, size: const Size(411, 420));
      await _open(tester, 'rhythm');
      var list = _scroll(tester, card: true);
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
      // Leaving the card gives the room back.
      await _goBack(tester);
      await _open(tester, 'rhythm');
      list = _scroll(tester, card: true);
      expect(list.maxScrollExtent, before);
      await _unmount(tester);
    });

    testWidgets('a step that lands after its card was left brings no bar', (
      tester,
    ) async {
      final c = await pumpWith(tester, ramp);
      await _open(tester, 'rhythm');
      final landing = tester
          .widget<WheelPicker<int>>(_wheel('Slow down over'))
          .onChanged;
      await _goBack(tester);
      await _open(tester, 'startBell');
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

      await _open(tester, 'startBell');

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
      await _goBack(tester);
      await flip();
      await _open(tester, 'startBell');
      expect(prefs.containsKey(courseKey), isTrue);
      final kindSaved = prefs.getString(kindKey);
      await _turn(tester, 'Countdown', '5 sec');
      expect(store.read(course).countdownSeconds, 5);
      await tester.tap(find.byKey(undoButton));
      await tester.pumpAndSettle();
      expect(store.read(course).countdownSeconds, start);
      expect(prefs.getString(kindKey), kindSaved);

      // A bar from the course's settings (the dial's, beside the switch)
      // goes when the switch is flipped: its Undo no longer has anywhere to
      // apply.
      await _goBack(tester);
      await _turn(tester, 'Extend', '+10 min');
      expect(find.byKey(undoBar), findsOneWidget);
      expect(store.read(course).extendMinutes, 10);
      await flip();
      expect(find.byKey(undoBar), findsNothing);
      expect(store.hasOverride(course), isFalse);
      expect(store.read(kind).countdownSeconds, start);
      expect(store.read(kind).extendMinutes, 0);
      // And on again: no bar was left behind to put anything back.
      await flip();
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a wheel that lands where it was offers nothing to undo', (
      tester,
    ) async {
      await pumpWith(tester, ramp);
      await _open(tester, 'rhythm');
      await _turn(tester, 'Slow down over', '20 min');
      expect(find.byKey(undoBar), findsNothing);
      await _unmount(tester);
    });

    testWidgets('the dial stands centred between gutters', (tester) async {
      final c = await _pump(tester, isTimer: true, onStart: () {});
      final wheel = tester.getRect(_wheel('Duration'));
      final section = tester.getRect(_dial);
      expect(wheel.left - section.left, greaterThanOrEqualTo(28));
      expect(section.right - wheel.right, greaterThanOrEqualTo(28));
      // The largest thing on the sheet.
      expect(wheel.height, greaterThan(tester.getRect(_tile('rhythm')).height));
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
          // Three minutes into the five after the recording.
          positionMs: 1380000,
          isActive: true,
          silenceLeftMs: 120000,
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

  group('Extend', () {
    testWidgets('is the dial of a recording, saved as before, apart from '
        'the Ending bell\'s silence', (tester) async {
      final container = await _pump(tester);
      // How it is spent is not shown: no choice between the end and the
      // pauses, and one short line of caption.
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Adds silence to the session.'), findsOneWidget);
      expect(find.textContaining('pauses'), findsNothing);
      String total() => tester
          .widget<Text>(find.byKey(const ValueKey('customize_total')))
          .data!;
      expect(total(), '20 min');
      await _turn(tester, 'Extend', '+10 min');
      expect(_read(container).extendMinutes, 10);
      expect(_read(container).endSilenceMinutes, 0);
      expect(
        container.read(cueSettingsStoreProvider).read(_practice).extendMinutes,
        10,
        reason: 'saved for the kind',
      );
      // The recording, what is added, and what the session comes to.
      expect(total(), '20 min + 10 min = 30 min');
      expect(find.text('Finishes at 9:30 AM'), findsOneWidget);
      // It can be undone like any wheel.
      expect(find.text('Extend: +10 min'), findsOneWidget);
      // The Ending bell's silence is its own setting, and untouched.
      expect(_filled(tester, 'endBell'), isFalse);
      expect(_says(tester, 'endBell'), ['Ending bell', 'Session bell']);
      await _open(tester, 'endBell');
      await _turn(tester, 'Silence after the audio', '+2 min');
      expect(_read(container).extendMinutes, 10);
      expect(_read(container).endSilenceMinutes, 2);
      await _goBack(tester);
      expect(total(), '20 min + 10 min + 2 min = 32 min');
      await _unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('both silences show, each with its own', (tester) async {
      final container = await _pump(tester);
      await container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            const CueSettings(extendMinutes: 4, endSilenceMinutes: 6),
            courseOverride: false,
          );
      await tester.pumpAndSettle();
      expect(
        tester.state<WheelPickerState<dynamic>>(_wheel('Extend')).selectedIndex,
        4,
      );
      expect(_says(tester, 'endBell'), [
        'Ending bell',
        'Session bell',
        '6 min silence',
      ]);
      await _unmount(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('in Settings, with no session, the dial stands alone', (
      tester,
    ) async {
      final container = await _pump(tester, audioDurationMs: 0);
      expect(find.byKey(const ValueKey('customize_total')), findsNothing);
      await _turn(tester, 'Extend', '+5 min');
      expect(_read(container).extendMinutes, 5);
      await _unmount(tester);
    });

    test('finish time reads the session\'s own length and position', () {
      const s = CueSettings(extendMinutes: 4, endSilenceMinutes: 6);
      final now = DateTime(2026, 1, 1, 9);
      // A 20-minute recording with 10 minutes of silence: the player reads 30.
      // At 18 minutes in, 12 remain, whatever part of them is silence.
      expect(
        customizeFinishesAt(
          now,
          s,
          isTimer: false,
          audioDurationMs: 20 * 60000,
          positionMs: 18 * 60000,
          isActive: true,
          sessionDurationMs: 30 * 60000,
        ),
        now.add(const Duration(minutes: 12)),
      );
      // At 2x the voice goes twice as fast; the silence (taken as all of it
      // ahead) does not: 2 min of voice in 1, then 10 of silence.
      expect(
        customizeFinishesAt(
          now,
          s,
          isTimer: false,
          audioDurationMs: 20 * 60000,
          positionMs: 18 * 60000,
          speed: 2,
          isActive: true,
          sessionDurationMs: 30 * 60000,
        ),
        now.add(const Duration(minutes: 11)),
      );
      // Before the player has said, the settings give the length.
      expect(
        customizeFinishesAt(
          now,
          s,
          isTimer: false,
          audioDurationMs: 20 * 60000,
          positionMs: 15 * 60000,
          isActive: true,
        ),
        now.add(const Duration(minutes: 15)),
      );
    });
  });
}
