import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/library_fixtures.dart';
import '../helpers/youtube_fake.dart';

/// Sessions the stats call done; set per test before anything reads them.
List<String> _done = [];

class _Stats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async =>
      LocalAllStats.empty().copyWith(tracksChecked: [..._done]);
}

/// Home's Continue reads a due YouTube course from what is stored. The
/// 12-hourly playlist check runs behind it; a slow or stuck extractor must
/// never hold the row back.
void main() {
  late LibraryDatabase db;
  late LibraryStore store;
  late FakeYoutubeApi api;
  late ProviderContainer container;
  final course = ytPlaylistId(playlistOne);

  setUp(() async {
    db = memoryLibraryDb();
    store = LibraryStore(db);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = FakeYoutubeApi()
      ..playlistGate = Completer<void>()
      ..playlists[playlistOne] = playlist([item(videoA), item(videoB)]);
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        libraryDatabaseProvider.overrideWithValue(db),
        libraryStoreProvider.overrideWithValue(store),
        youtubeExtractorProvider.overrideWithValue(api),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
        statsProvider.overrideWith(_Stats.new),
      ],
    );
    final source = container.read(youtubeSourceProvider);
    await source.storePlaylist(
      playlistOne,
      playlist([item(videoA), item(videoB)]),
    );
    await source.setSaved(course, saved: true);
    // Due: last checked in 2000.
    await (db.update(db.youtubePlaylists)
          ..where((p) => p.playlistId.equals(playlistOne)))
        .write(YoutubePlaylistsCompanion(lastCheckedAt: Value(DateTime(2000))));
  });

  Future<void> readStats(List<String> done) async {
    _done = done;
    container.listen(statsProvider, (_, _) {});
    await container.read(statsProvider.future);
  }

  tearDown(() async {
    if (!api.playlistGate!.isCompleted) api.playlistGate!.complete();
    await container.read(youtubeSourceProvider).refresh(course);
    container.dispose();
    store.dispose();
    await db.close();
  });

  test('a session left partway is offered while the check is stuck', () async {
    await readStats([]);
    await db
        .into(db.playbackPositions)
        .insertOnConflictUpdate(
          PlaybackPositionsCompanion.insert(
            trackId: ytVideoId(videoA),
            positionMs: 120000,
            durationMs: const Value(600000),
            updatedAt: DateTime(2026, 10, 18),
          ),
        );
    await store.noteSessionContext(ytVideoId(videoA), course);

    final items = await container
        .read(continueItemsProvider.future)
        .timeout(const Duration(seconds: 3));

    expect(items.single.trackId, ytVideoId(videoA));
    expect(items.single.courseId, course);
    await pumpEventQueue(times: 100);
    expect(api.playlistCalls, isNotEmpty, reason: 'the check did start');
    expect(api.playlistGate!.isCompleted, isFalse, reason: 'and is unfinished');
  });

  test(
    'the next session of a started course is offered the same way',
    () async {
      await readStats([ytVideoId(videoA)]);

      final items = await container
          .read(continueItemsProvider.future)
          .timeout(const Duration(seconds: 3));

      expect(items.single.trackId, ytVideoId(videoB));
      expect(items.single.courseId, course);
      await pumpEventQueue(times: 100);
    expect(api.playlistCalls, isNotEmpty, reason: 'the check did start');
      expect(
        api.playlistGate!.isCompleted,
        isFalse,
        reason: 'and is unfinished',
      );
    },
  );
}
