import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/no_hearts.dart';

PackModel _pack(String id) => PackModel(
  id: id,
  title: 'Course $id',
  items: [
    for (var i = 0; i < 4; i++)
      PackItemsModel(
        type: 'track',
        id: '$id-$i',
        title: 'Session $i',
        path: '/tracks/$id-$i',
        isCompleted: i == 0,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) =>
      AsyncData(_pack(packId));
}

class _FakeTracks extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => Track(
    id: trackId,
    title: 'Talk $trackId',
    subtitle: 'Talk · Ajahn Sucitto · 42 min',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: false,
    voices: const [
      TrackVoice(
        audioFiles: [TrackAudioFile(id: 'f', path: 'f.mp3', duration: 1)],
      ),
    ],
  );
}

const _courses = ['c1', 'c2', 'c3', 'c4'];
const _talks = ['t1'];

List<Override> get _overrides => [
  continueItemsProvider.overrideWith((ref) async => []),
  for (final id in _courses)
    packProvider(packId: id).overrideWith(_FakePack.new),
  for (final id in _talks)
    tracksProvider(trackId: id).overrideWith(_FakeTracks.new),
];

Future<LibraryTestApp> _pumpHome(
  WidgetTester tester,
  List<String> pins, {
  List<String> sessions = const [],
}) async {
  final app = await LibraryTestApp.create(tester);
  await app.prefs.setStringList(
    SharedPreferenceConstants.pinnedCourseIds,
    pins,
  );
  await app.prefs.setStringList(
    SharedPreferenceConstants.pinnedSessionIds,
    sessions,
  );
  await app.pump(tester, const HomeView(), overrides: _overrides);
  return app;
}

final _seeAll = find.byKey(const ValueKey('pinned_see_all'));

class _GoneTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async =>
      throw StateError('gone');
}

Future<void> _pumpGone(WidgetTester tester, {String? savedTitle}) async {
  final app = await LibraryTestApp.create(tester);
  await app.prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
    'ds-talk-gone',
  ]);
  await app.prefs.setStringList(SharedPreferenceConstants.pinnedSessionIds, [
    'ds-talk-gone',
  ]);
  if (savedTitle != null) {
    await app.prefs.setString(
      SharedPreferenceConstants.pinnedTitles,
      jsonEncode({'ds-talk-gone': savedTitle}),
    );
  }
  await app.pump(
    tester,
    const PinnedListView(),
    overrides: [
      tracksProvider(trackId: 'ds-talk-gone').overrideWith(_GoneTrack.new),
    ],
  );
}

void main() {
  testWidgets('Home shows three pins and no See all when that is all', (
    tester,
  ) async {
    await _pumpHome(tester, ['c1', 'c2', 'c3']);
    expect(find.byType(PinnedTile), findsNWidgets(3));
    expect(_seeAll, findsNothing);
  });

  testWidgets('more than three: Home shows the first three, then See all', (
    tester,
  ) async {
    await _pumpHome(tester, ['c1', 't1', 'c2', 'c3', 'c4'], sessions: ['t1']);
    expect(find.byType(PinnedTile), findsNWidgets(3));
    expectNoHearts();
    for (final id in ['c1', 't1', 'c2']) {
      expect(find.byKey(ValueKey('pinned_$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const ValueKey('pinned_c3')), findsNothing);
    // The pinned session reads as one: its title and what it is.
    expect(find.byType(PinnedSessionTile), findsOneWidget);
    expect(find.text('Talk t1'), findsOneWidget);
    expect(find.text('Talk · Ajahn Sucitto · 42 min'), findsOneWidget);

    // Under a mark this large, See all starts below the fold.
    await tester.ensureVisible(_seeAll);
    await tester.pump();
    expect(find.text('See all 5'), findsOneWidget);
    await tester.tap(_seeAll);
    await DharmaSeedTestApp.settle(tester);

    expect(find.byType(PinnedListView), findsOneWidget);
    expectNoHearts();
    final list = find.byKey(const ValueKey('pinned_list'));
    for (final id in ['c1', 't1', 'c2', 'c3', 'c4']) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('pinned_$id')),
        200,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.byKey(ValueKey('pinned_$id')), findsOneWidget, reason: id);
    }
  });

  testWidgets('a pinned session opens its page', (tester) async {
    await _pumpHome(tester, ['t1'], sessions: ['t1']);
    await tester.tap(find.text('Talk t1'));
    await DharmaSeedTestApp.settle(tester);
    expect(find.byType(TrackView), findsOneWidget);
  });

  testWidgets('unpinning in the list takes it off, with Undo', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, [
      'c1',
      't1',
    ]);
    await app.prefs.setStringList(SharedPreferenceConstants.pinnedSessionIds, [
      't1',
    ]);
    await app.pump(tester, const PinnedListView(), overrides: _overrides);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PinnedListView)),
    );

    await tester.tap(find.byTooltip('More options for Talk t1'));
    await DharmaSeedTestApp.settle(tester);
    await tester.tap(find.byKey(const ValueKey('pinned_menu_unpin')));
    await DharmaSeedTestApp.settle(tester);
    expect(container.read(pinnedCoursesProvider), ['c1']);
    expect(find.byType(PinnedSessionTile), findsNothing);

    await tester.tap(find.text('Undo'));
    await DharmaSeedTestApp.settle(tester);
    expect(container.read(pinnedCoursesProvider), ['c1', 't1']);
    expect(
      container.read(pinnedCoursesProvider.notifier).isSession('t1'),
      isTrue,
    );
  });

  testWidgets('a pinned session whose track is gone says Unavailable', (
    tester,
  ) async {
    await _pumpGone(tester);
    expect(find.text('ds-talk-gone'), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);
    // It can still be unpinned, but not played.
    await tester.tap(find.byTooltip('More options for Unavailable'));
    await DharmaSeedTestApp.settle(tester);
    expect(find.byKey(const ValueKey('pinned_menu_unpin')), findsOneWidget);
    expect(find.byKey(const ValueKey('pinned_menu_play')), findsNothing);
  });

  testWidgets('a gone session keeps the title it was saved with', (
    tester,
  ) async {
    await _pumpGone(tester, savedTitle: 'Metta for a difficult person');
    expect(find.text('Metta for a difficult person'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('ds-talk-gone'), findsNothing);
  });

  testWidgets('the list says how to pin when nothing is', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(tester, const PinnedListView(), overrides: _overrides);
    expect(find.byKey(const ValueKey('pinned_list_empty')), findsOneWidget);
    expect(find.text('Nothing pinned yet'), findsOneWidget);
  });
}
