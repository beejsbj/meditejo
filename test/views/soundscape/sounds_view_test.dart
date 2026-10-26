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
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/soundscape/synth_editors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

void main() {
  late FakeSoundscapeEngine engine;
  late ProviderContainer container;

  final starter = kStarterPresets.first;

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Widget home = const SoundsView(),
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
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
  }

  /// A phone: the mix is docked under the library.
  void phone(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 200,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_library')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls the presets row to [finder] (it builds its cards lazily).
  Future<void> revealPreset(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_presets')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMix(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
    await tester.pumpAndSettle();
  }

  SoundMix mix() => container.read(soundscapeProvider).mix;

  testWidgets('presets, the library as cards, and the mix in the dock', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    expect(find.text('Sounds'), findsOneWidget);
    expect(find.text('Your mix'), findsOneWidget);
    // The first starter preset is the mix of a fresh install, and its card
    // leads the presets.
    expect(find.byKey(ValueKey('preset_${starter.id}')), findsOneWidget);
    expect(find.text('Rain on the forest'), findsWidgets);
    // The dock is folded: no layers until it opens.
    expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);
    await openMix(tester);
    for (final layer in starter.mix.layers) {
      expect(find.byKey(ValueKey('layer_${layer.soundId}')), findsOneWidget);
    }
    await openMix(tester);
    expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);

    // Generated sounds and recordings, shelf by shelf.
    expect(find.byKey(const ValueKey('sound_synth-noise')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('shelf_night')));
    await reveal(tester, find.byKey(const ValueKey('sound_night-frogs')));
    expect(engine.playing, isEmpty, reason: 'nothing plays until asked');
  });

  testWidgets('play starts the mix; tapping a card layers it in and out', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_play')));
    await tester.pumpAndSettle();
    expect(engine.playing.keys.toSet(), {
      for (final l in starter.mix.layers) l.soundId,
    });

    final cafe = find.byKey(const ValueKey('sound_cafe'));
    await reveal(tester, cafe);
    await tester.tap(cafe);
    await tester.pumpAndSettle();
    expect(mix().contains('cafe'), isTrue);
    expect(engine.playing.containsKey('cafe'), isTrue);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Café')),
      isSemantics(isSelected: true, isButton: true),
    );
    // No longer the preset: the presets row offers to save it.
    await reveal(
      tester,
      find.byKey(const PageStorageKey('sounds_presets')),
      delta: -300,
    );
    await revealPreset(tester, find.byKey(const ValueKey('preset_save')));

    await reveal(tester, cafe);
    await tester.tap(cafe);
    await tester.pumpAndSettle();
    expect(mix().contains('cafe'), isFalse);
    expect(engine.playing.containsKey('cafe'), isFalse);

    await tester.tap(find.byKey(const ValueKey('sounds_stop')));
    await tester.pumpAndSettle();
    expect(engine.playing, isEmpty);
  });

  testWidgets('a preset card starts it in one tap', (tester) async {
    phone(tester);
    await pump(tester);
    final night = find.byKey(const ValueKey('preset_starter-night'));
    await tester.ensureVisible(night);
    await tester.tap(night);
    await tester.pumpAndSettle();
    final state = container.read(soundscapeProvider);
    expect(state.playing, isTrue);
    expect(state.matchingPreset?.id, 'starter-night');
    expect(engine.playing.keys.toSet(), {'night-meadow', 'stream'});
    expect(find.text('Playing'), findsWidgets);
  });

  testWidgets('layers: volume, mute, drift and remove', (tester) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_play')));
    await tester.pumpAndSettle();
    await openMix(tester);
    final id = starter.mix.layers.first.soundId;
    final before = mix().layer(id)!.volume;

    await tester.drag(find.byKey(ValueKey('volume_$id')), const Offset(-80, 0));
    await tester.pumpAndSettle();
    final dragged = mix().layer(id)!.volume;
    expect(dragged, lessThan(before));

    await tester.tap(find.byKey(ValueKey('mute_$id')));
    await tester.pumpAndSettle();
    expect(mix().layer(id)!.volume, 0);
    expect(engine.playing[id], 0);
    await tester.tap(find.byKey(ValueKey('mute_$id')));
    await tester.pumpAndSettle();
    expect(mix().layer(id)!.volume, dragged, reason: 'back to its level');

    final drift = mix().layer(id)!.animate;
    await tester.tap(find.byKey(ValueKey('drift_$id')));
    await tester.pumpAndSettle();
    expect(mix().layer(id)!.animate, !drift);

    await tester.tap(find.byKey(ValueKey('remove_$id')));
    await tester.pumpAndSettle();
    expect(mix().contains(id), isFalse);
    expect(engine.playing.containsKey(id), isFalse);
    expect(find.byKey(ValueKey('layer_$id')), findsNothing);
    expect(
      find.byKey(ValueKey('layer_${starter.mix.layers[1].soundId}')),
      findsOneWidget,
    );
  });

  testWidgets('a layer added from the library joins the open panel', (
    tester,
  ) async {
    // A wide window keeps the panel open beside the library.
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(find.byKey(const ValueKey('sounds_mix_toggle')), findsNothing);
    expect(find.byKey(const ValueKey('sounds_volume')), findsOneWidget);
    container.read(soundscapeProvider.notifier).clearMix();
    await tester.pumpAndSettle();
    expect(find.text('Nothing in your mix yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sound_synth-drone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('layer_synth-drone')), findsOneWidget);
    expect(find.byKey(const ValueKey('adjust_synth-drone')), findsOneWidget);
    expect(find.text('Nothing in your mix yet'), findsNothing);
  });

  testWidgets('an empty mix stays docked and says how to start', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    container.read(soundscapeProvider.notifier).clearMix();
    await tester.pumpAndSettle();
    expect(find.text('Tap a sound or a preset to start a mix.'), findsOne);
    expect(find.byKey(const ValueKey('sounds_mix_toggle')), findsNothing);
    await tester.tap(find.text('Your mix'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('sounds_play')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('saves the mix as a preset from the panel', (tester) async {
    phone(tester);
    await pump(tester);
    container.read(soundscapeProvider.notifier).toggleSound('river');
    await tester.pumpAndSettle();
    await openMix(tester);
    final save = find.byKey(const ValueKey('mix_save'));
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('sounds_dock')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('preset_name')),
      'Morning',
    );
    await tester.tap(find.byKey(const ValueKey('preset_name_save')));
    await tester.pumpAndSettle();
    final preset = container.read(soundscapeProvider).userPresets.single;
    expect(preset.name, 'Morning');
    expect(preset.mix.contains('river'), isTrue);
    // Saved: the mix is that preset now, so there is nothing to save.
    expect(find.byKey(const ValueKey('mix_save')), findsNothing);
    await openMix(tester);
    await revealPreset(tester, find.byKey(ValueKey('preset_${preset.id}')));
  });

  testWidgets('saves from the presets row, and deletes from a card menu', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    container.read(soundscapeProvider.notifier).toggleSound('river');
    await tester.pumpAndSettle();
    final save = find.byKey(const ValueKey('preset_save'));
    await revealPreset(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('preset_name')), 'Eve');
    await tester.tap(find.byKey(const ValueKey('preset_name_save')));
    await tester.pumpAndSettle();
    final id = container.read(soundscapeProvider).userPresets.single.id;
    // Built-in presets have no menu.
    expect(find.byKey(ValueKey('preset_menu_${starter.id}')), findsNothing);

    final menu = find.byKey(ValueKey('preset_menu_$id'));
    await revealPreset(tester, menu);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('preset_delete_$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset_delete_confirm')));
    await tester.pumpAndSettle();
    expect(container.read(soundscapeProvider).userPresets, isEmpty);
    expect(find.byKey(ValueKey('preset_$id')), findsNothing);
  });

  testWidgets('a full mix greys out the rest and says why', (tester) async {
    phone(tester);
    await pump(tester);
    final controller = container.read(soundscapeProvider.notifier)..clearMix();
    for (final id in [...kSynthIds, 'river', 'cafe', 'rain-car']) {
      controller.toggleSound(id);
    }
    await tester.pumpAndSettle();
    expect(mix().layers, hasLength(SoundMix.kMaxLayers));
    expect(find.text('A mix holds up to 6 sounds'), findsOneWidget);
    final frogs = find.byKey(const ValueKey('sound_night-frogs'));
    await reveal(tester, frogs);
    await tester.tap(frogs);
    await tester.pumpAndSettle();
    expect(mix().contains('night-frogs'), isFalse);
    expect(mix().layers, hasLength(SoundMix.kMaxLayers));
  });

  testWidgets('session switches start off and follow the taps (decision 17)', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    final practice = find.byKey(const ValueKey('under_practice'));
    await reveal(tester, practice);
    expect(tester.widget<SwitchListTile>(practice).value, isFalse);
    await tester.tap(practice);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(practice).value, isTrue);
    final talks = find.byKey(const ValueKey('under_talks'));
    await reveal(tester, talks);
    expect(tester.widget<SwitchListTile>(talks).value, isFalse);
    await tester.tap(talks);
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
    phone(tester);
    await pump(tester);
    container.read(soundscapeProvider.notifier).clearMix();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sound_synth-binaural')));
    await tester.pumpAndSettle();
    expect(engine.playing.containsKey(kSynthBinauralId), isTrue);
    await openMix(tester);
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
      mix().layer(kSynthBinauralId)!.params,
    );
    expect(params.beatHz, greaterThan(6));
  });

  testWidgets('noise editor: colour and reset commit to the layer', (
    tester,
  ) async {
    phone(tester);
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
    await openMix(tester);
    await tester.tap(find.byKey(const ValueKey('adjust_synth-noise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Brown'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('noise_reset')));
    await tester.pumpAndSettle();
    final params = NoiseParams.fromJson(mix().layer(kSynthNoiseId)!.params);
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
    expect(tester.takeException(), isNull);
    final controller = container.read(soundscapeProvider.notifier)..clearMix();
    for (final id in kSynthIds) {
      controller.toggleSound(id);
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final context = tester.element(find.byType(SoundsView));
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

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits a 360 dp phone at ${scale}x text, docked and open', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
      expect(tester.takeException(), isNull);
      await openMix(tester);
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(ValueKey('remove_${starter.mix.layers.first.soundId}')),
        findsOneWidget,
      );
    });
  }

  testWidgets('is localised', (tester) async {
    phone(tester);
    await pump(tester, locale: const Locale('de'));
    expect(find.text('Dein Mix'), findsOneWidget);
    expect(find.text('Regen im Wald'), findsWidgets);
  });

  testWidgets('credits are one tap away and list every sound', (tester) async {
    phone(tester);
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('sound_credits')));
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
      if (sound.license.requiresAttribution) {
        // CC BY must be credited in the app too: title, author, licence,
        // source and the changes made.
        final tile = find.byKey(ValueKey('credit_${sound.id}'));
        for (final text in [
          sound.originalTitle,
          sound.author,
          sound.license.label,
          sound.modifications,
          Uri.parse(sound.sourceUrl).host,
          'Attribution required',
        ]) {
          expect(
            find.descendant(of: tile, matching: find.textContaining(text)),
            findsWidgets,
            reason: '${sound.id}: $text',
          );
        }
      }
    }
    expect(find.text('CC0 1.0'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // And from the foot of the library.
    final footer = find.byKey(const ValueKey('sound_credits_footer'));
    await reveal(tester, footer);
    await tester.tap(footer);
    await tester.pumpAndSettle();
    expect(find.byType(SoundCreditsView), findsOneWidget);
  });

  testWidgets('as a page: back folds the open mix, then closes', (
    tester,
  ) async {
    phone(tester);
    await pump(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openSoundsPage(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(SoundsView), findsOneWidget);
    await openMix(tester);
    expect(find.byKey(const ValueKey('sounds_volume')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SoundsView), findsOneWidget);
    expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SoundsView), findsNothing);
  });
}
