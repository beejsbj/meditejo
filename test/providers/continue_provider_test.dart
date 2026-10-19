import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/library_fixtures.dart';

/// Courses `x-course-<name>` holding sessions `x-<name>-<n>`.
class _Source implements ContentSource, ParentedContentSource {
  @override
  String get prefix => 'x-';

  @override
  Future<String?> parentOf(String trackId) async {
    final parts = trackId.split('-');
    return parts.length == 3 ? 'x-course-${parts[1]}' : null;
  }

  @override
  Future<Track> track(String id) async => Track(
    id: id,
    title: 'Title of $id',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: true,
  );

  @override
  Future<List<PackModel>> browsePacks() async => const [];
  @override
  Future<PackModel> pack(String id) => throw UnimplementedError();
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => const {};
  @override
  Future<List<PackItemsModel>> searchPacks(String query) async => const [];
  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async => const [];
}

class _Stats extends StatsNotifier {
  _Stats(this.checked);
  final List<String> checked;

  @override
  Future<LocalAllStats> build() async =>
      LocalAllStats.empty().copyWith(tracksChecked: [...checked]);
}

PackModel _course(String name, {int sessions = 4}) => PackModel(
  id: 'x-course-$name',
  title: 'Course $name',
  items: [
    for (var i = 1; i <= sessions; i++)
      PackItemsModel(
        type: TypeConstants.track,
        id: 'x-$name-$i',
        title: 'Session $i of $name',
        path: '/tracks/x-$name-$i',
      ),
  ],
);

