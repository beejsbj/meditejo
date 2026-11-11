import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/presets/save_preset_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _heart = 'assets/audio/pulse_heartbeat.wav';
const _river = SoundMix([SoundLayer(soundId: 'river', volume: 0.6)]);
const _practice = CueScope(CueKind.practice);
const _talks = CueScope(CueKind.talks);

Finder _slot(PresetSlot slot) =>
    find.byKey(ValueKey('preset_slot_${slot.name}'));
final _name = find.byKey(const ValueKey('preset_name'));
final _save = find.byKey(const ValueKey('preset_name_save'));
final _update = find.byKey(const ValueKey('preset_update'));
final _asNew = find.byKey(const ValueKey('preset_save_as_new'));
final _pin = find.byKey(const ValueKey('preset_pin'));

/// The slot's checkbox; none where the slot is not offered.
Finder _box(PresetSlot slot) =>
    find.descendant(of: _slot(slot), matching: find.byType(Checkbox));

bool? _ticked(WidgetTester tester, PresetSlot slot) =>
    tester.widget<Checkbox>(_box(slot)).value;

Finder _says(PresetSlot slot, String text) =>
    find.descendant(of: _slot(slot), matching: find.text(text));

void main() {
  late ProviderContainer container;
  SavedPreset? result;

  /// A page with one button that opens the save sheet on [place].
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(411, 890),
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
    );
    addTearDown(container.dispose);
    result = null;
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
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, PresetContext place) async {
    final context = tester.element(find.byType(Scaffold));
    showSavePresetSheet(context, place).then((saved) => result = saved);
    await tester.pumpAndSettle();
  }

  SoundscapeController mixer() => container.read(soundscapeProvider.notifier);
  List<Preset> mine() => container.read(soundscapeProvider).userPresets;
  Future<void> set(CueScope scope, CueSettings settings) =>
      container.read(cueSettingsProvider(scope).notifier).update(settings);

  Preset sit() => Preset(
    id: 'user-sit',
    name: 'Morning sit',
    slots: PresetSlots(
      sound: _river,
      bells: PresetCues.bells(const CueSettings(startSound: _bowl)),
      length: const PresetLength.minutes(20),
    ),
  );

  testWidgets('from the Timer all four slots are offered, ticked where they '
      'differ from the defaults', (tester) async {
    await pump(tester);
    await set(
      _practice,
      const CueSettings(durationMinutes: 25, startSound: _bowl),
    );
    await open(tester, const PresetContext.timer());
    for (final slot in PresetSlot.values) {
      expect(_box(slot), findsOneWidget, reason: slot.name);
    }
    expect(_ticked(tester, PresetSlot.sound), isFalse);
    expect(_ticked(tester, PresetSlot.bells), isTrue);
    expect(_ticked(tester, PresetSlot.rhythm), isFalse);
    expect(_ticked(tester, PresetSlot.length), isTrue);
    expect(_says(PresetSlot.bells, 'Singing bowl / Session bell'), findsOne);
    expect(_says(PresetSlot.length, '25 min'), findsOne);
    expect(_says(PresetSlot.rhythm, 'Off'), findsOne);
    // Nothing loaded: a name and Save, which waits for the name.
    expect(_update, findsNothing);
    expect(_asNew, findsNothing);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    await tester.enterText(_name, 'Short sit');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final saved = mine().single;
    expect(saved.name, 'Short sit');
    expect(saved.slots.filled, {PresetSlot.bells, PresetSlot.length});
    expect(saved.slots.length, const PresetLength.minutes(25));
    expect(result!.preset, saved);
    expect(result!.updated, isFalse);
    expect(find.byType(SavePresetSheet), findsNothing);
  });

  testWidgets('a slot can be ticked or unticked before saving; with none '
      'ticked there is nothing to save', (tester) async {
    await pump(tester);
    await set(_practice, const CueSettings(startSound: _bowl));
    await open(tester, const PresetContext.timer());
    await tester.enterText(_name, 'Mine');
    await tester.pump();
    await tester.tap(_slot(PresetSlot.bells));
    await tester.pump();
    expect(_ticked(tester, PresetSlot.bells), isFalse);
    expect(tester.widget<FilledButton>(_save).onPressed, isNull);
    await tester.tap(_slot(PresetSlot.length));
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(mine().single.slots.filled, {PresetSlot.length});
    expect(mine().single.slots.length, const PresetLength.minutes(10));
  });

  testWidgets('under a recording Sound, Bells and Rhythm are offered; '
      'Length is shown, not saved', (tester) async {
    await pump(tester);
    await set(_talks, const CueSettings(pulseSound: _heart, pulseBpm: 54));
    await open(tester, const PresetContext.session(_talks));
    for (final slot in [
      PresetSlot.sound,
      PresetSlot.bells,
      PresetSlot.rhythm,
    ]) {
      expect(_box(slot), findsOneWidget, reason: slot.name);
    }
    expect(_box(PresetSlot.length), findsNothing);
    expect(_says(PresetSlot.length, 'Not set'), findsOne);
    expect(_ticked(tester, PresetSlot.rhythm), isTrue);
    expect(_says(PresetSlot.rhythm, 'Heartbeat · 54 BPM'), findsOne);
    // The read-only row does nothing when tapped.
    await tester.tap(_slot(PresetSlot.length));
    await tester.pump();
    await tester.enterText(_name, 'Talks');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(mine().single.slots.filled, {PresetSlot.rhythm});
  });

  testWidgets('from the Sounds sheet only Sound is offered', (tester) async {
    await pump(tester);
    mixer().toggleSound('river');
    await tester.pump();
    await open(tester, const PresetContext.sounds());
    expect(_box(PresetSlot.sound), findsOneWidget);
    expect(_ticked(tester, PresetSlot.sound), isTrue);
    // The mix a new install starts with, and the river added to it.
    expect(
      find.descendant(
        of: _slot(PresetSlot.sound),
        matching: find.textContaining('River'),
      ),
      findsOne,
    );
    for (final slot in [
      PresetSlot.bells,
      PresetSlot.rhythm,
      PresetSlot.length,
    ]) {
      expect(_box(slot), findsNothing, reason: slot.name);
      expect(_says(slot, 'Not set'), findsOne, reason: slot.name);
    }
    await tester.enterText(_name, 'River');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(mine().single.slots.filled, {PresetSlot.sound});
    expect(mine().single.mix.contains('river'), isTrue);
    mixer().stop();
    await tester.pumpAndSettle();
  });

  testWidgets('a preset loaded and edited: Update writes only the offered, '
      'ticked slots, and the rest are shown as kept (#68)', (tester) async {
    await pump(tester);
    mixer().putPreset(sit());
    await applyPreset(container, const PresetContext.sounds(), sit());
    await tester.pumpAndSettle();
    mixer().toggleSound('cafe');
    await tester.pumpAndSettle();
    await open(tester, const PresetContext.sounds());
    expect(_name, findsNothing);
    expect(_save, findsNothing);
    expect(find.text('Update “Morning sit”'), findsOne);
    expect(_asNew, findsOneWidget);
    expect(_ticked(tester, PresetSlot.sound), isTrue);
    expect(
      _says(PresetSlot.bells, 'Singing bowl / Session bell · kept'),
      findsOne,
    );
    expect(_says(PresetSlot.length, '20 min · kept'), findsOne);
    expect(_says(PresetSlot.rhythm, 'Not set'), findsOne);
    await tester.tap(_update);
    await tester.pumpAndSettle();
    final updated = mine().single;
    expect(updated.id, 'user-sit');
    expect(updated.mix.contains('cafe'), isTrue);
    expect(updated.slots.bells, sit().slots.bells);
    expect(updated.slots.length, sit().slots.length);
    expect(result!.updated, isTrue);
    mixer().stop();
    await tester.pumpAndSettle();
  });

  testWidgets('Save as new asks for a name and leaves the loaded preset as '
      'it was', (tester) async {
    await pump(tester);
    mixer().putPreset(sit());
    await applyPreset(container, const PresetContext.sounds(), sit());
    await tester.pumpAndSettle();
    mixer().toggleSound('cafe');
    await tester.pumpAndSettle();
    await open(tester, const PresetContext.sounds());
    await tester.tap(_asNew);
    await tester.pumpAndSettle();
    expect(_update, findsNothing);
    expect(_asNew, findsNothing);
    expect(_says(PresetSlot.length, 'Not set'), findsOne);
    await tester.enterText(_name, 'Café');
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(mine(), hasLength(2));
    expect(mine().first, sit());
    expect(mine().last.name, 'Café');
    expect(mine().last.slots.filled, {PresetSlot.sound});
    expect(mine().last.mix.contains('cafe'), isTrue);
    expect(result!.updated, isFalse);
    mixer().stop();
    await tester.pumpAndSettle();
  });

  testWidgets('on the Timer, Update ticks a slot that was changed, so a '
      'sound-only preset gains bells unless it is unticked', (tester) async {
    await pump(tester);
    final rain = Preset.sound(id: 'user-rain', name: 'Rain', mix: _river);
    mixer().putPreset(rain);
    await applyPreset(container, const PresetContext.timer(), rain);
    await set(_practice, const CueSettings(startSound: _bowl));
    await tester.pump();
    await open(tester, const PresetContext.timer());
    expect(find.text('Update “Rain”'), findsOne);
    expect(_ticked(tester, PresetSlot.sound), isTrue);
    expect(_ticked(tester, PresetSlot.bells), isTrue);
    expect(_ticked(tester, PresetSlot.length), isFalse);
    await tester.tap(_slot(PresetSlot.bells));
    await tester.pump();
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(mine().single.slots.filled, {PresetSlot.sound});
    await open(tester, const PresetContext.timer());
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(mine().single.slots.filled, {PresetSlot.sound, PresetSlot.bells});
  });

  testWidgets('a built-in preset cannot be updated: its changed mix is saved '
      'as a new one', (tester) async {
    await pump(tester);
    mixer().applyPreset('starter-night');
    await tester.pumpAndSettle();
    mixer().toggleSound('river');
    await tester.pumpAndSettle();
    await open(tester, const PresetContext.sounds());
    expect(_update, findsNothing);
    expect(_name, findsOneWidget);
    mixer().stop();
    await tester.pumpAndSettle();
  });

  testWidgets('Pin to Home pins what is saved; on Update the tick shows and '
      'sets whether it is pinned', (tester) async {
    await pump(tester);
    await set(_practice, const CueSettings(startSound: _bowl));
    await open(tester, const PresetContext.timer());
    await tester.enterText(_name, 'Pinned sit');
    await tester.pump();
    await tester.ensureVisible(_pin);
    await tester.tap(_pin);
    await tester.pump();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    final id = mine().single.id;
    expect(container.read(pinnedPresetIdsProvider), contains(id));
    expect(find.text('Pin to Home'), findsNothing);

    await set(_practice, const CueSettings(startSound: ''));
    await tester.pump();
    await open(tester, const PresetContext.timer());
    expect(find.text('Pin to Home'), findsOne);
    final box = find.descendant(of: _pin, matching: find.byType(Checkbox));
    expect(tester.widget<Checkbox>(box).value, isTrue);
    await tester.tap(_pin);
    await tester.pump();
    await tester.tap(_update);
    await tester.pumpAndSettle();
    expect(container.read(pinnedPresetIdsProvider), isNot(contains(id)));
  });

  testWidgets('fits a small phone at twice the text size: nothing overflows '
      'and Save is on screen', (tester) async {
    await pump(tester, size: const Size(360, 640), textScale: 2);
    await set(_practice, const CueSettings(startSound: _bowl));
    await open(tester, const PresetContext.timer());
    expect(tester.takeException(), isNull);
    final save = tester.getRect(_save);
    expect(save.bottom, lessThanOrEqualTo(640));
    await tester.ensureVisible(_pin);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
