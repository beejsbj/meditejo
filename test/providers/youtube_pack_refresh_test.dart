import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';

import '../helpers/library_fixtures.dart';
import '../helpers/youtube_fake.dart';

void main() {
  test(
    'cached course provider returns before extraction and updates after it',
    () async {
      final db = memoryLibraryDb();
      final store = LibraryStore(db);
      final api = FakeYoutubeApi()
        ..playlistGate = Completer<void>()
        ..playlists[playlistOne] = playlist([item(videoA), item(videoB)]);
      final container = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(db),
          libraryStoreProvider.overrideWithValue(store),
          youtubeExtractorProvider.overrideWithValue(api),
          contentSourcesProvider.overrideWith(
            (ref) => [ref.watch(youtubeSourceProvider)],
          ),
        ],
      );
      addTearDown(() async {
        if (!api.playlistGate!.isCompleted) api.playlistGate!.complete();
        await container
            .read(youtubeSourceProvider)
            .refresh('yt-playlist-$playlistOne');
        container.dispose();
        store.dispose();
        await db.close();
      });
      final source = container.read(youtubeSourceProvider);
      await source.storePlaylist(playlistOne, playlist([item(videoA)]));
      await source.setSaved('yt-playlist-$playlistOne', saved: true);
      await (db.update(
        db.youtubePlaylists,
      )..where((p) => p.playlistId.equals(playlistOne))).write(
        YoutubePlaylistsCompanion(lastCheckedAt: Value(DateTime(2000))),
      );
      final provider = packDataProvider(packId: 'yt-playlist-$playlistOne');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final before = await container
          .read(provider.future)
          .timeout(const Duration(seconds: 2));
      expect(before.items.map((i) => i.id), ['yt-video-$videoA']);
      expect(api.playlistGate!.isCompleted, isFalse);
      api.playlistGate!.complete();
      await source.refresh('yt-playlist-$playlistOne');
      await container.pump();
      final after = await container.read(provider.future);
      expect(after.items.map((i) => i.id), [
        'yt-video-$videoA',
        'yt-video-$videoB',
      ]);
    },
  );
}
