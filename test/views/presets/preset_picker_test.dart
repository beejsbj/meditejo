import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/presets/preset_labels.dart';
import 'package:medito/views/presets/save_preset_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _gong = 'assets/audio/bell_gong.wav';
const _river = SoundMix([SoundLayer(soundId: 'river', volume: 0.6)]);
const _practice = CueScope(CueKind.practice);
const _talks = CueScope(CueKind.talks);

Finder _entry(String id) => find.byKey(ValueKey('preset_entry_$id'));
Finder _menu(String id) => find.byKey(ValueKey('preset_menu_$id'));
final _row = find.byKey(const ValueKey('customize_presets'));
final _list = find.byKey(const ValueKey('preset_picker'));
final _loaded = find.byKey(const ValueKey('preset_loaded'));

/// Opens the list of presets from Customize's row.
Future<void> _openList(WidgetTester tester) async {
  // Under the tiles: on a small phone it is scrolled to.
  await tester.ensureVisible(_row);
  await tester.pumpAndSettle();
  await tester.tap(_row);
  await tester.pumpAndSettle();
}

/// Picks a preset from the list, which closes.
Future<void> _pick(WidgetTester tester, String id) async {
  await _openList(tester);
  await tester.scrollUntilVisible(
    _entry(id),
    120,
    scrollable: find.descendant(of: _list, matching: find.byType(Scrollable)),
  );
  await tester.tap(_entry(id));
  await tester.pumpAndSettle();
  expect(_list, findsNothing);
}

final _saveButton = find.byKey(const ValueKey('customize_preset_save'));

/// The words of the line that names the loaded preset.
String _line(WidgetTester tester) => tester.widget<Text>(_loaded).data!;

/// What an entry says it sets, with the muted parts marked.
List<(String, bool muted)> _parts(WidgetTester tester, String id) {
  final rich = tester.widget<RichText>(
    find.descendant(
      of: find.descendant(of: _entry(id), matching: find.byType(PresetSummary)),
      matching: find.byType(RichText),
    ),
  );
  final base = rich.text.style?.color;
  final parts = <(String, bool)>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null && span.text != ' · ') {
      final color = span.style?.color;
      parts.add((span.text!, color != null && color != base));
    }
    return true;
  });
  return parts;
}

