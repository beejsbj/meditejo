import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/cues/custom_bell_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/services/bells/bell_recipes.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/bells/custom_bell_store.dart';
import 'package:medito/views/cues/bell_maker_view.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// Records what is rung, without a platform player.
class _Preview extends SessionBellPreview {
  final played = <String>[];
  final files = <String>[];
  int stops = 0;

  @override
  Future<void> play(double volume, {String asset = kSessionBellAsset}) async =>
      played.add(asset);

  @override
  Future<void> playFile(String path, double volume) async => files.add(path);

  @override
  Future<void> stop() async => stops++;
}

late Directory _dir;
late _Preview _preview;
late List<BellSpec> _renders;
late SharedPreferences _prefs;
late ProviderContainer _container;

/// The sound is the spec's key as bytes: quick, and tells which spec it was.
Future<Uint8List> _render(BellSpec spec) async {
  _renders.add(spec);
  return Uint8List.fromList(spec.key.codeUnits);
}

/// Lets the frames of a route or dialog play out. (The art keeps asking for
/// frames while it loads, so `pumpAndSettle` would never see a quiet tree.)
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Lets real file work finish: the fake clock does not run it, and what it
/// finishes schedules more work on the fake one, so the two take turns. With
/// [until], it stops as soon as that is true and fails if it never is, rather
/// than trusting a fixed delay on a slow machine.
Future<void> _io(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (until != null && until()) return;
    if (until == null && i >= 24) return;
  }
  fail('the file work never finished');
}

Future<void> _setUp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(420, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  _prefs = await SharedPreferences.getInstance();
  _dir = Directory.systemTemp.createTempSync('bellmaker');
  addTearDown(() => _dir.deleteSync(recursive: true));
  _preview = _Preview();
  _renders = [];
  _container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_prefs),
      customBellStoreProvider.overrideWithValue(
        CustomBellStore(_prefs, directory: () async => _dir, render: _render),
      ),
      sessionBellPreviewProvider.overrideWithValue(_preview),
      bellRendererProvider.overrideWithValue(_render),
      bellPreviewFileProvider.overrideWithValue(
        () async => File('${_dir.path}/p/preview.wav'),
      ),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
    ],
  );
  addTearDown(_container.dispose);
}

