import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

/// #85: an episode whose description was never read reads it when its page
/// opens, and shows it without leaving the page.
void main() {
  Future<(DharmaSeedTestApp, YoutubeSource, FakeYoutubeApi)> setUp(
    WidgetTester tester,
  ) async {
    final app = await DharmaSeedTestApp.create(tester, seed: false);
    final api = FakeYoutubeApi()
      ..videos[videoA] = video(
        videoA,
        title: 'Ep. 1 - Introduction',
        description: 'Where the meaning crisis comes from.',
      );
    final source = YoutubeSource(
      db: app.libraryDb,
      library: app.library,
      api: api,
      detailsPause: () => Duration.zero,
    );
    await tester.runAsync(
      // Stored from a playlist's row: no description yet.
      () => source.storePlaylist(
        playlistOne,
        playlist([item(videoA, title: 'Ep. 1 - Introduction')]),
      ),
    );
    return (app, source, api);
  }

  testWidgets('opening an unread episode reads its description', (
    tester,
  ) async {
    final (app, source, api) = await setUp(tester);
    await app.pump(
      tester,
      const TrackView(trackId: 'yt-video-$videoA'),
      overrides: [
        youtubeAvailableProvider.overrideWithValue(true),
        youtubeSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
      ],
    );
    await DharmaSeedTestApp.settle(tester);

    expect(api.videoCalls, [videoA]);
    expect(
      find.textContaining('Where the meaning crisis comes from.'),
      findsOneWidget,
    );
    final row = await tester.runAsync(() => app.libraryDb.youtubeVideo(videoA));
    expect(row!.resolvedAt, isNotNull);
  });

  testWidgets('without the YouTube bridge nothing is looked up', (
    tester,
  ) async {
    final (app, source, api) = await setUp(tester);
    await app.pump(
      tester,
      const TrackView(trackId: 'yt-video-$videoA'),
      overrides: [
        youtubeAvailableProvider.overrideWithValue(false),
        youtubeSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
      ],
    );
    await DharmaSeedTestApp.settle(tester);
    expect(api.videoCalls, isEmpty);
  });
}