void main() {
  late ProviderContainer container;

  Preset sit() => Preset(
    id: 'user-sit',
    name: 'Morning sit',
    slots: PresetSlots(
      sound: _river,
      bells: PresetCues.bells(
        const CueSettings(startSound: _bowl, endSound: _gong),
      ),
      length: const PresetLength.minutes(20),
    ),
  );

  Preset open() => const Preset(
    id: 'user-open',
    name: 'Open sit',
    slots: PresetSlots(length: PresetLength.openEnded()),
  );

  Future<void> pump(
    WidgetTester tester, {
    CueScope scope = _practice,
    bool timer = true,
    List<Preset> presets = const [],
    Size size = const Size(411, 890),
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    SoundscapeStore(prefs)
      ..writePresets(presets)
      ..writePinnedPresets(const []);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
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
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: CustomizeSheet(
              scope: scope,
              isTimer: timer,
              onStart: () {},
              audioDurationMs: 20 * 60000,
              clock: () => DateTime(2026, 1, 1, 9, 0),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Drops the sheet so its 30 second refresh timer is cancelled.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  CueSettings cues(CueScope scope) =>
      container.read(cueSettingsProvider(scope));

  testWidgets('the Timer lists the presets, the user\'s own first, each '
      'saying what it sets', (tester) async {
    await pump(tester, presets: [sit(), open()]);
    expect(_line(tester), 'Presets');
    await _openList(tester);
    final own = tester.getTopLeft(_entry('user-open')).dy;
    final older = tester.getTopLeft(_entry('user-sit')).dy;
    final builtIn = tester.getTopLeft(_entry('starter-rain-forest')).dy;
    expect(own, lessThan(older));
    expect(older, lessThan(builtIn));
    expect(_parts(tester, 'user-sit'), [
      ('River', false),
      ('Singing bowl', false),
      ('20 min', false),
    ]);
    expect(_parts(tester, 'user-open'), [('∞', false)]);
    expect(_parts(tester, 'starter-rain-forest').single.$2, isFalse);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a tap sets the slots the preset holds, and the sheet names '
      'it; a change says "edited"', (tester) async {
    await pump(tester, presets: [sit(), open()]);
    await _pick(tester, 'user-sit');
    expect(cues(_practice).startSound, _bowl);
    expect(cues(_practice).endSound, _gong);
    expect(cues(_practice).durationMinutes, 20);
    expect(
      container
          .read(soundscapeProvider.notifier)
          .sessionDefault(SoundscapeSessionKind.practice)
          .selection,
      const SoundscapeSelection.preset('user-sit'),
    );
    expect(_line(tester), 'From Morning sit');
    // The dial follows.
    expect(find.text('Finishes at 9:20 AM'), findsOneWidget);

    await container
        .read(cueSettingsProvider(_practice).notifier)
        .update(cues(_practice).copyWith(startSound: _gong));
    await tester.pumpAndSettle();
    expect(_line(tester), 'From Morning sit · edited');

    // The list marks the one loaded.
    final semantics = tester.ensureSemantics();
    await _openList(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Use Morning sit'))),
      isSemantics(isSelected: true, isButton: true),
    );
    semantics.dispose();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // ∞: the Timer counts up; the bells of the sit before stay.
    await _pick(tester, 'user-open');
    expect(container.read(timerSettingsProvider).mode, TimerMode.stopwatch);
    expect(cues(_practice).endSound, _gong);
    expect(_line(tester), 'From Open sit');
    await unmount(tester);
  });

  testWidgets('under a recording a preset\'s length is muted and not set; a '
      'preset that holds only a length does nothing', (tester) async {
    await pump(tester, scope: _talks, timer: false, presets: [sit(), open()]);
    await _openList(tester);
    expect(_parts(tester, 'user-sit'), [
      ('River', false),
      ('Singing bowl', false),
      ('20 min', true),
    ]);
    expect(_parts(tester, 'user-open'), [('∞', true)]);
    // It holds nothing that is in play here: tapping it does nothing.
    await tester.tap(_entry('user-open'));
    await tester.pumpAndSettle();
    expect(_list, findsOneWidget);
    expect(_line(tester), 'Presets');
    expect(container.read(timerSettingsProvider).mode, TimerMode.countdown);

    await tester.tap(_entry('user-sit'));
    await tester.pumpAndSettle();
    expect(_list, findsNothing);
    expect(cues(_talks).startSound, _bowl);
    expect(cues(_talks).durationMinutes, 10);
    expect(cues(_practice).startSound, cueDefaultBell);
    expect(_line(tester), 'From Morning sit');
    await unmount(tester);
  });

  testWidgets('a preset\'s ⋮, or holding it, offers Pin to Home, and Delete '
      'for the user\'s own', (tester) async {
    await pump(tester, presets: [sit()]);
    final pins = container.read(pinnedPresetIdsProvider.notifier);
    expect(pins.isPinned('user-sit'), isFalse);
    await _openList(tester);
    await tester.tap(_menu('user-sit'));
    await tester.pumpAndSettle();
    final pin = find.byKey(const ValueKey('preset_pin_user-sit'));
    expect(
      find.descendant(of: pin, matching: find.text('Pin to Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pin, matching: find.byIcon(Icons.push_pin_outlined)),
      findsOneWidget,
    );
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(pins.isPinned('user-sit'), isTrue);

    await tester.longPress(_entry('user-sit'));
    await tester.pumpAndSettle();
    expect(find.text('Unpin from Home'), findsOneWidget);
    await tester.tap(pin);
    await tester.pumpAndSettle();
    expect(pins.isPinned('user-sit'), isFalse);

    // A built-in one can be pinned, not deleted.
    await tester.tap(_menu('starter-night'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('preset_pin_starter-night')), findsOne);
    expect(
      find.byKey(const ValueKey('preset_delete_starter-night')),
      findsNothing,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    pins.pin('user-sit');
    await tester.tap(_menu('user-sit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset_delete_user-sit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset_delete_confirm')));
    await tester.pumpAndSettle();
    expect(_entry('user-sit'), findsNothing);
    expect(container.read(soundscapeProvider).userPresets, isEmpty);
    expect(pins.isPinned('user-sit'), isFalse);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('Save opens the save sheet for this place, and what is saved '
      'is the preset loaded', (tester) async {
    await pump(tester);
    await container
        .read(cueSettingsProvider(_practice).notifier)
        .update(const CueSettings(durationMinutes: 30, startSound: _bowl));
    await tester.pumpAndSettle();
    await tester.ensureVisible(_saveButton);
    await tester.pumpAndSettle();
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(find.byType(SavePresetSheet), findsOneWidget);
    expect(
      tester.widget<SavePresetSheet>(find.byType(SavePresetSheet)).place,
      const PresetContext.timer(),
    );
    await tester.enterText(find.byKey(const ValueKey('preset_name')), 'Half');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('preset_name_save')));
    await tester.pumpAndSettle();
    final saved = container.read(soundscapeProvider).userPresets.single;
    expect(saved.slots.filled, {PresetSlot.bells, PresetSlot.length});
    expect(_line(tester), 'From Half');
    await _openList(tester);
    expect(_entry(saved.id), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('under a recording the save sheet offers no Length', (
    tester,
  ) async {
    await pump(tester, scope: _talks, timer: false);
    await tester.tap(_saveButton);
    await tester.pumpAndSettle();
    expect(
      tester.widget<SavePresetSheet>(find.byType(SavePresetSheet)).place,
      const PresetContext.session(_talks),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('preset_slot_length')),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await unmount(tester);
  });

  testWidgets('a small phone at twice the text size shows the row and the '
      'list without overflow', (tester) async {
    await pump(
      tester,
      presets: [sit()],
      size: const Size(360, 640),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(_row, findsOneWidget);
    await _openList(tester);
    expect(tester.takeException(), isNull);
    expect(_entry('user-sit'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await unmount(tester);
  });
}
