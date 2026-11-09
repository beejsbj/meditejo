import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/youtube/youtube_source.dart';
import 'package:medito/src/youtube_api.g.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/views/teacher/youtube_channel_view.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/youtube_fake.dart';

/// #85: a YouTube channel is the teacher of its playlists and videos.
const vervaeke = 'UCpqDUjTsof-kTNpnyWper_Q';
const courseId = 'yt-playlist-$playlistOne';

Future<(DharmaSeedTestApp, YoutubeSource, FakeYoutubeApi)> _setUp(
  WidgetTester tester, {
  bool channelRead = true,
}) async {
  final app = await DharmaSeedTestApp.create(tester, seed: false);
  final api = FakeYoutubeApi()
    ..playlists[playlistOne] = playlist(
      [
        for (final (n, id) in [(1, videoA), (2, videoB)])
          item(
            id,
            title: 'Ep. $n - Awakening from the Meaning Crisis',
            uploader: 'John Vervaeke',
          ),
      ],
      title: 'Awakening from the Meaning Crisis',
      uploader: 'John Vervaeke',
      description: 'A fifty-part series on the meaning crisis.',
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
    db: app.libraryDb,
    library: app.library,
    api: api,
    detailsPause: () => Duration.zero,
  );
  await tester.runAsync(() async {
    final preview = await source.preview(
      Uri.parse('https://www.youtube.com/playlist?list=$playlistOne'),
    );
    await source.add(
      preview,
      const ImportChoice(
        kind: LibraryKind.course,
        group: LibraryGroup.practice,
      ),
    );
    if (channelRead) await source.fillDetails(courseId);
  });
  return (app, source, api);
}

void main() {
  testWidgets('a channel page shows the channel, its description and its '
      'saved courses', (tester) async {
    final (app, source, _) = await _setUp(tester);
    await app.pump(
      tester,
      const TeacherView(teacherId: 'yt-channel-$vervaeke'),
      overrides: [youtubeSourceProvider.overrideWithValue(source)],
    );

    expect(find.byType(YoutubeChannelView), findsOneWidget);
    expect(find.text('John Vervaeke'), findsWidgets);
    expect(find.text('Cognitive science, wisdom and meaning.'), findsOneWidget);
    expect(find.text('1 course'), findsOneWidget, reason: 'no zero counts');
    // The channel's own page does not put its face on every card.
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is NetworkImageWidget &&
            w.url == 'https://yt3.example/vervaeke.jpg' &&
            w.art is CoverArt &&
            (w.art! as CoverArt).kind == ArtCoverKind.teacher &&
            (w.art! as CoverArt).id == 'https://yt3.example/vervaeke.jpg',
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('channel_open_youtube')), findsOneWidget);
    expect(find.text('Awakening from the Meaning Crisis'), findsOneWidget);
    expect(find.text('John Vervaeke · YouTube'), findsOneWidget);
  });

  testWidgets('a channel with no description says so', (tester) async {
    final (app, source, api) = await _setUp(tester, channelRead: false);
    api.channels[vervaeke] = YoutubeChannel(
      url: channelUrl(vervaeke),
      name: 'John Vervaeke',
      avatar: '',
      description: '',
    );
    await app.pump(
      tester,
      const TeacherView(teacherId: 'yt-channel-$vervaeke'),
      overrides: [youtubeSourceProvider.overrideWithValue(source)],
    );
    expect(find.text('No channel description on YouTube.'), findsOneWidget);
  });

  testWidgets('a channel that is not stored is not found', (tester) async {
    final (app, source, _) = await _setUp(tester);
    await app.pump(
      tester,
      const TeacherView(teacherId: 'yt-channel-UCnobodynobodynobody000'),
      overrides: [youtubeSourceProvider.overrideWithValue(source)],
    );
    expect(
      find.text('This teacher is not in the library yet.'),
      findsOneWidget,
    );
  });

  testWidgets('a YouTube course has Summary and Teacher tabs, and the '
      'teacher button opens the channel', (tester) async {
    final (app, source, _) = await _setUp(tester);
    await app.pump(
      tester,
      const PackView(id: courseId),
      overrides: [
        youtubeSourceProvider.overrideWithValue(source),
        contentSourcesProvider.overrideWith(
          (ref) => [ref.watch(youtubeSourceProvider)],
        ),
      ],
    );

    await tester.tap(find.text('Summary'));
    await DharmaSeedTestApp.settle(tester);
    expect(
      find.textContaining('A fifty-part series on the meaning crisis.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Teacher'));
    await DharmaSeedTestApp.settle(tester);
    expect(find.text('Cognitive science, wisdom and meaning.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('course_open_teacher')));
    await DharmaSeedTestApp.settle(tester);
    expect(find.byType(YoutubeChannelView), findsOneWidget);
  });

  testWidgets('a YouTube card carries its channel\'s picture at the lower '
      'left, and a card without one has none', (tester) async {
    final (app, source, _) = await _setUp(tester);
    await app.pump(
      tester,
      const Column(
        children: [
          SizedBox.square(
            dimension: 120,
            child: CardArt(
              art: ArtSubject.cover(ArtCoverKind.course, courseId),
              avatarSize: 32,
            ),
          ),
          SizedBox.square(
            dimension: 120,
            child: CardArt(
              art: ArtSubject.cover(
                ArtCoverKind.course,
                'yt-playlist-PLnochannel',
              ),
              avatarSize: 32,
            ),
          ),
        ],
      ),
      overrides: [youtubeSourceProvider.overrideWithValue(source)],
    );
    final avatars = find.byWidgetPredicate(
      (w) =>
          w is NetworkImageWidget &&
          w.url == 'https://yt3.example/vervaeke.jpg',
    );
    expect(avatars, findsOneWidget);
    final card = tester.getRect(find.byType(CardArt).first);
    final avatar = tester.getRect(avatars);
    expect(avatar.left - card.left, lessThan(card.width / 2));
    expect(avatar.top - card.top, greaterThan(card.height / 2));
  });
}
