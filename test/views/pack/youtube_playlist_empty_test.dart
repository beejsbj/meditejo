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

  Future<void> pollsWhileFailing(
    WidgetTester tester,
    String code,
    List<int> expectedCallsAfterEachMinute,
  ) async {
    final db = memoryLibraryDb();
    final store = LibraryStore(db);
    final api = FakeYoutubeApi()..failure = PlatformException(code: code);
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
    final start = api.playlistCalls.length;
    for (final expected in expectedCallsAfterEachMinute) {
      await tester.pump(const Duration(minutes: 1));
      await DharmaSeedTestApp.settle(tester);
      expect(api.playlistCalls.length - start, expected);
    }
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    await tester.runAsync(db.close);
  }

  testWidgets('a rate-limited playlist backs off instead of polling', (
    tester,
  ) async {
    // Attempts at 30 s, 60 s, 120 s and 240 s (an offline playlist would
    // make two a minute: 2, 4, 6, 8).
    await pollsWhileFailing(tester, 'rate-limited', [2, 3, 3, 4]);
  });

  testWidgets('resuming the app does not re-ask a rate-limiting YouTube', (
    tester,
  ) async {
    final db = memoryLibraryDb();
    final store = LibraryStore(db);
    final api = FakeYoutubeApi()
      ..failure = PlatformException(code: 'rate-limited');
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
    final before = api.playlistCalls.length;
    for (final state in [
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
      AppLifecycleState.paused,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(seconds: 1));
    }
    // Under 30 s have passed, so no timer tick: resuming alone asked nothing.
    expect(api.playlistCalls.length, before);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    await tester.runAsync(db.close);
  });

  testWidgets('a permanently unavailable playlist is not polled', (
    tester,
  ) async {
    await pollsWhileFailing(tester, 'private', [0, 0, 0]);
  });
}
