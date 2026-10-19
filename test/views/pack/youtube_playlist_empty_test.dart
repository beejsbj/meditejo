import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/views/pack/widgets/youtube_playlist_empty.dart';

import '../../helpers/library_fixtures.dart';
import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

void main() {
  testWidgets(
    'offline starter explains and retries after connectivity returns',
    (tester) async {
      final db = memoryLibraryDb();
      final store = LibraryStore(db);
      final api = FakeYoutubeApi()
        ..failure = PlatformException(code: 'network');
      final source = YoutubeSource(db: db, library: store, api: api);
      await tester.runAsync(() async {
        await source.storePlaylist(playlistOne, playlist([]));
        await source.refresh('yt-playlist-$playlistOne');
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [youtubeSourceProvider.overrideWithValue(source)],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: YoutubePlaylistEmpty(packId: 'yt-playlist-PLone'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text("You're offline. Connect to load this playlist"),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      api.failure = null;
      api.playlists[playlistOne] = playlist([item(videoA)]);
      final before = api.playlistCalls.length;
      await tester.pump(const Duration(seconds: 30));
      await DharmaSeedTestApp.settle(tester);
      expect(api.playlistCalls.length, greaterThan(before));
      expect(source.refreshError('yt-playlist-$playlistOne'), isNull);
      final row = await tester.runAsync(() => db.youtubePlaylist(playlistOne));
      expect(row!.videoIds, contains(videoA));
      await tester.pumpWidget(const SizedBox());
      final after = api.playlistCalls.length;
      await tester.pump(const Duration(minutes: 1));
      expect(api.playlistCalls.length, after);
      store.dispose();
      await tester.runAsync(db.close);
    },
  );
}