Widget _app(Widget home) => UncontrolledProviderScope(
  container: _container,
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Slider _slider(WidgetTester tester, String name) =>
    tester.widget<Slider>(find.byKey(ValueKey('bell_maker_$name')));

/// Moves a control and lets go; waits for the bell to have rung [rings] times.
Future<void> _release(
  WidgetTester tester,
  String name,
  double at, {
  required int rings,
}) async {
  final slider = _slider(tester, name);
  slider.onChanged!(at);
  await tester.pump();
  slider.onChangeEnd!(at);
  await _io(tester, until: () => _preview.files.length >= rings);
}

void main() {
  const temple = 'assets/audio/bell_temple.wav';

  testWidgets('starts from the bell the cue rings, with its controls', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_app(const BellMakerView(from: temple)));
    await tester.pump();
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('bell_maker_start_temple')),
    );
    expect(chip.selected, isTrue);
    expect(find.text('Make a bell'), findsOneWidget);
    expect(find.text('196 Hz'), findsOneWidget);
    expect(find.text('3.2 s'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bell_maker_name')))
          .controller!
          .text,
      'My bell',
    );
    // Nothing is made or rung until asked.
    expect(_renders, isEmpty);
    expect(_preview.files, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('anything but a bell starts from the singing bowl', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_app(const BellMakerView(from: '')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('bell_maker_start_bowl_medium')),
          )
          .selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('choosing a bell to start from sets its controls and rings it', (
    tester,
  ) async {
    await _setUp(tester);
    await tester.pumpWidget(_app(const BellMakerView(from: temple)));
    await tester.pump();
    final chip = find.byKey(const ValueKey('bell_maker_start_gong'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await _io(tester, until: () => _preview.files.isNotEmpty);
    expect(_renders.single.preset, 'gong');
    expect(_renders.single.knobs, bellRecipes['gong']!.knobs);
    expect(_preview.files, ['${_dir.path}/p/preview.wav']);
    expect(find.text('118 Hz'), findsOneWidget);
    expect(
      File('${_dir.path}/p/preview.wav').readAsBytesSync(),
      _renders.single.key.codeUnits,
      reason: 'the file rung is the sound made',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'letting go of a control makes and rings that bell, once per sound',
    (tester) async {
      await _setUp(tester);
      await tester.pumpWidget(_app(const BellMakerView(from: temple)));
      await tester.pump();
      await _release(tester, 'strike', 0.9, rings: 1);
      expect(_renders, hasLength(1));
      expect(_renders.single.knobs.strike, closeTo(0.9, 1e-9));
      expect(
        _renders.single.knobs.pitch,
        closeTo(196, 1e-6),
        reason: 'only the strike moved',
      );
      expect(_preview.files, hasLength(1));
      // Tapping the bell rings it again, without making it again.
      await tester.tap(find.byKey(const ValueKey('bell_maker_figure')));
      await _io(tester, until: () => _preview.files.length >= 2);
      expect(_renders, hasLength(1));
      expect(_preview.files, hasLength(2));
      // A control moved to somewhere new makes a new sound.
      await _release(tester, 'ring', 0.2, rings: 3);
      expect(_renders, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Save needs a name, keeps the sound heard and returns the bell', (
    tester,
  ) async {
    await _setUp(tester);
    CustomBell? result;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showBellMaker(context, from: temple),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    FilledButton save() => tester.widget<FilledButton>(
      find.byKey(const ValueKey('bell_maker_save')),
    );
    expect(save().onPressed, isNotNull, reason: 'a name is suggested');
    await tester.enterText(
      find.byKey(const ValueKey('bell_maker_name')),
      '   ',
    );
    await tester.pump();
    expect(save().onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('bell_maker_name')),
      'Morning bowl',
    );
    await tester.pump();
    await _release(tester, 'bright', 0.7, rings: 1);
    expect(_renders, hasLength(1));
    save().onPressed!();
    await _io(tester, until: () => result != null);
    await _settle(tester);
    expect(result?.name, 'Morning bowl');
    expect(result?.preset, 'temple');
    expect(result?.knobs.bright, closeTo(0.7, 1e-9));
    expect(_renders, hasLength(1), reason: 'the sound heard is the one kept');
    final path = await tester.runAsync(
      () => _container.read(customBellStoreProvider).fileFor(result!.id),
    );
    expect(File(path!).readAsBytesSync(), _renders.single.key.codeUnits);
    expect(_container.read(customBellsProvider).single.id, result!.id);
    expect(find.byType(BellMakerView), findsNothing);
  });

  testWidgets('closing without saving keeps nothing', (tester) async {
    await _setUp(tester);
    CustomBell? result = CustomBell(
      id: 'custom-bell:placeholder1',
      name: 'x',
      preset: 'gong',
      knobs: bellRecipes['gong']!.knobs,
      createdAtMs: 0,
    );
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showBellMaker(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Close'));
    await _settle(tester);
    expect(result, isNull);
    expect(_container.read(customBellsProvider), isEmpty);
    expect(_preview.stops, greaterThan(0), reason: 'nothing rings on');
  });

  group('in the Customize bell picker', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      await _setUp(tester);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: CustomizeSheet(
              scope: const CueScope(CueKind.practice),
              audioDurationMs: 20 * 60000,
              clock: () => DateTime(2026, 1, 1, 9, 0),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> open(WidgetTester tester, String row) async {
      final finder = find.text(row).first;
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await _settle(tester);
    }

    Future<CustomBell> keep(String name) => _container
        .read(customBellsProvider.notifier)
        .save(name: name, spec: BellSpec.preset('bowl_deep'));

    testWidgets('a saved bell is listed, picked per cue and rung', (
      tester,
    ) async {
      await pumpSheet(tester);
      final bell = (await tester.runAsync(() => keep('Evening')))!;
      await tester.pump();
      await open(tester, 'Ending bell');
      expect(find.text('Your bells'), findsOneWidget);
      expect(find.byKey(ValueKey('bell_icon_${bell.id}')), findsOneWidget);
      final row = find.byKey(ValueKey('bell_row_${bell.id}'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await _settle(tester);
      const scope = CueScope(CueKind.practice);
      expect(_container.read(cueSettingsProvider(scope)).endSound, bell.id);
      expect(
        _container.read(cueSettingsProvider(scope)).startSound,
        kSessionBellAsset,
      );
      expect(_preview.played.last, bell.id);
      // The row says which bell it rings, by name.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('customize_endBell')),
          matching: find.text('Evening'),
        ),
        findsWidgets,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a bell can be renamed, and keeps its id in the cues', (
      tester,
    ) async {
      await pumpSheet(tester);
      final bell = (await tester.runAsync(() => keep('Evening')))!;
      await tester.pump();
      await open(tester, 'Starting bell');
      await tester.tap(find.byKey(ValueKey('bell_row_${bell.id}')));
      await _settle(tester);
      await tester.tap(find.byKey(ValueKey('bell_menu_${bell.id}')));
      await _settle(tester);
      await tester.tap(find.text('Rename'));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('bell_rename_field')),
        'Dawn',
      );
      await tester.tap(find.byKey(const ValueKey('bell_rename_confirm')));
      await _io(
        tester,
        until: () => _container.read(customBellsProvider).single.name == 'Dawn',
      );
      await _settle(tester);
      expect(_container.read(customBellsProvider).single.name, 'Dawn');
      expect(_container.read(customBellsProvider).single.id, bell.id);
      expect(
        _container
            .read(cueSettingsProvider(const CueScope(CueKind.practice)))
            .startSound,
        bell.id,
      );
      expect(find.text('Dawn'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'deleting a bell asks first, and its cues go back to the default',
      (tester) async {
        await pumpSheet(tester);
        final bell = (await tester.runAsync(() => keep('Evening')))!;
        final path = (await tester.runAsync(
          () => _container.read(customBellStoreProvider).fileFor(bell.id),
        ))!;
        await tester.pump();
        await open(tester, 'Starting bell');
        await tester.tap(find.byKey(ValueKey('bell_row_${bell.id}')));
        await _settle(tester);
        const scope = CueScope(CueKind.practice);
        expect(_container.read(cueSettingsProvider(scope)).startSound, bell.id);
        // The end cue rings it too: deleting from the start list moves both.
        await _container
            .read(cueSettingsProvider(scope).notifier)
            .update(
              _container
                  .read(cueSettingsProvider(scope))
                  .copyWith(endSound: bell.id),
            );
        await tester.pump();
        await tester.tap(find.byKey(ValueKey('bell_menu_${bell.id}')));
        await _settle(tester);
        await tester.tap(find.text('Delete'));
        await _settle(tester);
        // Asked first; cancelling keeps it.
        expect(find.text('Delete “Evening”?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await _settle(tester);
        expect(_container.read(customBellsProvider), hasLength(1));
        await tester.tap(find.byKey(ValueKey('bell_menu_${bell.id}')));
        await _settle(tester);
        await tester.tap(find.text('Delete'));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('bell_delete_confirm')));
        await _io(
          tester,
          until: () => _container.read(customBellsProvider).isEmpty,
        );
        await _settle(tester);
        expect(_container.read(customBellsProvider), isEmpty);
        expect(File(path).existsSync(), isFalse);
        expect(
          _container.read(cueSettingsProvider(scope)).startSound,
          kSessionBellAsset,
        );
        expect(
          _container.read(cueSettingsProvider(scope)).endSound,
          kSessionBellAsset,
        );
        expect(find.text('Your bells'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('Make a bell opens the maker from the bell the cue rings', (
      tester,
    ) async {
      await pumpSheet(tester);
      await open(tester, 'Ending bell');
      final row = find.byKey(const ValueKey('bell_row_make'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await _settle(tester);
      expect(find.byType(BellMakerView), findsOneWidget);
      // The cue rang the swell bell, so that is where the maker starts.
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('bell_maker_start_swell')),
            )
            .selected,
        isTrue,
      );
      // Saving returns to the picker with the new bell chosen.
      await tester.tap(find.byKey(const ValueKey('bell_maker_save')));
      await _io(
        tester,
        until: () => _container.read(customBellsProvider).isNotEmpty,
      );
      await _settle(tester);
      final made = _container.read(customBellsProvider).single;
      expect(find.byType(BellMakerView), findsNothing);
      expect(
        _container
            .read(cueSettingsProvider(const CueScope(CueKind.practice)))
            .endSound,
        made.id,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a cue that names a bell that is gone shows the default', (
      tester,
    ) async {
      await pumpSheet(tester);
      const scope = CueScope(CueKind.practice);
      await _container
          .read(cueSettingsProvider(scope).notifier)
          .update(
            _container
                .read(cueSettingsProvider(scope))
                .copyWith(endSound: 'custom-bell:gone123456'),
          );
      await tester.pump();
      await open(tester, 'Ending bell');
      // What rings is the default bell, so that is the row that is ticked.
      expect(
        find.descendant(
          of: find.byKey(ValueKey('bell_row_$cueDefaultBell')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
