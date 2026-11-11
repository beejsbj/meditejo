import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/soundscape_fakes.dart';

const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _heart = 'assets/audio/pulse_heartbeat.wav';
const _river = SoundMix([SoundLayer(soundId: 'river', volume: 0.6)]);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(
    PackModel(
      id: packId,
      title: 'Course $packId',
      items: [
        PackItemsModel(
          type: 'track',
          id: '$packId-0',
          title: 'Session',
          path: '/tracks/$packId-0',
        ),
      ],
    ),
  );
}

/// Six presets of the user's, each holding something different.
List<Preset> _six() => [
  Preset(
    id: 'user-1',
    name: 'Morning sit',
    slots: PresetSlots(
      sound: _river,
      bells: PresetCues.bells(const CueSettings(startSound: _bowl)),
      length: const PresetLength.minutes(20),
    ),
  ),
  const Preset(
    id: 'user-2',
    name: 'Open sit',
    slots: PresetSlots(length: PresetLength.openEnded()),
  ),
  Preset.sound(id: 'user-3', name: 'River', mix: _river),
  Preset(
    id: 'user-4',
    name: 'Walking',
    slots: PresetSlots(
      rhythm: PresetCues.rhythm(const CueSettings(pulseSound: _heart)),
      length: const PresetLength.minutes(90),
    ),
  ),
  Preset.sound(id: 'user-5', name: 'Fifth', mix: _river),
  Preset.sound(id: 'user-6', name: 'Sixth', mix: _river),
];

Finder _tile(String id) => find.byKey(ValueKey('pinned_preset_$id'));
final _seeAll = find.byKey(const ValueKey('pinned_see_all'));

Future<LibraryTestApp> _pumpHome(
  WidgetTester tester, {
  List<Preset> presets = const [],
  List<String> pinned = const [],
  List<String> courses = const [],
}) async {
  final app = await LibraryTestApp.create(tester);
  SoundscapeStore(app.prefs)
    ..writePresets(presets)
    ..writePinnedPresets(pinned);
  await app.prefs.setStringList(
    SharedPreferenceConstants.pinnedCourseIds,
    courses,
  );
  await app.pump(
    tester,
    const HomeView(),
    overrides: <Override>[
      continueItemsProvider.overrideWith((ref) async => []),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      for (final id in courses)
        packProvider(packId: id).overrideWith(_FakePack.new),
    ],
  );
  return app;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HomeView)));

void main() {
  testWidgets('with nothing pinned Home has the Timer and Sounds, and no '
      'preset tile by itself', (tester) async {
    await _pumpHome(tester, presets: _six());
    expect(find.byKey(const ValueKey('shortcut_timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut_sounds')), findsOneWidget);
    expect(find.byType(PinnedPresetTile), findsNothing);
    expect(find.byType(PinnedSection), findsOneWidget);
    expect(_seeAll, findsNothing);
  });

  testWidgets('a preset is on Home because it is pinned: its tile says how '
      'long it runs and what it rings', (tester) async {
    await _pumpHome(tester, presets: _six(), pinned: ['user-1', 'user-2']);
    expect(find.byType(PinnedPresetTile), findsNWidgets(2));
    expect(
      find.descendant(of: _tile('user-1'), matching: find.text('Morning sit')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tile('user-1'),
        matching: find.text('20 min · Singing bowl'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _tile('user-2'), matching: find.text('∞')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Start Morning sit, 20 min · Singing bowl'),
      findsOneWidget,
    );
    // Not pinned, not on Home.
    expect(_tile('user-3'), findsNothing);
    expect(_seeAll, findsNothing);
  });

  testWidgets('a sound-only preset runs as long as the Timer is set', (
    tester,
  ) async {
    await _pumpHome(tester, presets: _six(), pinned: ['user-3']);
    expect(
      find.descendant(of: _tile('user-3'), matching: find.text('10 min')),
      findsOneWidget,
    );
  });

  testWidgets('Home shows four preset tiles and the pinned courses under '
      'them; the rest are behind See all, which counts everything', (
    tester,
  ) async {
    final pinned = [for (final p in _six()) p.id];
    await _pumpHome(
      tester,
      presets: _six(),
      pinned: pinned,
      courses: ['c1', 'c2'],
    );
    expect(find.byType(PinnedPresetTile), findsNWidgets(4));
    for (final id in pinned.take(4)) {
      expect(_tile(id), findsOneWidget);
    }
    expect(_tile('user-5'), findsNothing);
    expect(find.byType(PinnedCourseTile), findsNWidgets(2));
    // Presets first, in two columns, then the cards.
    final first = tester.getRect(_tile('user-1'));
    final second = tester.getRect(_tile('user-2'));
    final third = tester.getRect(_tile('user-3'));
    expect(second.top, first.top);
    expect(second.left, greaterThan(first.right));
    expect(third.top, greaterThan(first.bottom));
    expect(
      tester.getRect(find.byType(PinnedCourseTile).first).top,
      greaterThan(third.bottom),
    );
    await tester.ensureVisible(_seeAll);
    await settle(tester);
    expect(
      find.descendant(of: _seeAll, matching: find.text('See all 8')),
      findsOneWidget,
    );

    await tester.tap(_seeAll);
    await settle(tester);
    expect(find.byType(PinnedListView), findsOneWidget);
    final list = find.byType(PinnedListView);
    expect(
      find.descendant(of: list, matching: find.byType(PinnedPresetTile)),
      findsNWidgets(6),
    );
    expect(
      find.descendant(of: list, matching: find.byType(PinnedCourseTile)),
      findsNWidgets(2),
    );
  });

  testWidgets('holding a tile offers Unpin, with the pin and words a course '
      'has; Undo puts it back where it was', (tester) async {
    final app = await _pumpHome(
      tester,
      presets: _six(),
      pinned: ['user-1', 'user-2', 'user-3'],
    );
    await tester.ensureVisible(_tile('user-2'));
    await settle(tester);
    await tester.longPress(_tile('user-2'));
    await settle(tester);
    final unpin = find.byKey(const ValueKey('pinned_menu_unpin'));
    expect(
      find.descendant(of: unpin, matching: find.text('Unpin from Home')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: unpin,
        matching: find.byIcon(Icons.push_pin_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(unpin);
    await settle(tester);
    expect(_tile('user-2'), findsNothing);
    expect(_container(tester).read(pinnedPresetIdsProvider), [
      'user-1',
      'user-3',
    ]);
    // The preset itself is still there.
    expect(
      SoundscapeStore(app.prefs).readPresets().map((p) => p.id),
      contains('user-2'),
    );
    expect(find.text('Unpinned from Home'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(_container(tester).read(pinnedPresetIdsProvider), [
      'user-1',
      'user-2',
      'user-3',
    ]);
    expect(_tile('user-2'), findsOneWidget);
  });

  testWidgets('a pin whose preset was deleted leaves no tile', (tester) async {
    await _pumpHome(tester, presets: _six(), pinned: ['user-gone', 'user-1']);
    expect(find.byType(PinnedPresetTile), findsOneWidget);
    deletePreset(_container(tester), 'user-1');
    await settle(tester);
    expect(find.byType(PinnedPresetTile), findsNothing);
  });
}

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);
