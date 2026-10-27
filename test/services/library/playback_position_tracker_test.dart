import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/library/playback_position_tracker.dart';

import '../../helpers/library_fixtures.dart';

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late PlaybackPositionTracker tracker;
  var now = DateTime.utc(2026, 10, 1);

  setUp(() async {
    db = memoryLibraryDb();
    now = DateTime.utc(2026, 10, 1);
    store = LibraryStore(db, clock: () => now);
    tracker = PlaybackPositionTracker(
      store,
      parentsOf: (id) async => id == 'lib-track-1' ? ['lib-course-1'] : [],
      ignore: (id) => id == 'timer',
    );
    await store.add(
      const LibraryDraft(
        sourceId: 'lib-course-1',
        kind: LibraryKind.course,
        title: 'C',
      ),
    );
    await store.add(
      const LibraryDraft(
        sourceId: 'other',
        kind: LibraryKind.course,
        title: 'O',
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> play(
    int position, {
    bool playing = true,
    bool done = false,
    String id = 'lib-track-1',
  }) => tracker.onState(
    trackId: id,
    positionMs: position,
    durationMs: 600000,
    isPlaying: playing,
    isCompleted: done,
  );

  test('saves every few seconds of listening, quietly', () async {
    final before = store.positionsRevision.value;
    await play(1000);
    expect(
      await store.resumePoint('lib-track-1'),
      isNull,
      reason: 'too soon to be worth saving',
    );
    await play(12000);
    expect((await store.resumePoint('lib-track-1'))!.positionMs, 12000);
    await play(14000);
    expect(
      (await store.resumePoint('lib-track-1'))!.positionMs,
      12000,
      reason: 'under the interval since the last save',
    );
    await play(20000);
    expect((await store.resumePoint('lib-track-1'))!.positionMs, 20000);
    expect(
      store.positionsRevision.value,
      before,
      reason: 'lists are not re-read while playing',
    );
  });

  test('pausing saves the exact place and tells lists to re-read', () async {
    await play(30000);
    final before = store.positionsRevision.value;
    await play(33500, playing: false);
    expect((await store.resumePoint('lib-track-1'))!.positionMs, 33500);
    expect(store.positionsRevision.value, greaterThan(before));
  });

  test('finishing forgets the place', () async {
    await play(30000);
    await play(600000, playing: false, done: true);
    expect(await store.resumePoint('lib-track-1'), isNull);
  });

  test(
    'the first play brings the session and its course to the front',
    () async {
      now = DateTime.utc(2026, 10, 5);
      await play(2000);
      final order = (await store.entries()).map((e) => e.sourceId).toList();
      expect(order.first, 'lib-course-1');
      expect(order, ['lib-course-1', 'other']);
    },
  );

  test('the timer and empty states are left alone', () async {
    await play(50000, id: 'timer');
    await play(50000, id: '');
    expect(await db.positionOf('timer'), isNull);
  });

  test('a new session starts fresh', () async {
    await play(50000);
    await play(60000, id: 'lib-track-2');
    await play(1000, id: 'lib-track-2', playing: false);
    expect(
      await store.resumePoint('lib-track-2'),
      isNull,
      reason: '1 s is just an opening',
    );
    expect((await store.resumePoint('lib-track-1'))!.positionMs, 50000);
  });

  test('states that arrive close together are handled in order', () async {
    final playing = play(30000);
    final paused = play(33500, playing: false);
    await Future.wait([playing, paused]);
    expect(
      (await store.resumePoint('lib-track-1'))!.positionMs,
      33500,
      reason: 'the later pause is the last word',
    );
  });
}
