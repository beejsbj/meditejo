import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';

import '../../helpers/fake_session_source.dart';
import '../../helpers/library_fixtures.dart';

PlaybackRequest request(String trackId) => PlaybackRequest(
  trackId: trackId,
  fileId: trackId,
  title: 'Session $trackId',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://a.test/$trackId',
  duration: 600000,
  hasBackgroundSound: true,
);

MyItemDraft draft(String id) => MyItemDraft(id: id, title: 'Session $id');

/// Which course a session's cues (and autoplay) follow.
void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late FakeSessionSource upstream;
  late MyCourseSource source;
  late ProviderContainer container;

  setUp(() {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    upstream = FakeSessionSource()..addCourse('retreat', ['x-1', 'x-2']);
    source = MyCourseSource(db: db, library: store, sources: () => [upstream]);
    container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(store),
        myCourseSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWithValue([upstream, source]),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    source.dispose();
    store.dispose();
    await db.close();
  });

  Future<CueScope> scopeOf(String trackId) =>
      container.read(cueScopeForRequestProvider(request(trackId)).future);

  test('a session opened from a personal course follows that course', () async {
    // A Talks course holding a session its source files under a retreat.
    final mine = await source.create(
      title: 'Evening talks',
      group: LibraryGroup.talks,
      lines: [MyCourseLine.session(draft('x-2'))],
    );
    await store.noteSessionContext('x-2', mine);

    expect(await scopeOf('x-2'), CueScope(CueKind.talks, courseId: mine));
  });

  test(
    'a session with no course at its source follows the personal one',
    () async {
      // Like an imported file: its source names no course.
      final mine = await source.create(
        title: 'Morning sits',
        lines: [MyCourseLine.session(draft('x-9'))],
      );
      await store.noteSessionContext('x-9', mine);

      expect(await scopeOf('x-9'), CueScope(CueKind.practice, courseId: mine));
    },
  );

  test('once the personal course no longer lists it, the source course '
      'leads', () async {
    final mine = await source.create(
      title: 'Evening talks',
      group: LibraryGroup.talks,
      lines: [MyCourseLine.session(draft('x-1'))],
    );
    await store.noteSessionContext('x-1', mine);
    await source.removeItem(mine, 'x-1');

    expect(
      (await scopeOf('x-1')).courseId,
      'x-course-retreat',
      reason: 'the course it was opened from has dropped it',
    );
  });

  test('without a personal course, the source course leads', () async {
    expect((await scopeOf('x-1')).courseId, 'x-course-retreat');
    // A context recorded from the source's own course page changes nothing.
    await store.noteSessionContext('x-2', 'x-course-retreat');
    container.invalidate(cueScopeForRequestProvider);
    expect((await scopeOf('x-2')).courseId, 'x-course-retreat');
  });
}
