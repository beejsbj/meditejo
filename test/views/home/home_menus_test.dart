import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/widgets/cards/card_actions.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

const _pack = PackModel(
  id: 'lib-course-a',
  title: 'Course A',
  items: [
    PackItemsModel(
      type: 'track',
      id: 'lib-track-1',
      title: 'One',
      path: '/tracks/lib-track-1',
      isCompleted: true,
    ),
    PackItemsModel(
      type: 'track',
      id: 'lib-track-2',
      title: 'Two',
      path: '/tracks/lib-track-2',
      isCompleted: false,
    ),
  ],
);

ContinueItem _item(String id, {bool resume = true}) => ContinueItem(
  trackId: id,
  path: '/tracks/$id',
  title: 'Title $id',
  group: LibraryGroup.practice,
  lastPlayed: DateTime(2026, 10, 19),
  courseId: 'lib-course-a',
  courseTitle: 'Course A',
  resume: resume
      ? const ResumePoint(positionMs: 120000, durationMs: 600000)
      : null,
  sessionNumber: 4,
  sessionTotal: 32,
);

var _gate = Completer<void>();
final _prepared = <PlaybackRequest>[];

Track _track(String id) => Track(
  id: id,
  title: 'Title $id',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: true,
  voices: [
    TrackVoice(
      audioFiles: [
        TrackAudioFile(id: 'f-$id', path: 'a.mp3', duration: 600000),
      ],
    ),
  ],
);

class _OneFileTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => _track(trackId);
}

class _GatedTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async {
    await _gate.future;
    return _track(trackId);
  }
}

/// Two voices: nothing picks one, so the track page opens.
class _TwoVoiceTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async {
    final base = _track(trackId);
    return Track(
      id: base.id,
      title: base.title,
      description: '',
      coverUrl: '',
      isPublished: true,
      hasBackgroundSound: true,
      voices: [
        for (final name in ['Ana', 'Ben'])
          TrackVoice(
            guideName: name,
            audioFiles: [
              TrackAudioFile(id: 'f-$name', path: 'a.mp3', duration: 600000),
            ],
          ),
      ],
    );
  }
}

class _FailingTrack extends Tracks {
  @override
  Future<Track> build({required String trackId}) async =>
      throw StateError('offline');
}

/// Records what the session is prepared with; no player is started.
class _RecordingPlayer extends PlayerProvider {
  @override
  void prepare(PlaybackRequest request) => _prepared.add(request);
}

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) =>
      const AsyncData(_pack);
}

Future<LibraryTestApp> _pumpHome(
  WidgetTester tester, {
  bool resume = true,
  bool pinned = false,
  List<Override> extra = const [],
}) async {
  final app = await LibraryTestApp.create(tester);
  if (pinned) await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
  await app.pump(
    tester,
    const HomeView(),
    overrides: [
      continueItemsProvider.overrideWith(
        (ref) async => pinned ? [] : [_item('t1', resume: resume)],
      ),
      packProvider(packId: _pack.id).overrideWith(_FakePack.new),
      ...extra,
    ],
  );
  return app;
}

