import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/widgets/shimmers/folder_shimmer_widget.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

void main() {
  testWidgets('a background refresh landing on an open course keeps the page', (
    tester,
  ) async {
    final app = await DharmaSeedTestApp.create(tester, seed: false);
    final api = FakeYoutubeApi()
      ..playlistGate = Completer<void>()
      ..playlists[playlistOne] = playlist([item(videoA), item(videoB)]);
    final source = YoutubeSource(
      db: app.libraryDb,
      library: app.library,
      api: api,
    );
    await tester.runAsync(() async {
      await source.storePlaylist(playlistOne, playlist([item(videoA)]));
      await source.setSaved('yt-playlist-$playlistOne', saved: true);
      await (app.libraryDb.update(
        app.libraryDb.youtubePlaylists,
      )..where((p) => p.playlistId.equals(playlistOne))).write(
        YoutubePlaylistsCompanion(lastCheckedAt: Value(DateTime(2000))),
      );
    });
    await app.pump(
      tester,
      const PackView(id: 'yt-playlist-$playlistOne'),
      overrides: [
        youtubeSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
      ],
    );
    expect(find.byType(FolderShimmerWidget), findsNothing);
    expect(find.byType(CustomScrollView), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PackView)),
    );
    final states = <AsyncValue<PackModel>>[];
    container.listen(
      packProvider(packId: 'yt-playlist-$playlistOne'),
      (_, next) => states.add(next),
    );
    api.playlistGate!.complete();
    // Between the refresh landing and the page settling, never the shimmer.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(FolderShimmerWidget), findsNothing);
    }
    expect(find.byType(CustomScrollView), findsOneWidget);
    // The page itself is never handed a loading state (it would swap the
    // list for the placeholder and lose the scroll position), yet it ends
    // up showing the refreshed sessions.
    expect(states, isNotEmpty);
    expect(states.where((s) => s.isLoading), isEmpty);
    expect(states.last.requireValue.items, hasLength(2));
    expect(api.playlistCalls, hasLength(1), reason: 'the refresh did run');
    final row = await tester.runAsync(
      () => app.libraryDb.youtubePlaylist(playlistOne),
    );
    expect(row!.videoIds, contains(videoB));
    await tester.pump(const Duration(seconds: 15));
  });
}
