import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/soundscape/sound_credits_view.dart';
import 'package:medito/views/soundscape/sound_cards.dart';
import 'package:medito/views/soundscape/sounds_sheet.dart';
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
    Map<String, Object> prefsValues = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsValues);
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

  testWidgets('Clear is in the open dock only; Undo restores the exact mix', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    final clear = find.byKey(const ValueKey('sounds_clear'));
    expect(clear, findsNothing, reason: 'not on the docked bar');
    await openMix(tester);
    expect(clear, findsOneWidget);
    expect(
      find.byKey(const ValueKey('sounds_mix_toggle')),
      findsOneWidget,
      reason: 'the chevron stays',
    );

    final controller = container.read(soundscapeProvider.notifier);
    controller.setLayerVolume(starter.mix.layers.first.soundId, 0.37);
    controller.setLayerAnimate(starter.mix.layers.first.soundId, true);
    await tester.pumpAndSettle();
    controller.togglePlay();
    await tester.pumpAndSettle();
    expect(container.read(soundscapeProvider).playing, isTrue);
    final before = mix();
    expect(before.isEmpty, isFalse);

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(mix().isEmpty, isTrue);
    expect(container.read(soundscapeProvider).active, isFalse);
    expect(find.text('Mix cleared'), findsOneWidget);
    // Folded to its bar, the dock is not under the toast: it sits above.
    await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Mix cleared'), findsOneWidget);
    expect(
      // The toast's own surface: the SnackBar's box includes its margin.
      tester
          .getRect(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const ValueKey('sounds_dock'))).top,
      ),
    );

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(mix().layers, before.layers);
    expect(container.read(soundscapeProvider).playing, isTrue);
  });

  testWidgets('a late Undo keeps what was added after Clear', (tester) async {
    phone(tester);
    await pump(tester);
    await openMix(tester);
    final controller = container.read(soundscapeProvider.notifier);
    await tester.tap(find.byKey(const ValueKey('sounds_clear')));
    await tester.pumpAndSettle();
    controller.toggleSound('river');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(mix().layers.map((l) => l.soundId), ['river']);
  });

  testWidgets('the snackbar times out; it does not wait for Undo', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    await openMix(tester);
    await tester.tap(find.byKey(const ValueKey('sounds_clear')));
    await tester.pump();
    expect(find.text('Mix cleared'), findsOneWidget);
    // The entrance, then the default window, then the exit.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Mix cleared'), findsNothing);
  });

  testWidgets('Clear and Undo also work in the always-open wide panel', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester);
    expect(find.byKey(const ValueKey('sounds_mix_toggle')), findsNothing);
    final before = mix();
    await tester.tap(find.byKey(const ValueKey('sounds_clear')));
    await tester.pumpAndSettle();
    expect(mix().isEmpty, isTrue);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(mix().layers, before.layers);
  });

  testWidgets('a layer says what Swell does, beside its chip', (tester) async {
    phone(tester);
    await pump(tester);
    await openMix(tester);
    expect(find.text('Swell'), findsWidgets);
    expect(find.text('Rises and falls slowly'), findsWidgets);
    expect(find.text('Drift'), findsNothing);
  });

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
    // Presets are wide prints, so the second shows only in part: tap the
    // part that's on screen.
    final row = tester.getRect(
      find.byKey(const PageStorageKey('sounds_presets')),
    );
    await tester.tapAt(tester.getRect(night).intersect(row).center);
    await tester.pumpAndSettle();
    final state = container.read(soundscapeProvider);
    expect(state.playing, isTrue);
    expect(state.matchingPreset?.id, 'starter-night');
    expect(engine.playing.keys.toSet(), {'night-meadow', 'stream'});
    expect(
      find.descendant(
        of: night,
        matching: find.byIcon(Symbols.equalizer_rounded),
      ),
      findsOneWidget,
    );
  });

  testWidgets('presets and sounds look different, and tap differently', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    final preset = find.byKey(const ValueKey('preset_starter-night'));
    final sound = find.byKey(const ValueKey('sound_rain-car'));
    await tester.ensureVisible(preset);
    // A preset is a wide print: whose it is, its layers, and play.
    final print = tester.getSize(preset);
    expect(print.width / (print.height - kPresetStackDepth), closeTo(2, 0.01));
    expect(
      find.descendant(of: preset, matching: find.text('MEDITEJO')),
      findsOneWidget,
    );
    // Its loudest layer always shows; the next shows whole or as "+1".
    expect(
      find.descendant(of: preset, matching: find.text('Meadow at night')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: preset,
        matching: find.byWidgetPredicate(
          (w) => w is Text && (w.data == 'Mountain stream' || w.data == '+1'),
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: preset,
        matching: find.byIcon(Symbols.play_arrow_rounded),
      ),
      findsOneWidget,
    );

    // A sound is a square tile with a + while it's out of the mix.
    await tester.scrollUntilVisible(
      sound,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_library')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final tile = tester.getSize(sound);
    expect(tile.width, closeTo(tile.height, 0.5));
    expect(
      find.descendant(of: sound, matching: find.byIcon(Symbols.add_rounded)),
      findsOneWidget,
    );
    final before = {for (final l in mix().layers) l.soundId};

    // Tapping a sound adds one layer and keeps the rest; its + turns into a tick.
    await tester.tap(sound);
    await tester.pumpAndSettle();
    expect({for (final l in mix().layers) l.soundId}, {...before, 'rain-car'});
    expect(
      find.descendant(of: sound, matching: find.byIcon(Symbols.check_rounded)),
      findsOneWidget,
    );

    // Tapping a preset replaces the whole mix.
    await reveal(tester, preset, delta: -200);
    final row = tester.getRect(
      find.byKey(const PageStorageKey('sounds_presets')),
    );
    await tester.tapAt(tester.getRect(preset).intersect(row).center);
    await tester.pumpAndSettle();
    expect(
      {for (final l in mix().layers) l.soundId},
      {'night-meadow', 'stream'},
    );
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

    final swell = mix().layer(id)!.animate;
    await tester.tap(find.byKey(ValueKey('swell_$id')));
    await tester.pumpAndSettle();
    expect(mix().layer(id)!.animate, !swell);

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
    // Save waits for a name.
    await tester.pump();
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
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('preset_name_save')));
    await tester.pumpAndSettle();
    final id = container.read(soundscapeProvider).userPresets.single.id;
    // A built-in preset's menu pins it; it cannot be deleted.
    final builtIn = find.byKey(ValueKey('preset_menu_${starter.id}'));
    await revealPreset(tester, builtIn);
    await tester.tap(builtIn);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('preset_pin_${starter.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('preset_delete_${starter.id}')), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

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

  /// Opens the Sounds sheet over a page, as Home's tile does.
  Future<void> pumpSheet(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Map<String, Object> prefsValues = const {},
    Future<void> Function()? before,
  }) async {
    await pump(
      tester,
      locale: locale,
      prefsValues: prefsValues,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showSoundsSheet(context),
            child: const Text('open sounds'),
          ),
        ),
      ),
    );
    await before?.call();
    await tester.tap(find.text('open sounds'));
    await tester.pumpAndSettle();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sounds_chooser_done')));
    await tester.pumpAndSettle();
  }

  group('the sheet on your own mix', () {
    testWidgets('is the mixer in a bottom sheet, saying whose mix it is', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(SoundsView), findsOneWidget);
      expect(find.text('Your mix'), findsOneWidget);
      // Nothing plays until something is tapped.
      expect(container.read(soundscapeProvider).active, isFalse);
      expect(find.byKey(const ValueKey('sounds_back')), findsNothing);
    });

    testWidgets('a sound started in it plays on its own, and goes on after '
        'the sheet closes', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      final night = find.byKey(const ValueKey('preset_starter-night'));
      await revealPreset(tester, night);
      await tester.tap(night);
      await tester.pumpAndSettle();
      final night_ = kStarterPresets.firstWhere((p) => p.id == 'starter-night');
      expect(
        container.read(soundscapeProvider).owner,
        SoundscapeOwner.standalone,
      );
      expect(engine.playing.keys, night_.mix.layers.map((l) => l.soundId));

      await done(tester);
      expect(find.byType(SoundsView), findsNothing);
      final state = container.read(soundscapeProvider);
      expect(state.owner, SoundscapeOwner.standalone);
      expect(state.playing, isTrue);
      expect(state.mix, night_.mix);
      expect(engine.playing, isNotEmpty, reason: 'still sounding');
      expect(engine.paused, isFalse);

      // Opened again, it is the same mix, still playing; Stop stops it.
      await tester.tap(find.text('open sounds'));
      await tester.pumpAndSettle();
      expect(container.read(soundscapeProvider).playing, isTrue);
      expect(find.text('Night'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('sounds_stop')));
      await tester.pumpAndSettle();
      expect(container.read(soundscapeProvider).active, isFalse);
      expect(engine.playing, isEmpty);
    });

    testWidgets('a swipe down closes it like Done, and the sound goes on', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('sounds_play')));
      await tester.pumpAndSettle();
      await tester.fling(find.text('Sounds'), const Offset(0, 600), 2000);
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsNothing);
      expect(container.read(soundscapeProvider).playing, isTrue);
      expect(engine.playing, isNotEmpty);
    });

    testWidgets('back folds the open mix, then closes the sheet', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(tester);
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

    testWidgets('a double tap opens one sheet', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      final context = tester.element(find.text('open sounds'));
      unawaited(showSoundsSheet(context));
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsOneWidget);
      await done(tester);
      expect(find.byType(SoundsView), findsNothing);
    });

    testWidgets('a session that starts under it closes it, and takes the '
        'mixer', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('sounds_play')));
      await tester.pumpAndSettle();
      expect(
        container.read(soundscapeProvider).owner,
        SoundscapeOwner.standalone,
      );

      await container
          .read(soundscapeProvider.notifier)
          .startSession(SoundscapeSessionKind.practice);
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsNothing);
      // Practice plays nothing by default: the session silenced the mix.
      expect(container.read(soundscapeProvider).playing, isFalse);
      expect(
        container.read(soundscapeProvider).sessionKind,
        SoundscapeSessionKind.practice,
      );
    });
  });

  group('what plays under sessions', () {
    /// The "Plays under practice" / "Plays under talks" line.
    Finder line(SoundscapeSessionKind kind) =>
        find.byKey(ValueKey('under_${kind.name}'));

    /// What that line says under its title.
    String says(WidgetTester tester, SoundscapeSessionKind kind) => tester
        .widget<Text>(
          find.descendant(of: line(kind), matching: find.byType(Text)).at(1),
        )
        .data!;

    SoundscapeSessionDefault setting(SoundscapeSessionKind kind) =>
        container.read(soundscapeProvider).sessionDefault(kind);

    Finder sheetList(String key) => find
        .descendant(
          of: find.byKey(PageStorageKey<String>(key)),
          matching: find.byType(Scrollable),
        )
        .last;

    /// Turns the sheet to [kind]'s choice, from its line.
    Future<void> open(WidgetTester tester, SoundscapeSessionKind kind) async {
      await reveal(tester, line(kind));
      await tester.tap(line(kind));
      await tester.pumpAndSettle();
    }

    /// Back to the user's own mix, keeping the choice.
    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('sounds_back')));
      await tester.pumpAndSettle();
    }

    Future<void> tapPreset(WidgetTester tester, String id) async {
      final card = find.byKey(ValueKey('preset_$id'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: sheetList('sounds_presets'),
      );
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
    }

    Future<void> tapCard(WidgetTester tester, String id) async {
      final card = find.byKey(ValueKey('sound_$id'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: sheetList('sounds_library'),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 8 && card.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(sheetList('sounds_library'), const Offset(0, -80));
        await tester.pumpAndSettle();
      }
      await tester.tap(card.hitTestable());
      await tester.pumpAndSettle();
    }

    testWidgets('is one line each, starting at Off (decision 17)', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(tester);
      await reveal(tester, line(SoundscapeSessionKind.practice));
      // No switches: the line says what plays, and opens the chooser.
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Plays under practice'), findsOneWidget);
      expect(find.text('Plays under talks'), findsOneWidget);
      expect(says(tester, SoundscapeSessionKind.practice), 'Off');
      expect(says(tester, SoundscapeSessionKind.talks), 'Off');
      expect(setting(SoundscapeSessionKind.practice).enabled, isFalse);
    });

    testWidgets('a tap turns the same sheet to that choice, and what is left '
        'in it is what plays', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      // The same sheet, saying whose sound this is, back at its top.
      expect(find.byType(SoundsView), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Plays under practice'), findsOneWidget);
      expect(find.text('Your mix'), findsNothing);
      expect(find.text('Presets').hitTestable(), findsOneWidget);
      expect(line(SoundscapeSessionKind.talks), findsNothing);

      await tapPreset(tester, 'starter-night');
      expect(engine.playing, isNotEmpty, reason: 'heard as it is chosen');
      await back(tester);

      expect(find.byType(SoundsView), findsOneWidget);
      expect(find.text('Your mix'), findsOneWidget);
      expect(setting(SoundscapeSessionKind.practice).enabled, isTrue);
      expect(
        setting(SoundscapeSessionKind.practice).selection,
        const SoundscapeSelection.preset('starter-night'),
      );
      await reveal(tester, line(SoundscapeSessionKind.practice));
      expect(says(tester, SoundscapeSessionKind.practice), 'Night');
      // Your own mix is back, as it was, and nothing plays on.
      expect(mix(), starter.mix);
      expect(container.read(soundscapeProvider).playing, isFalse);
      expect(engine.playing, isEmpty);
    });

    testWidgets('your own mix, playing, is silenced while choosing and comes '
        'back after', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await tester.tap(find.byKey(const ValueKey('sounds_play')));
      await tester.pumpAndSettle();
      expect(engine.playing.keys, starter.mix.layers.map((l) => l.soundId));

      await open(tester, SoundscapeSessionKind.talks);
      expect(engine.playing, isEmpty, reason: 'silent until a sound is tapped');
      await tapPreset(tester, 'starter-shore');
      // Android's back also returns to your own mix.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsOneWidget);
      expect(find.byKey(const ValueKey('sounds_back')), findsNothing);

      final state = container.read(soundscapeProvider);
      expect(state.mix, starter.mix);
      expect(state.owner, SoundscapeOwner.standalone);
      expect(state.playing, isTrue);
      expect(engine.playing.keys, starter.mix.layers.map((l) => l.soundId));
      expect(
        setting(SoundscapeSessionKind.talks).selection,
        const SoundscapeSelection.preset('starter-shore'),
      );
    });

    testWidgets('talks keep their own choice; closing the sheet keeps it too', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.talks);
      expect(find.text('Plays under talks'), findsOneWidget);
      await tapPreset(tester, 'starter-shore');
      await done(tester);
      expect(find.byType(SoundsView), findsNothing);
      expect(
        setting(SoundscapeSessionKind.talks).selection,
        const SoundscapeSelection.preset('starter-shore'),
      );
      expect(
        setting(SoundscapeSessionKind.practice).enabled,
        isFalse,
        reason: 'practice is untouched',
      );
      // Chosen, not started: nothing plays on its own after the sheet.
      expect(container.read(soundscapeProvider).active, isFalse);
      expect(mix(), starter.mix);
      expect(engine.playing, isEmpty);
    });

    testWidgets('an existing choice from the old switches carries over', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(
        tester,
        prefsValues: {
          // What a user of 0.1.4 who switched "Play under practice" on and
          // chose Night in Customize has stored.
          'soundscape_session_defaults':
              '{"practice":{"enabled":true,"selection":"preset:starter-night",'
              '"volume":0.5},"talks":{"enabled":false,"selection":"mix",'
              '"volume":0.35}}',
          'soundscape_session_defaults_version': 2,
        },
      );
      await reveal(tester, line(SoundscapeSessionKind.practice));
      expect(says(tester, SoundscapeSessionKind.practice), 'Night');
      expect(says(tester, SoundscapeSessionKind.talks), 'Off');
    });

    testWidgets('Clear and its Undo (#67) work inside the sheet, above its '
        'dock', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      await tapPreset(tester, 'starter-night');
      final chosen = container.read(soundscapeProvider).mix;
      expect(chosen.isEmpty, isFalse);

      await tester.tap(find.byKey(const ValueKey('sounds_clear')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(container.read(soundscapeProvider).mix.isEmpty, isTrue);
      // The snackbar is in the sheet, over it, not behind it on the page,
      // and clear of the dock at its foot.
      final undo = find.widgetWithText(SnackBarAction, 'Undo');
      expect(undo.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.text('Mix cleared')).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('sounds_dock'))).top,
        ),
      );
      await tester.tap(undo);
      await tester.pumpAndSettle();
      expect(container.read(soundscapeProvider).mix, chosen);

      await done(tester);
      expect(
        setting(SoundscapeSessionKind.practice).selection,
        const SoundscapeSelection.preset('starter-night'),
      );
    });

    testWidgets('Done closes the sheet even with the mix panel open; '
        'back folds it first', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      await tapPreset(tester, 'starter-night');
      await openMix(tester);
      expect(
        find.byKey(const ValueKey('sounds_volume')),
        findsOneWidget,
        reason: 'the mix panel is open',
      );

      // Back folds the panel, and only then leaves the choice.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sounds_back')), findsOneWidget);
      expect(find.byKey(const ValueKey('sounds_volume')), findsNothing);

      // Done leaves whatever is open.
      await openMix(tester);
      await done(tester);
      expect(find.byType(SoundsView), findsNothing);
      expect(
        setting(SoundscapeSessionKind.practice).selection,
        const SoundscapeSelection.preset('starter-night'),
      );
    });

    testWidgets('a session that starts while choosing closes the sheet, '
        'and nothing is kept', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      await tapPreset(tester, 'starter-night');

      // Autoplay moves on, or a sit starts elsewhere.
      await container
          .read(soundscapeProvider.notifier)
          .startSession(SoundscapeSessionKind.talks);
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsNothing, reason: 'it left');
      expect(
        find.text('The session changed, so the sound was left as it was.'),
        findsOneWidget,
      );
      expect(setting(SoundscapeSessionKind.practice).enabled, isFalse);
      expect(
        container.read(soundscapeProvider).sessionKind,
        SoundscapeSessionKind.talks,
        reason: 'the session owns the mixer',
      );
    });

    testWidgets('a page pushed over the sheet stays when a session closes '
        'the sheet', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      // A deep link, or the player of the session about to start.
      unawaited(
        Navigator.of(
          tester.element(find.byKey(const ValueKey('sounds_chooser_done'))),
        ).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('a page over it')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container
          .read(soundscapeProvider.notifier)
          .startSession(SoundscapeSessionKind.practice);
      await tester.pumpAndSettle();
      expect(find.text('a page over it'), findsOneWidget, reason: 'it stays');
      expect(
        find.byType(SoundsView, skipOffstage: false),
        findsNothing,
        reason: 'the sheet was taken out from under the page',
      );
      expect(container.read(soundscapeProvider.notifier).auditioning, isFalse);
    });

    testWidgets('a session that ends while choosing closes the sheet too', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(
        tester,
        before: () async {
          final mixer = container.read(soundscapeProvider.notifier);
          mixer.setSessionDefault(
            SoundscapeSessionKind.practice,
            const SoundscapeSessionDefault(enabled: true),
          );
          await mixer.startSession(SoundscapeSessionKind.practice);
          await tester.pumpAndSettle();
        },
      );
      await open(tester, SoundscapeSessionKind.practice);
      await tapCard(tester, kSynthNoiseId);

      container.read(soundscapeProvider.notifier).endSession();
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsNothing);
      // Your own mix, silent; the noise was never kept anywhere.
      expect(mix(), starter.mix);
      expect(container.read(soundscapeProvider).active, isFalse);
      expect(
        setting(SoundscapeSessionKind.practice).selection,
        SoundscapeSelection.currentMix,
      );
    });

    testWidgets('chosen during a sit of that kind, it plays on under it', (
      tester,
    ) async {
      phone(tester);
      await pumpSheet(
        tester,
        before: () async {
          final mixer = container.read(soundscapeProvider.notifier);
          mixer.setSessionDefault(
            SoundscapeSessionKind.practice,
            const SoundscapeSessionDefault(enabled: true),
          );
          await mixer.startSession(SoundscapeSessionKind.practice);
          await tester.pumpAndSettle();
        },
      );

      await open(tester, SoundscapeSessionKind.practice);
      await tapPreset(tester, 'starter-night');
      final night = container.read(soundscapeProvider).mix;
      await done(tester);
      final state = container.read(soundscapeProvider);
      expect(state.owner, SoundscapeOwner.session);
      expect(state.mix, night, reason: 'the new choice, under the sit');
      expect(
        setting(SoundscapeSessionKind.practice).selection,
        const SoundscapeSelection.preset('starter-night'),
      );
    });

    testWidgets('a double tap on a line turns the sheet once', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await reveal(tester, line(SoundscapeSessionKind.practice));
      await tester.tap(line(SoundscapeSessionKind.practice));
      await tester.tap(
        line(SoundscapeSessionKind.practice),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SoundsView), findsOneWidget);
      expect(find.byKey(const ValueKey('sounds_back')), findsOneWidget);
      await back(tester);
      expect(find.byKey(const ValueKey('sounds_back')), findsNothing);
      expect(container.read(soundscapeProvider.notifier).auditioning, isFalse);
      await done(tester);
      expect(find.byType(SoundsView), findsNothing);
    });

    testWidgets('the dock\'s title wraps at 360 dp in German with large '
        'text', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 740)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpSheet(tester, locale: const Locale('de'));
      await open(tester, SoundscapeSessionKind.practice);
      expect(tester.takeException(), isNull);
      final title = tester.widget<Text>(find.text('Läuft bei Übungen').last);
      expect(title.maxLines, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a mix of layers is named by its sounds', (tester) async {
      phone(tester);
      await pumpSheet(tester);
      await open(tester, SoundscapeSessionKind.practice);
      // Two sounds that match no preset, on the same shelf.
      await tapCard(tester, kSynthNoiseId);
      await tapCard(tester, kSynthDroneId);
      await back(tester);
      expect(
        setting(SoundscapeSessionKind.practice).selection.kind,
        SoundscapeSelectionKind.layers,
      );
      await reveal(tester, line(SoundscapeSessionKind.practice));
      expect(says(tester, SoundscapeSessionKind.practice), 'Noise, Drone');
    });
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
    BinauralParams params() =>
        BinauralParams.fromJson(mix().layer(kSynthBinauralId)!.params);
    // The band chips set the beat (#71) ...
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('binaural_band_theta')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('binaural_band_alpha')));
    await tester.pumpAndSettle();
    expect(params().beatHz, 10);
    expect(find.text('8–13 Hz'), findsOneWidget);
    // ... and the wheel under them refines it within the band.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('binaural_beat')),
        matching: find.text('10.5 Hz'),
      ),
    );
    await tester.pumpAndSettle();
    expect(params().beatHz, 10.5);
    expect(engine.retuned.containsKey(kSynthBinauralId), isTrue);
  });

  testWidgets('noise editor: a colour commits to the layer, its bands kept', (
    tester,
  ) async {
    phone(tester);
    await pump(tester);
    final controller = container.read(soundscapeProvider.notifier)
      ..clearMix()
      ..toggleSound(kSynthNoiseId);
    await tester.pumpAndSettle();
    const curve = [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0];
    controller.setLayerParams(
      kSynthNoiseId,
      const NoiseParams(bands: curve).toJson(),
    );
    await tester.pumpAndSettle();
    await openMix(tester);
    await tester.tap(find.byKey(const ValueKey('adjust_synth-noise')));
    await tester.pumpAndSettle();
    // The bands are folded away, whatever they hold; no shape chips.
    expect(find.byKey(const ValueKey('noise_band_0')), findsNothing);
    expect(find.byKey(const ValueKey('noise_bands_fold')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('noise_colour_brown')));
    await tester.pumpAndSettle();
    final params = NoiseParams.fromJson(mix().layer(kSynthNoiseId)!.params);
    expect(params.colour, NoiseColour.brown);
    expect(params.bands, curve);
    expect(engine.retuned.containsKey(kSynthNoiseId), isTrue);
  });

  testWidgets('noise editor: Reset, inside the opened Equaliser, flattens '
      'the bands and hides itself', (tester) async {
    phone(tester);
    await pump(tester);
    final controller = container.read(soundscapeProvider.notifier)
      ..clearMix()
      ..toggleSound(kSynthNoiseId);
    await tester.pumpAndSettle();
    await openMix(tester);
    await tester.tap(find.byKey(const ValueKey('adjust_synth-noise')));
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('noise_bands_reset'));
    // Folded: no Reset. Opened on flat bands: still none.
    expect(reset, findsNothing);
    await tester.tap(find.byKey(const ValueKey('noise_bands_fold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('noise_band_0')), findsOneWidget);
    expect(reset, findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('noise_bands_fold')), findsNothing);

    // With a shaped spectrum (and a colour, which Reset leaves alone).
    const curve = [0.0, 0.2, 0.4, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5, 0.5];
    controller.setLayerParams(
      kSynthNoiseId,
      const NoiseParams(colour: NoiseColour.brown, bands: curve).toJson(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('adjust_synth-noise')));
    await tester.pumpAndSettle();
    expect(reset, findsNothing, reason: 'inside the fold');
    await tester.tap(find.byKey(const ValueKey('noise_bands_fold')));
    await tester.pumpAndSettle();
    expect(reset, findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(reset);
    await tester.pumpAndSettle();
    final params = NoiseParams.fromJson(mix().layer(kSynthNoiseId)!.params);
    expect(params.bands, NoiseParams.flat);
    expect(params.colour, NoiseColour.brown);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('noise_band_0'))).value,
      1.0,
    );
    expect(reset, findsNothing, reason: 'nothing left to reset');
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
      (kSynthNoiseId, 'noise_bands_fold'),
      (kSynthDroneId, 'drone_movement'),
      (kSynthBinauralId, 'binaural_carrier'),
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

  group('the library grid', () {
    /// How many cards the fullest row on screen holds. (The first shelf has
    /// only the three generated sounds, so its row can't show the grid's
    /// width.)
    Future<int> columns(WidgetTester tester) async {
      final library = await container.read(soundLibraryProvider.future);
      final rows = <int, int>{};
      for (final id in [...kSynthIds, for (final s in library.sounds) s.id]) {
        final card = find.byKey(ValueKey('sound_$id'));
        if (card.evaluate().isEmpty) continue;
        final row = tester.getTopLeft(card).dy.round();
        rows[row] = (rows[row] ?? 0) + 1;
      }
      return rows.values.reduce((a, b) => a > b ? a : b);
    }

    Future<void> sized(WidgetTester tester, Size size, double scale) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester);
    }

    for (final (size, scale, across) in [
      (const Size(360, 740), 1.0, 3),
      (const Size(360, 740), 1.3, 3),
      (const Size(412, 915), 1.0, 3),
      // Beyond 1.3x titles would break mid-word at 101 dp, so a 360 dp phone
      // trades a column for room.
      (const Size(360, 740), 2.0, 2),
    ]) {
      testWidgets('$across across at ${size.width.toInt()} dp, ${scale}x text, '
          'with every card laid out without overflow', (tester) async {
        await sized(tester, size, scale);
        expect(await columns(tester), across);
        expect(tester.takeException(), isNull);

        // Scroll the whole library past, so every shelf's cards are laid
        // out, and a card with a long title can't hide an overflow.
        final list = find
            .descendant(
              of: find.byKey(const PageStorageKey('sounds_library')),
              matching: find.byType(Scrollable),
            )
            .first;
        for (var i = 0; i < 40; i++) {
          await tester.drag(list, const Offset(0, -400));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'page $i');
        }
      });
    }

    testWidgets('keeps the card tap target and the selected tick in view', (
      tester,
    ) async {
      await sized(tester, const Size(360, 740), 1.3);
      final card = find.byKey(const ValueKey('sound_synth-noise'));
      expect(tester.getSize(card).width, greaterThan(96));
      expect(tester.getSize(card).width, lessThan(110));
      // Selected: the tick sits inside the card's right edge.
      container.read(soundscapeProvider.notifier).clearMix();
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      final tick = find.descendant(
        of: card,
        matching: find.byIcon(Symbols.check_rounded),
      );
      expect(tick, findsOneWidget);
      expect(
        tester.getTopRight(tick).dx,
        lessThanOrEqualTo(tester.getTopRight(card).dx),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('wide windows take more columns, as before', (tester) async {
      await sized(tester, const Size(1280, 900), 1.0);
      expect(await columns(tester), greaterThan(3));
    });
  });

  testWidgets('is localised', (tester) async {
    phone(tester);
    await pump(tester, locale: const Locale('de'));
    expect(find.text('Dein Mix'), findsOneWidget);
    expect(find.text('Regen im Wald'), findsWidgets);
  });

  testWidgets('credits are one tap away and list every sound', (tester) async {
    phone(tester);
    await pump(tester);
    // From the foot of the library.
    final footer = find.byKey(const ValueKey('sound_credits_footer'));
    await reveal(tester, footer);
    await tester.tap(footer);
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
    expect(find.byType(SoundsView), findsOneWidget);
  });
}
