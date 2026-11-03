import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/teacher/youtube_channel_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

/// #81 on top of #85: a YouTube course's header names its channel as its
/// teacher, and its Summary reads a one-video course's description when
/// the tab is chosen.
const vervaeke = 'UCpqDUjTsof-kTNpnyWper_Q';

/// Records which pages asked for a description on demand. Opening a course
/// also fills details in the background, so the API's calls alone cannot
/// tell the Summary tab's read apart.
class _RecordingSource extends YoutubeSource {
  _RecordingSource({
    required super.db,
    required super.library,
    required super.api,
    super.detailsPause,
  });

  final described = <String>[];

  @override
  Future<bool> describe(String id) {
    described.add(id);
    return super.describe(id);
  }
}

void main() {
  Future<(DharmaSeedTestApp, _RecordingSource, FakeYoutubeApi)> setUp(
    WidgetTester tester,
  ) async {
    final app = await DharmaSeedTestApp.create(tester, seed: false);
    final api = FakeYoutubeApi()
      ..videos[videoA] = video(
        videoA,
        title: 'Ep. 1 - Introduction',
        description: 'Where the meaning crisis comes from.',
      );
    final source = _RecordingSource(
      db: app.libraryDb,
      library: app.library,
      api: api,
      detailsPause: () => Duration.zero,
    );
    return (app, source, api);
  }

  List<Override> overrides(YoutubeSource source, {bool available = true}) => [
    youtubeAvailableProvider.overrideWithValue(available),
    youtubeSourceProvider.overrideWithValue(source),
    contentSourcesProvider.overrideWith(
      (ref) => [ref.watch(youtubeSourceProvider)],
    ),
  ];

  testWidgets('a series names its channel, with a Teacher tab, and the name '
      'opens the channel page', (tester) async {
    final (app, source, _) = await setUp(tester);
    await tester.runAsync(
      () => source.storePlaylist(
        playlistOne,
        playlist(
          [item(videoA, uploader: 'John Vervaeke')],
          title: 'Awakening from the Meaning Crisis',
          uploader: 'John Vervaeke',
          channel: vervaeke,
        ),
      ),
    );
    await app.pump(
      tester,
      PackView(id: ytPlaylistId(playlistOne)),
      overrides: overrides(source),
    );
    await DharmaSeedTestApp.settle(tester);

    final teacher = find.byKey(const ValueKey('course_teacher'));
    expect(teacher, findsOneWidget);
    expect(
      find.descendant(of: teacher, matching: find.text('John Vervaeke')),
      findsOneWidget,
    );
    expect(find.text('Teacher'), findsOneWidget);

    await tester.tap(teacher);
    await DharmaSeedTestApp.settle(tester);
    expect(find.byType(YoutubeChannelView), findsOneWidget);
  });

  testWidgets('choosing Summary on a one-video course reads its video', (
    tester,
  ) async {
    final (app, source, _) = await setUp(tester);
    await tester.runAsync(
      // Saved before descriptions were kept: nothing resolved yet.
      () => source.storePlaylist(
        'single-$videoA',
        playlist([item(videoA, title: 'Ep. 1 - Introduction')]),
      ),
    );
    await app.pump(
      tester,
      PackView(id: ytSingleCourseId(videoA)),
      overrides: overrides(source),
    );
    await DharmaSeedTestApp.settle(tester);
    expect(source.described, isEmpty, reason: 'not until Summary is chosen');

    await tester.tap(find.text('Summary'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await DharmaSeedTestApp.settle(tester);
    expect(source.described, [ytSingleCourseId(videoA)]);
    expect(
      find.textContaining('Where the meaning crisis comes from.'),
      findsOneWidget,
    );
  });

  testWidgets('without the YouTube bridge Summary looks nothing up', (
    tester,
  ) async {
    final (app, source, _) = await setUp(tester);
    await tester.runAsync(
      () => source.storePlaylist(
        'single-$videoA',
        playlist([item(videoA, title: 'Ep. 1 - Introduction')]),
      ),
    );
    await app.pump(
      tester,
      PackView(id: ytSingleCourseId(videoA)),
      overrides: overrides(source, available: false),
    );
    await DharmaSeedTestApp.settle(tester);

    await tester.tap(find.text('Summary'));
    await DharmaSeedTestApp.settle(tester);
    expect(source.described, isEmpty);
  });
}
