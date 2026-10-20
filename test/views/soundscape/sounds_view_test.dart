import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/background_sound/background_sound_view.dart';
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/soundscape/synth_editors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

void main() {
  late FakeSoundscapeEngine engine;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
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
          home: const Scaffold(body: BackgroundSoundView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(BackgroundSoundView)),
    );
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 200,
  }) async {
    await tester.scrollUntilVisible(finder, delta);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the starter mix, presets and the library shelves', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Your mix'), findsOneWidget);
    // The first starter preset is the mix of a fresh install.
    expect(find.text('Rain on the forest'), findsWidgets);
    for (final layer in kStarterPresets.first.mix.layers) {
      expect(find.byKey(ValueKey('layer_${layer.soundId}')), findsOneWidget);
    }
    await reveal(tester, find.text('NIGHT'));
    expect(find.byKey(const ValueKey('sound_night-frogs')), findsOneWidget);
    expect(engine.playing, isEmpty, reason: 'nothing plays until asked');
  });

  testWidgets('play starts the mix; tapping a sound layers it in', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_play')));
    await tester.pumpAndSettle();
    expect(engine.playing.keys.toSet(), {
      for (final l in kStarterPresets.first.mix.layers) l.soundId,
    });

    final cafe = find.byKey(const ValueKey('sound_cafe'));
    await reveal(tester, cafe);
    await tester.tap(cafe);
    await tester.pumpAndSettle();
    expect(container.read(soundscapeProvider).mix.contains('cafe'), isTrue);
    expect(engine.playing.containsKey('cafe'), isTrue);
    // No longer the preset: offer to save it.
    await reveal(
      tester,
      find.byKey(const ValueKey('preset_save')),
      delta: -200,
    );
    expect(find.byKey(const ValueKey('preset_save')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sounds_stop')));
    await tester.pumpAndSettle();
    expect(engine.playing, isEmpty);
  });

  testWidgets('saves the mix as a preset', (tester) async {
    await pump(tester);
    container.read(soundscapeProvider.notifier).toggleSound('river');
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('preset_save'));
    await reveal(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('preset_name')),
      'Morning',
    );
    await tester.tap(find.byKey(const ValueKey('preset_name_save')));
    await tester.pumpAndSettle();
    final state = container.read(soundscapeProvider);
    expect(state.userPresets.single.name, 'Morning');
    expect(find.text('Morning'), findsWidgets);
  });

  testWidgets('session switches follow decision 8', (tester) async {
    await pump(tester);
    final practice = find.byKey(const ValueKey('under_practice'));
    await reveal(tester, practice);
    expect(tester.widget<SwitchListTile>(practice).value, isTrue);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const ValueKey('under_talks')))
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('under_talks')));
    await tester.pumpAndSettle();
    expect(
      container
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.talks)
          .enabled,
      isTrue,
    );
  });

  testWidgets('binaural beats: layer, headphones note and editor', (
    tester,
  ) async {
    await pump(tester);
    container.read(soundscapeProvider.notifier).clearMix();
    await tester.pumpAndSettle();
    final pill = find.byKey(const ValueKey('sound_synth-binaural'));
    await reveal(tester, pill);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(engine.playing.containsKey(kSynthBinauralId), isTrue);
    await reveal(
      tester,
      find.byKey(const ValueKey('adjust_synth-binaural')),
      delta: -200,
    );
    expect(find.byKey(const ValueKey('binaural_headphones')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('adjust_synth-binaural')));
    await tester.pumpAndSettle();
    expect(
      find.text('Binaural beats need headphones: each ear hears its own tone.'),
      findsWidgets,
    );
    await tester.drag(
      find.byKey(const ValueKey('binaural_beat')),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    final params = BinauralParams.fromJson(
      container.read(soundscapeProvider).mix.layer(kSynthBinauralId)!.params,
    );
    expect(params.beatHz, greaterThan(6));
  });

  testWidgets('noise editor: colour and reset commit to the layer', (
    tester,
  ) async {
    await pump(tester);
    final controller = container.read(soundscapeProvider.notifier)
      ..clearMix()
      ..toggleSound(kSynthNoiseId);
    await tester.pumpAndSettle();
    controller.setLayerParams(
      kSynthNoiseId,
      const NoiseParams(bands: [0, 0, 0, 0, 0, 1, 1, 1, 1, 1]).toJson(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust_synth-noise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brown'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('noise_reset')));
    await tester.pumpAndSettle();
    final params = NoiseParams.fromJson(
      container.read(soundscapeProvider).mix.layer(kSynthNoiseId)!.params,
    );
    expect(params.colour, NoiseColour.brown);
    expect(params.bands, NoiseParams.flat);
    expect(engine.retuned.containsKey(kSynthNoiseId), isTrue);
  });

  testWidgets('the editors scroll on a short screen at large text', (
    tester,
  ) async {
    // A phone in landscape, with the text at 160 %.
    tester.view
      ..physicalSize = const Size(800, 360)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);
    final controller = container.read(soundscapeProvider.notifier)..clearMix();
    for (final id in kSynthIds) {
      controller.toggleSound(id);
    }
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(BackgroundSoundView));
    for (final (id, last) in [
      (kSynthNoiseId, 'noise_band_9'),
      (kSynthDroneId, 'drone_movement'),
      (kSynthBinauralId, 'binaural_beat'),
    ]) {
      unawaited(showSynthEditor(context, id));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$id overflows');
      // Its last control can be reached.
      await tester.scrollUntilVisible(
        find.byKey(ValueKey(last)),
        100,
        scrollable: find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(ValueKey(last)).hitTestable(), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('is localised', (tester) async {
    await pump(tester, locale: const Locale('de'));
    expect(find.text('Dein Mix'), findsOneWidget);
    expect(find.text('Regen im Wald'), findsWidgets);
  });

  testWidgets('credits list every bundled sound with its licence', (
    tester,
  ) async {
    await pump(tester);
    final link = find.byKey(const ValueKey('sound_credits'));
    await reveal(tester, link);
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(SoundCreditsView), findsOneWidget);
    final library = await container.read(soundLibraryProvider.future);
    final list = find.byType(Scrollable).last;
    for (final sound in library.sounds) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('credit_${sound.id}')),
        200,
        scrollable: list,
      );
    }
    expect(find.text('CC0 1.0'), findsWidgets);
  });
}
