import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/soundscape/sound_control_spec.dart';
import 'package:medito/views/soundscape/sound_controls.dart';
import 'package:medito/views/soundscape/sound_mix_panel.dart';
import 'package:medito/views/soundscape/synth_editors.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// Every sound's editor is built from its spec, out of the one shared
/// vocabulary (#71).
void main() {
  late FakeSoundscapeEngine engine;
  late ProviderContainer container;

  SoundscapeController mixer() => container.read(soundscapeProvider.notifier);
  SoundMix mix() => container.read(soundscapeProvider).mix;
  Map<String, Object?> params(String id) => mix().layer(id)!.params;

  /// A phone with the mix's panel on it, each of [layers] in the mix.
  Future<void> pump(
    WidgetTester tester, {
    Map<String, Map<String, Object?>> layers = const {},
    Locale locale = const Locale('en'),
  }) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    engine = FakeSoundscapeEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...soundscapeTestOverrides(engine),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SoundsMixBody()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    mixer().clearMix();
    for (final MapEntry(key: id, value: p) in layers.entries) {
      mixer().toggleSound(id);
      if (p.isNotEmpty) mixer().setLayerParams(id, p);
    }
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String id) async {
    unawaited(showSynthEditor(tester.element(find.byType(SoundsMixBody)), id));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    Navigator.of(tester.element(find.byType(SoundEditor))).pop();
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String key) {
    final chip = tester.widget(find.byKey(ValueKey(key)));
    return switch (chip) {
      ChoiceChip(:final selected) => selected,
      FilterChip(:final selected) => selected,
      _ => throw StateError('$key is not a chip'),
    };
  }

  group('each sound is built from its spec', () {
    for (final id in kSynthIds) {
      testWidgets('$id: every control in its spec, and nothing else', (
        tester,
      ) async {
        await pump(tester, layers: {id: const {}});
        await open(tester, id);
        final spec = soundControlSpec(id);
        expect(spec.adjustable, isTrue);
        for (final control in spec.adjust) {
          expect(find.byKey(ValueKey(control.id)), findsOneWidget);
        }
        expect(
          find.byType(SoundControlView),
          findsNWidgets(spec.adjust.length),
        );
        expect(
          find.byKey(const ValueKey('binaural_headphones')),
          spec.headphones ? findsWidgets : findsNothing,
        );
        // Nothing is written by opening and looking.
        expect(engine.retuned, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a recording has volume and Swell, and no Adjust', (
      tester,
    ) async {
      await pump(tester, layers: {'rain-terrace': const {}, kSynthDroneId: {}});
      expect(soundControlSpec('rain-terrace').adjustable, isFalse);
      expect(find.byKey(const ValueKey('volume_rain-terrace')), findsOneWidget);
      expect(find.byKey(const ValueKey('swell_rain-terrace')), findsOneWidget);
      expect(find.byKey(const ValueKey('adjust_rain-terrace')), findsNothing);
      expect(find.byKey(ValueKey('adjust_$kSynthDroneId')), findsOneWidget);
    });

    testWidgets('Swell is on every layer, recording or generated, and '
        'toggles it', (tester) async {
      await pump(
        tester,
        layers: {'rain-terrace': const {}, for (final id in kSynthIds) id: {}},
      );
      for (final id in ['rain-terrace', ...kSynthIds]) {
        final swell = find.byKey(ValueKey('swell_$id'));
        await tester.ensureVisible(swell);
        await tester.pumpAndSettle();
        expect(mix().layer(id)!.animate, isFalse);
        await tester.tap(swell);
        await tester.pumpAndSettle();
        expect(mix().layer(id)!.animate, isTrue, reason: id);
        expect(find.text('Rises and falls slowly'), findsWidgets);
      }
    });
  });

  group('binaural beats', () {
    testWidgets('band chips set the beat; the wheel refines it', (
      tester,
    ) async {
      await pump(tester, layers: {kSynthBinauralId: const {}});
      await open(tester, kSynthBinauralId);
      expect(chipSelected(tester, 'binaural_band_theta'), isTrue);
      expect(find.text('4–8 Hz'), findsOneWidget);

      for (final (band, centre, caption) in [
        ('delta', 2.0, '0.5–4 Hz'),
        ('beta', 16.0, '13–30 Hz'),
        ('alpha', 10.0, '8–13 Hz'),
      ]) {
        await tester.tap(find.byKey(ValueKey('binaural_band_$band')));
        await tester.pumpAndSettle();
        expect(
          BinauralParams.fromJson(params(kSynthBinauralId)).beatHz,
          centre,
        );
        expect(chipSelected(tester, 'binaural_band_$band'), isTrue);
        expect(find.text(caption), findsOneWidget);
        // The wheel offers this band's steps only.
        final wheel = tester.widget<WheelPicker<Object?>>(
          find.byKey(const ValueKey('binaural_beat')),
        );
        expect([
          for (final o in wheel.options) o.value,
        ], BeatBand.values.byName(band).steps);
        expect(wheel.value, centre);
      }

      // A step on the wheel, applied once it comes to rest.
      final wheel = tester.state<WheelPickerState<Object?>>(
        find.byKey(const ValueKey('binaural_beat')),
      );
      wheel.moveTo(wheel.selectedIndex + 3);
      await tester.pumpAndSettle();
      expect(BinauralParams.fromJson(params(kSynthBinauralId)).beatHz, 11.5);
      expect(chipSelected(tester, 'binaural_band_alpha'), isTrue);
      expect(engine.retuned.containsKey(kSynthBinauralId), isTrue);
    });

    testWidgets('the tone is a range, applied on release', (tester) async {
      await pump(tester, layers: {kSynthBinauralId: const {}});
      await open(tester, kSynthBinauralId);
      final carrier = find.byKey(const ValueKey('binaural_carrier'));
      await tester.ensureVisible(carrier);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(carrier));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      // Shown while dragged, not yet applied.
      expect(BinauralParams.fromJson(params(kSynthBinauralId)).carrierHz, 200);
      expect(find.textContaining('Tone · 200 Hz'), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        BinauralParams.fromJson(params(kSynthBinauralId)).carrierHz,
        greaterThan(200),
      );
    });

    testWidgets('a beat saved off the steps keeps its place until turned', (
      tester,
    ) async {
      const saved = {'carrierHz': 231.4, 'beatHz': 6.37};
      await pump(tester, layers: {kSynthBinauralId: saved});
      await open(tester, kSynthBinauralId);
      expect(chipSelected(tester, 'binaural_band_theta'), isTrue);
      final wheel = tester.widget<WheelPicker<Object?>>(
        find.byKey(const ValueKey('binaural_beat')),
      );
      expect(wheel.value, 6.37);
      expect([
        for (final o in wheel.options) o.label,
      ], containsAllInOrder(['6.0 Hz', '6.37 Hz', '6.5 Hz']));
      await close(tester);
      expect(params(kSynthBinauralId), saved);
      expect(engine.retuned, isEmpty);
    });

    testWidgets('reads in German, with its decimal comma', (tester) async {
      await pump(
        tester,
        layers: {kSynthBinauralId: const {}},
        locale: const Locale('de'),
      );
      await open(tester, kSynthBinauralId);
      expect(find.text('Schwebung'), findsOneWidget);
      expect(find.text('6,0 Hz'), findsOneWidget);
      expect(find.text('4–8 Hz'), findsOneWidget);
    });
  });

  group('noise', () {
    testWidgets('colour is the control; the bands fold under Equaliser', (
      tester,
    ) async {
      await pump(tester, layers: {kSynthNoiseId: const {}});
      await open(tester, kSynthNoiseId);
      expect(chipSelected(tester, 'noise_colour_pink'), isTrue);
      // No shape words.
      for (final word in ['Shape', 'Even', 'Soft', 'Deep', 'Airy', 'Custom']) {
        expect(find.text(word), findsNothing, reason: word);
      }
      expect(find.text('Equaliser'), findsOneWidget);
      expect(find.byKey(const ValueKey('noise_band_0')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('noise_bands_fold')));
      await tester.pumpAndSettle();
      final band = find.byKey(const ValueKey('noise_band_9'));
      await tester.ensureVisible(band);
      await tester.pumpAndSettle();
      // Its thumb is at the top: a drag down the track lowers the band.
      await tester.drag(band, const Offset(0, 60));
      await tester.pumpAndSettle();
      final bands = NoiseParams.fromJson(params(kSynthNoiseId)).bands;
      expect(bands[9], lessThan(1));
      expect(bands.sublist(0, 9), NoiseParams.flat.sublist(0, 9));

      await tester.tap(find.byKey(const ValueKey('noise_bands_fold')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('noise_band_0')), findsNothing);
    });

    for (final (name, bands) in [
      // What the "Deep" chip once set, and a curve drawn by hand.
      ('a shape', [1, 1, 1, 0.8, 0.55, 0.35, 0.22, 0.14, 0.09, 0.06]),
      ('a curve of its own', [0, 0.25, 1, 0.8, 0.31, 0.6, 1, 0.4, 0.1, 0]),
    ]) {
      testWidgets('a mix saved with $name opens and closes as it was, and '
          'keeps its bands through a colour change', (tester) async {
        final saved = {'colour': 'white', 'bands': bands};
        await pump(tester, layers: {kSynthNoiseId: saved});
        await open(tester, kSynthNoiseId);
        expect(chipSelected(tester, 'noise_colour_white'), isTrue);
        await close(tester);
        expect(params(kSynthNoiseId), saved);
        expect(engine.retuned, isEmpty);

        await open(tester, kSynthNoiseId);
        await tester.tap(find.byKey(const ValueKey('noise_colour_brown')));
        await tester.pumpAndSettle();
        final noise = NoiseParams.fromJson(params(kSynthNoiseId));
        expect(noise.colour, NoiseColour.brown);
        expect(noise.bands, bands);
      });
    }
  });

  group('drone', () {
    testWidgets('root and timbre chips, and the movement range', (
      tester,
    ) async {
      await pump(tester, layers: {kSynthDroneId: const {}});
      await open(tester, kSynthDroneId);
      expect(chipSelected(tester, 'drone_root_A2'), isTrue);
      await tester.tap(find.byKey(const ValueKey('drone_root_D3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drone_root_A2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drone_timbre_pure')));
      await tester.pumpAndSettle();
      final movement = find.byKey(const ValueKey('drone_movement'));
      await tester.drag(movement, const Offset(-400, 0));
      await tester.pumpAndSettle();
      final drone = DroneParams.fromJson(params(kSynthDroneId));
      expect(drone.rootsHz, [DroneParams.roots['D3']]);
      expect(drone.timbre, DroneTimbre.pure);
      expect(drone.movement, 0);
      // Tapping the chosen root again keeps it: there is always a root.
      await tester.tap(find.byKey(const ValueKey('drone_root_D3')));
      await tester.pumpAndSettle();
      expect(chipSelected(tester, 'drone_root_D3'), isTrue);
    });

    testWidgets('a root saved off the chips stays when another is chosen', (
      tester,
    ) async {
      await pump(
        tester,
        layers: {
          kSynthDroneId: const {'rootHz': 100.0},
        },
      );
      await open(tester, kSynthDroneId);
      expect(find.text('Up to three notes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('drone_root_A3')));
      await tester.pumpAndSettle();
      expect(DroneParams.fromJson(params(kSynthDroneId)).rootsHz, [100, 220]);
      // It shows as a chip of its own, and can be turned off.
      expect(find.text('100 Hz'), findsOneWidget);
      expect(chipSelected(tester, 'drone_root_100.0'), isTrue);
      await tester.tap(find.byKey(const ValueKey('drone_root_100.0')));
      await tester.pumpAndSettle();
      expect(DroneParams.fromJson(params(kSynthDroneId)).rootsHz, [220]);
    });

    testWidgets('the last root says why it stays, on its own node', (
      tester,
    ) async {
      await pump(tester, layers: {kSynthDroneId: const {}});
      await open(tester, kSynthDroneId);
      final handle = tester.ensureSemantics();
      final node = tester.getSemantics(
        find.byKey(const ValueKey('drone_root_A2')),
      );
      final data = node.getSemanticsData();
      expect(data.hint, 'At least one stays chosen');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, contains('A2'));
      handle.dispose();
    });

    testWidgets('roots make a chord of up to three', (tester) async {
      await pump(tester, layers: {kSynthDroneId: const {}});
      await open(tester, kSynthDroneId);
      for (final r in ['E2', 'A3']) {
        await tester.tap(find.byKey(ValueKey('drone_root_$r')));
        await tester.pumpAndSettle();
      }
      expect(DroneParams.fromJson(params(kSynthDroneId)).rootsHz, [
        82.41,
        110,
        220,
      ]);
      // Full: a fourth root does nothing until one comes off.
      await tester.tap(
        find.byKey(const ValueKey('drone_root_G2')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(DroneParams.fromJson(params(kSynthDroneId)).rootsHz.length, 3);
      await tester.tap(find.byKey(const ValueKey('drone_root_A3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('drone_root_G2')));
      await tester.pumpAndSettle();
      expect(DroneParams.fromJson(params(kSynthDroneId)).rootsHz, [
        82.41,
        98,
        110,
      ]);
    });
  });

  testWidgets('chips can hold several choices (the seam for a chord, #69)', (
    tester,
  ) async {
    // A drone whose roots chips allow two at once, kept in a test key.
    final chord = SoundChips<String>(
      id: 'chord',
      title: (l) => l.droneRoot,
      maxSelected: 2,
      choices: [
        for (final name in ['A2', 'D3', 'E3'])
          SoundChoice(name, name, (_) => name),
      ],
      read: (p) => {
        ...(p['chord'] as List? ?? const ['A2']).cast<String>(),
      },
      write: (p, s) => {
        ...p,
        'chord': [...s],
      },
    );
    await pump(tester, layers: {kSynthDroneId: const {}});
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byType(SoundsMixBody)),
        builder: (_) => SoundEditor(
          id: kSynthDroneId,
          spec: SoundControlSpec(adjust: [chord]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<Object?> chosen() => params(kSynthDroneId)['chord']! as List;

    await tester.tap(find.byKey(const ValueKey('chord_D3')));
    await tester.pumpAndSettle();
    expect(chosen(), unorderedEquals(['A2', 'D3']));
    // Full: the third waits until one comes off.
    expect(
      tester
          .widget<FilterChip>(find.byKey(const ValueKey('chord_E3')))
          .onSelected,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('chord_A2')));
    await tester.pumpAndSettle();
    expect(chosen(), ['D3']);
    // The last one stays: a chord of nothing is not a choice.
    await tester.tap(find.byKey(const ValueKey('chord_D3')));
    await tester.pumpAndSettle();
    expect(chosen(), ['D3']);
    expect(chipSelected(tester, 'chord_D3'), isTrue);
  });
}
