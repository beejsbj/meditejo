import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/views/pack/pack_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

/// Pulling a YouTube course to refresh tells the user why it failed: the
/// typed reason survives the bridge, so a rate-limited user is not told they
/// are offline, in the app's own language.
void main() {
  Future<String> pullAndRead(WidgetTester tester, Object failure) async {
    final app = await DharmaSeedTestApp.create(tester, seed: false);
    final api = FakeYoutubeApi()
      ..playlists[playlistOne] = playlist([item(videoA), item(videoB)]);
    final source = YoutubeSource(
      db: app.libraryDb,
      library: app.library,
      api: api,
    );
    await tester.runAsync(() async {
      await source.storePlaylist(playlistOne, playlist([item(videoA)]));
      await source.setSaved('yt-playlist-$playlistOne', saved: true);
      // Fresh: only a pull overrides the twelve-hour throttle.
      await (app.libraryDb.update(
        app.libraryDb.youtubePlaylists,
      )..where((p) => p.playlistId.equals(playlistOne))).write(
        YoutubePlaylistsCompanion(lastCheckedAt: Value(DateTime.now())),
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
    api.failure = failure;

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 500),
      1000,
    );
    await DharmaSeedTestApp.settle(tester);

    expect(find.byType(SnackBar), findsOneWidget);
    expect(api.playlistCalls, isNotEmpty, reason: 'the pull did ask');
    return tester
        .widget<Text>(
          find.descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Text),
          ),
        )
        .data!;
  }

  testWidgets('a rate-limited pull says try later, not offline', (
    tester,
  ) async {
    final text = await pullAndRead(
      tester,
      PlatformException(code: 'rate-limited'),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    expect(text, l10n.youtubeRateLimited);
    expect(text, isNot(l10n.youtubePlaylistOffline));
    expect(text.toLowerCase(), contains('try again later'));
  });

  testWidgets('a busy or bot-checked pull is try later too', (tester) async {
    final text = await pullAndRead(tester, PlatformException(code: 'busy'));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(text, l10n.youtubeRateLimited);
  });

  testWidgets('an offline pull says offline', (tester) async {
    final text = await pullAndRead(tester, PlatformException(code: 'network'));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(text, l10n.youtubePlaylistOffline);
  });

  testWidgets('an unavailable playlist says so', (tester) async {
    final text = await pullAndRead(
      tester,
      PlatformException(code: 'unavailable'),
    );
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(text, l10n.youtubePlaylistUnavailable);
  });
}