void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late SharedPreferences prefs;

  setUp(() async {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() => db.close());

  Future<void> addCourse(
    String name, {
    LibraryGroup group = LibraryGroup.practice,
    bool played = false,
  }) async {
    await store.add(
      LibraryDraft(
        sourceId: 'x-course-$name',
        kind: LibraryKind.course,
        title: 'Course $name',
        group: group,
      ),
    );
    if (played) await store.touchPlayed(['x-course-$name']);
  }

  Future<void> leftAt(String trackId, DateTime when) => db
      .into(db.playbackPositions)
      .insertOnConflictUpdate(
        PlaybackPositionsCompanion.insert(
          trackId: trackId,
          positionMs: 120000,
          durationMs: const Value(600000),
          updatedAt: when,
        ),
      );

  Future<List<ContinueItem>> read({
    List<String> checked = const [],
    List<PackModel> packs = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        libraryStoreProvider.overrideWithValue(store),
        libraryContentRouterProvider.overrideWithValue(
          ContentRouter(sources: [_Source()]),
        ),
        statsProvider.overrideWith(() => _Stats(checked)),
        for (final pack in packs)
          packDataProvider(packId: pack.id).overrideWith((ref) async => pack),
      ],
    );
    addTearDown(container.dispose);
    container.listen(statsProvider, (_, _) {});
    await container.read(statsProvider.future);
    return container.read(continueItemsProvider.future);
  }

  test('a session left partway resumes, with its course and place', () async {
    await addCourse('a', played: true);
    await leftAt('x-a-2', DateTime(2026, 10, 18));

    final items = await read(packs: [_course('a')]);

    expect(items, hasLength(1));
    expect(items.single.trackId, 'x-a-2');
    expect(items.single.resume?.positionMs, 120000);
    expect(items.single.courseTitle, 'Course a');
    expect(items.single.sessionNumber, 2);
    expect(items.single.sessionTotal, 4);
  });

  test('a completed resume point yields the next unfinished session', () async {
    await addCourse('a', played: true);
    await leftAt('x-a-1', DateTime(2026, 10, 18));
    final items = await read(checked: ['x-a-1'], packs: [_course('a')]);
    expect(items.single.trackId, 'x-a-2');
    expect(items.single.resume, isNull);
    expect(items.single.completedSessions, 1);
  });

  test(
    'resuming a later session does not invent earlier completions',
    () async {
      await addCourse('a', played: true);
      await leftAt('x-a-4', DateTime(2026, 10, 18));
      final items = await read(packs: [_course('a')]);
      expect(items.single.sessionNumber, 4);
      expect(items.single.completedSessions, 0);
    },
  );

  test(
    'all started courses participate before the practice-first limit',
    () async {
      final names = [
        'oldPractice',
        'done1',
        'done2',
        'done3',
        'done4',
        'done5',
        'talk',
      ];
      for (final name in names) {
        await addCourse(
          name,
          group: name == 'talk' ? LibraryGroup.talks : LibraryGroup.practice,
          played: true,
        );
      }
      final items = await read(
        packs: [for (final name in names) _course(name)],
        checked: [
          'x-oldPractice-1',
          'x-talk-1',
          for (final name in names.where((n) => n.startsWith('done')))
            for (var i = 1; i <= 4; i++) 'x-$name-$i',
        ],
      );
      expect(items.map((i) => i.trackId), ['x-oldPractice-2', 'x-talk-2']);
    },
  );

  test('a course with some sessions done offers its next one', () async {
    await addCourse('a', played: true);

    final items = await read(
      checked: ['x-a-1', 'x-a-2'],
      packs: [_course('a')],
    );

    expect(items.single.trackId, 'x-a-3');
    expect(items.single.resume, isNull);
    expect(items.single.sessionNumber, 3);
  });

  test(
    'checked sessions establish progress without a playback timestamp',
    () async {
      await addCourse('unrelated');
      await addCourse('checked');
      final items = await read(
        checked: ['x-checked-1'],
        packs: [_course('unrelated'), _course('checked')],
      );
      expect(items.single.trackId, 'x-checked-2');
      expect(items.single.completedSessions, 1);
    },
  );

  test(
    'course order changes refresh Continue without a library or stats change',
    () async {
      await addCourse('a');
      var pack = _course('a');
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          libraryStoreProvider.overrideWithValue(store),
          libraryContentRouterProvider.overrideWithValue(
            ContentRouter(sources: [_Source()]),
          ),
          statsProvider.overrideWith(() => _Stats(['x-a-1'])),
          packDataProvider(packId: pack.id).overrideWith((ref) async => pack),
        ],
      );
      addTearDown(container.dispose);
      container.listen(continueItemsProvider, (_, _) {});
      await container.read(statsProvider.future);
      expect(
        (await container.read(continueItemsProvider.future)).single.trackId,
        'x-a-2',
      );
      pack = pack.copyWith(items: pack.items.reversed.toList());
      container.invalidate(packDataProvider(packId: pack.id));
      final next = await container.read(continueItemsProvider.future);
      expect(next.single.trackId, 'x-a-4');
      expect(next.single.sessionNumber, 1);
    },
  );

  test(
    'a resumed standalone recording uses its library title override',
    () async {
      await store.add(
        const LibraryDraft(
          sourceId: 'x-loose',
          kind: LibraryKind.single,
          title: 'Original',
        ),
      );
      await store.setTitle('x-loose', 'My renamed recording');
      await leftAt('x-loose', DateTime(2026, 10, 18));
      final items = await read();
      expect(items.single.title, 'My renamed recording');
    },
  );

  test('a finished course is not in progress', () async {
    await addCourse('a', played: true);
    // Nothing in progress, so Home falls back; but not to a finished course.
    final items = await read(
      checked: ['x-a-1', 'x-a-2', 'x-a-3', 'x-a-4'],
      packs: [_course('a')],
    );
    expect(items, isEmpty);
  });

  test('a course with a session left partway shows once', () async {
    await addCourse('a', played: true);
    await leftAt('x-a-3', DateTime(2026, 10, 18));

    final items = await read(checked: ['x-a-1'], packs: [_course('a')]);

    expect(items.map((i) => i.trackId), ['x-a-3']);
  });

  test('practice before talks, then most recent; three at most', () async {
    await addCourse('talkA', group: LibraryGroup.talks, played: true);
    await addCourse('p1', played: true);
    await addCourse('p2', played: true);
    await addCourse('p3', played: true);
    await leftAt('x-talkA-1', DateTime(2026, 10, 19));
    await leftAt('x-p1-1', DateTime(2026, 10, 10));
    await leftAt('x-p2-1', DateTime(2026, 10, 12));
    await leftAt('x-p3-1', DateTime(2026, 10, 11));

    final items = await read(
      packs: [_course('talkA'), _course('p1'), _course('p2'), _course('p3')],
    );

    expect(items.map((i) => i.trackId), ['x-p2-1', 'x-p3-1', 'x-p1-1']);
  });

  test('an older practice resume ranks ahead of twelve recent talks', () async {
    await addCourse('practice');
    await leftAt('x-practice-1', DateTime(2026, 10, 1));
    for (var i = 0; i < 12; i++) {
      await addCourse('talk$i', group: LibraryGroup.talks);
      await leftAt('x-talk$i-1', DateTime(2026, 10, 19));
    }
    final items = await read(
      packs: [
        _course('practice'),
        for (var i = 0; i < 12; i++) _course('talk$i'),
      ],
    );
    expect(items, hasLength(3));
    expect(items.first.trackId, 'x-practice-1');
  });

  group('a session in several courses', () {
    PackModel mine(String id, List<String> sessions) => PackModel(
      id: id,
      title: 'Mine $id',
      items: [
        for (final s in sessions)
          PackItemsModel(
            type: TypeConstants.track,
            id: s,
            title: 'Session $s',
            path: '/tracks/$s',
          ),
      ],
    );

    test('continues in the course it was opened from', () async {
      await addCourse('a', played: true);
      await leftAt('x-a-2', DateTime(2026, 10, 18));
      await store.noteSessionContext('x-a-2', 'my-course-1');

      final items = await read(
        packs: [
          _course('a'),
          mine('my-course-1', ['x-b-1', 'x-a-2']),
        ],
      );

      expect(items.single.courseId, 'my-course-1');
      expect(items.single.courseTitle, 'Mine my-course-1');
      expect(items.single.sessionNumber, 2);
      expect(items.single.sessionTotal, 2);
    });

    test('falls back to its own course once that course drops it', () async {
      await addCourse('a', played: true);
      await leftAt('x-a-2', DateTime(2026, 10, 18));
      await store.noteSessionContext('x-a-2', 'my-course-1');

      final items = await read(
        packs: [
          _course('a'),
          mine('my-course-1', ['x-b-1']),
        ],
      );

      expect(items.single.courseId, 'x-course-a');
      expect(items.single.sessionNumber, 2);
    });

    test('a gone session is never the next one', () async {
      await store.add(
        const LibraryDraft(
          sourceId: 'my-course-1',
          kind: LibraryKind.course,
          title: 'Mine',
          group: LibraryGroup.practice,
        ),
      );
      await store.touchPlayed(['my-course-1']);
      final pack = mine('my-course-1', ['x-a-1', 'x-a-2', 'x-a-3']);
      final withGone = pack.copyWith(
        items: [
          pack.items[0],
          pack.items[1].copyWith(unavailable: true),
          pack.items[2],
        ],
      );

      final items = await read(checked: ['x-a-1'], packs: [withGone]);

      expect(items.single.trackId, 'x-a-3');
    });
  });

  test('a session from outside the library still counts', () async {
    await leftAt('x-loose', DateTime(2026, 10, 18));

    final items = await read();

    expect(items.single.trackId, 'x-loose');
    expect(items.single.title, 'Title of x-loose');
    expect(items.single.group, LibraryGroup.practice);
  });

  group('with nothing in progress', () {
    test('the next session of a pinned course', () async {
      await addCourse('a');
      await addCourse('b');
      await prefs.setStringList('pinned_course_ids', ['x-course-b']);

      final items = await read(
        checked: ['x-b-1'],
        packs: [_course('a'), _course('b')],
      );

      expect(items.single.trackId, 'x-b-2');
    });

    test('else the first course in the library, practice first', () async {
      await addCourse('talks', group: LibraryGroup.talks);
      await addCourse('practice');

      final items = await read(packs: [_course('talks'), _course('practice')]);

      expect(items.single.trackId, 'x-practice-1');
      expect(items.single.resume, isNull);
    });

    test('an empty library has nothing to offer', () async {
      expect(await read(), isEmpty);
    });

    test('pins are only read from the pinned list', () {
      expect(PinnedCoursesNotifier.maxPinned, 3);
    });
  });
}