void main() {
  setUp(_prepared.clear);

  group('Continue card menu', () {
    testWidgets('has no ⋮: a long-press opens it, with all three actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpHome(tester);
      final card = find.byKey(const ValueKey('continue_t1'));
      // The play button is the one control on the card.
      expect(find.byTooltip('More options for Title t1'), findsNothing);
      expect(
        find.descendant(of: card, matching: find.byType(CardMenuButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byType(IconButton)),
        findsOneWidget,
      );
      // A screen reader hears that holding it does something, and what.
      final data = tester.getSemantics(card).getSemanticsData();
      expect(data.hasAction(SemanticsAction.longPress), isTrue);
      expect(
        tester.getSemantics(card).hintOverrides?.onLongPressHint,
        'show more options',
      );

      await tester.longPress(card);
      await settle(tester);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Open course'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
      expect(find.text('Remove from Continue'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a course start has nothing to restart', (tester) async {
      await _pumpHome(tester, resume: false);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      expect(find.text('Open course'), findsOneWidget);
      expect(find.text('Restart'), findsNothing);
    });

    testWidgets('Open course shows the course page', (tester) async {
      await _pumpHome(tester);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_open_course')));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('Restart plays from the start, forgetting the place', (
      tester,
    ) async {
      final app = await _pumpHome(
        tester,
        extra: [
          tracksProvider(trackId: 't1').overrideWith(_OneFileTrack.new),
          playerProvider.overrideWith(_RecordingPlayer.new),
        ],
      );
      await tester.runAsync(
        () => app.harness.store.savePosition('t1', 120000, 600000),
      );
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_restart')));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(_prepared, hasLength(1));
      expect(_prepared.single.trackId, 't1');
      expect(_prepared.single.startPositionMs, 0);
      expect(
        await tester.runAsync(() => app.harness.store.resumePoint('t1')),
        isNull,
      );
    });

    // The place is cleared only once the session is about to start: a failed
    // fetch must not lose it.
    testWidgets('Restart keeps the place when the session cannot load', (
      tester,
    ) async {
      final app = await _pumpHome(
        tester,
        extra: [tracksProvider(trackId: 't1').overrideWith(_FailingTrack.new)],
      );
      await tester.runAsync(
        () => app.harness.store.savePosition('t1', 120000, 600000),
      );
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_restart')));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.textContaining('Unable to load audio'), findsOneWidget);
      expect(
        await tester.runAsync(() => app.harness.store.resumePoint('t1')),
        isNotNull,
      );
    });

    // With a choice to make the track page opens; it must still restart.
    testWidgets('Restart via the track page still plays from the start', (
      tester,
    ) async {
      _prepared.clear();
      final app = await _pumpHome(
        tester,
        extra: [
          tracksProvider(trackId: 't1').overrideWith(_TwoVoiceTrack.new),
          playerProvider.overrideWith(_RecordingPlayer.new),
        ],
      );
      await tester.runAsync(
        () => app.harness.store.savePosition('t1', 120000, 600000),
      );
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_restart')));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      final page = tester.widget<TrackView>(find.byType(TrackView));
      expect(page.fromStart, isTrue);
      expect(_prepared, isEmpty);
      await tester.tap(find.byKey(const ValueKey('track_play')));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(_prepared.single.startPositionMs, 0);
      expect(
        await tester.runAsync(() => app.harness.store.resumePoint('t1')),
        isNull,
      );
    });

    for (final shrinks in [false, true]) {
      testWidgets('Restart still starts when clearing the place drops the card '
          '(list shrinks: $shrinks)', (tester) async {
        _gate = Completer<void>();
        _prepared.clear();
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          const HomeView(),
          overrides: [
            continueItemsProvider.overrideWith((ref) async {
              final rev = ref.watch(playbackPositionsRevisionProvider);
              // As the real provider does: a session with no saved place
              // is no longer in progress.
              return shrinks && rev > 0
                  ? [_item('a')]
                  : [_item('a'), _item('b')];
            }),
            tracksProvider(trackId: 'b').overrideWith(_GatedTrack.new),
            playerProvider.overrideWith(_RecordingPlayer.new),
          ],
        );
        await tester.longPress(find.byKey(const ValueKey('continue_b')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('continue_menu_restart')));
        await tester.pump(const Duration(milliseconds: 50));
        _gate.complete();
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(_prepared.map((r) => r.trackId), ['b']);
      });
    }

    testWidgets('Remove from Continue records it by course', (tester) async {
      final app = await _pumpHome(tester);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_remove')));
      await settle(tester);
      final saved = app.prefs.getStringList('continue_dismissed');
      expect(saved, hasLength(1));
      expect(saved!.single, startsWith('lib-course-a|'));
      expect(find.text('Removed from Continue'), findsOneWidget);

      // Undo takes it back.
      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(app.prefs.getStringList('continue_dismissed'), isEmpty);
    });

    testWidgets('keeps "Session 4 of 32" whole beside a long course title', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith(
            (ref) async => [
              ContinueItem(
                trackId: 't1',
                path: '/tracks/t1',
                title: 'Developing Piti, Developing Focus',
                group: LibraryGroup.practice,
                lastPlayed: DateTime(2026, 10, 19),
                courseId: 'c',
                courseTitle: 'Practising the Jhānas: A Complete Course',
                resume: const ResumePoint(
                  positionMs: 1800000,
                  durationMs: 5340000,
                ),
                sessionNumber: 4,
                sessionTotal: 32,
              ),
            ],
          ),
        ],
      );
      expect(find.text('Session 4 of 32 ·'), findsOneWidget);
      expect(find.text('59:00 left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Pinned card menu', () {
    for (final how in ['long-press', 'the more button']) {
      testWidgets('opens with $how', (tester) async {
        await _pumpHome(tester, pinned: true);
        if (how == 'long-press') {
          await tester.longPress(
            find.byKey(const ValueKey('pinned_lib-course-a')),
          );
        } else {
          await tester.tap(find.byTooltip('More options for Course A'));
        }
        await settle(tester);
        expect(find.text('Open'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Unpin from Home'), findsOneWidget);
      });
    }

    testWidgets('Open shows the course page', (tester) async {
      await _pumpHome(tester, pinned: true);
      await tester.tap(find.byTooltip('More options for Course A'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pinned_menu_open')));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('Unpin offers Undo, which pins it back in place', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [_pack.id, 'other']);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => []),
          packProvider(packId: _pack.id).overrideWith(_FakePack.new),
          packProvider(packId: 'other').overrideWith(_FakePack.new),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );

      await tester.tap(find.byTooltip('More options for Course A').first);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pinned_menu_unpin')));
      await settle(tester);
      expect(container.read(pinnedCoursesProvider), ['other']);
      expect(find.text('Unpinned from Home'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(container.read(pinnedCoursesProvider), [_pack.id, 'other']);
      expect(app.prefs.getStringList('pinned_course_ids'), [_pack.id, 'other']);
    });

    testWidgets('Unpin shows Undo even when the prefs write is slow', (
      tester,
    ) async {
      await _pumpHome(tester, pinned: true);
      // A device-like store: a write takes a few frames to land.
      final slow = _SlowStore(SharedPreferencesStorePlatform.instance);
      SharedPreferencesStorePlatform.instance = slow;
      await tester.tap(find.byTooltip('More options for Course A'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pinned_menu_unpin')));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      for (final c in slow.pending) {
        c.complete();
      }
      await settle(tester);
      expect(find.text('Unpinned from Home'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
    });

    for (final reversed in [false, true]) {
      testWidgets('two unpins undone restore the order '
          '(newest first: $reversed)', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.prefs.setStringList('pinned_course_ids', ['a', 'b', 'c']);
        await app.pump(
          tester,
          const HomeView(),
          overrides: [
            continueItemsProvider.overrideWith((ref) async => []),
            for (final id in ['a', 'b', 'c'])
              packProvider(packId: id).overrideWith(_FakePack.new),
          ],
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(HomeView)),
        );
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.byTooltip('More options for Course A').first);
          await settle(tester);
          await tester.tap(find.byKey(const ValueKey('pinned_menu_unpin')));
          await settle(tester);
        }
        expect(container.read(pinnedCoursesProvider), ['c']);

        final notifier = container.read(pinnedCoursesProvider.notifier);
        if (reversed) {
          await notifier.pinBack('b', ['b', 'c']);
          await notifier.pinBack('a', ['a', 'b', 'c']);
        } else {
          await notifier.pinBack('a', ['a', 'b', 'c']);
          await notifier.pinBack('b', ['b', 'c']);
        }
        expect(container.read(pinnedCoursesProvider), ['a', 'b', 'c']);
      });
    }
  });
}

/// A write takes until its completer is completed.
class _SlowStore extends SharedPreferencesStorePlatform {
  _SlowStore(this.inner);
  final SharedPreferencesStorePlatform inner;
  final pending = <Completer<void>>[];

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final c = Completer<void>();
    pending.add(c);
    await c.future;
    return inner.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) => inner.remove(key);
  @override
  Future<bool> clear() => inner.clear();
  @override
  Future<Map<String, Object>> getAll() => inner.getAll();
}
