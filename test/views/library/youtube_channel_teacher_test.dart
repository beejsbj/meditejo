import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/youtube/youtube_ids.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/src/youtube_api.g.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/teacher/youtube_channel_view.dart';

import '../../helpers/library_app.dart';
import '../../helpers/youtube_fake.dart';
import 'library_layout_test.dart' show settle, tapFilter;

/// #85: a YouTube channel is a teacher the user can keep, as a Dharma Seed
/// teacher is: saved from its page, listed under Teachers, opening its page,
/// and taken out again.
const vervaeke = 'UCpqDUjTsof-kTNpnyWper_Q';
final channelId = ytChannelId(vervaeke);

Future<(LibraryTestApp, YoutubeSource, List<Override>)> _setUp(
  WidgetTester tester,
) async {
  final app = await LibraryTestApp.create(tester);
  final api = FakeYoutubeApi()
    ..playlists[playlistOne] = playlist(
      [item(videoA, uploader: 'John Vervaeke')],
      title: 'Awakening from the Meaning Crisis',
      uploader: 'John Vervaeke',
      channel: vervaeke,
      avatar: 'https://yt3.example/vervaeke.jpg',
    )
    ..channels[vervaeke] = YoutubeChannel(
      url: channelUrl(vervaeke),
      name: 'John Vervaeke',
      avatar: 'https://yt3.example/vervaeke.jpg',
      description: 'Cognitive science, wisdom and meaning.',
    );
  final source = YoutubeSource(
    db: app.harness.db,
    library: app.harness.store,
    api: api,
    detailsPause: () => Duration.zero,
  );
  await tester.runAsync(() async {
    final preview = await source.preview(
      Uri.parse('https://www.youtube.com/playlist?list=$playlistOne'),
    );
    await source.add(
      preview,
      const ImportChoice(kind: LibraryKind.course, group: LibraryGroup.talks),
    );
  });
  return (
    app,
    source,
    <Override>[
      youtubeAvailableProvider.overrideWithValue(true),
      youtubeSourceProvider.overrideWithValue(source),
    ],
  );
}

void main() {
  testWidgets('the channel page saves and unsaves it, as a teacher', (
    tester,
  ) async {
    final (app, _, overrides) = await _setUp(tester);
    await app.pump(
      tester,
      YoutubeChannelView(teacherId: channelId),
      overrides: overrides,
    );
    await settle(tester);

    await tester.tap(find.text('Add to library'));
    await settle(tester);
    expect(find.text('In library'), findsOneWidget);
    final saved = await tester.runAsync(
      () => app.harness.store.entry(channelId),
    );
    expect(saved!.kind, LibraryKind.teacher);
    expect(saved.title, 'John Vervaeke');
    expect(saved.coverUrl, 'https://yt3.example/vervaeke.jpg');

    await tester.tap(find.text('In library'));
    await settle(tester);
    expect(find.text('Add to library'), findsOneWidget);
    expect(
      await tester.runAsync(() => app.harness.store.entry(channelId)),
      isNull,
    );
  });

  testWidgets('a saved channel is listed under Teachers, opens its page, '
      'and can be removed', (tester) async {
    final (app, source, overrides) = await _setUp(tester);
    await tester.runAsync(() => source.setSaved(channelId, saved: true));
    await app.pump(tester, const LibraryView(), overrides: overrides);
    await settle(tester);

    await tapFilter(tester, 'teachers');
    expect(find.text('John Vervaeke'), findsOneWidget);
    expect(find.text('Awakening from the Meaning Crisis'), findsNothing);

    // Opens the same channel page.
    await tester.tap(find.text('John Vervaeke'));
    await settle(tester);
    expect(find.byType(YoutubeChannelView), findsOneWidget);
    expect(find.text('Cognitive science, wisdom and meaning.'), findsOneWidget);
    expect(find.text('In library'), findsOneWidget);
    Navigator.of(tester.element(find.byType(YoutubeChannelView))).pop();
    await settle(tester);

    // Taken out from the Library as any teacher is.
    await tester.tap(find.byKey(ValueKey('library_menu_$channelId')));
    await settle(tester);
    await tester.tap(find.text('Remove from library'));
    await settle(tester);
    expect(find.text('John Vervaeke'), findsNothing);
    expect(
      await tester.runAsync(() => app.harness.store.entry(channelId)),
      isNull,
    );
  });
}
