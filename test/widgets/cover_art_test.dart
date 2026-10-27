import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/views/dharma_seed/widgets/teacher_avatar.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cards/card_art.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

import '../helpers/art_finders.dart';

const _photo = 'https://www.dharmaseed.org/api/1/teachers/210/p.png/?maxW=400';
const _thumb = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 160, height: 90, child: child)),
  ),
);

void main() {
  setUpAll(holdCuratedArt);

  group('the art for an id', () {
    test('a playlist is a course the user made, by its id', () {
      expect(
        courseArt('my-course-0123456789abcdef'),
        const ArtSubject.cover(
          ArtCoverKind.playlist,
          'my-course-0123456789abcdef',
        ),
      );
      expect(
        courseArt('ds-retreat-1'),
        const ArtSubject.cover(ArtCoverKind.course, 'ds-retreat-1'),
      );
    });

    test('a renamed item keeps its subject: the title is not in it', () {
      // Nothing about the art takes a title, so a rename cannot move it.
      expect(courseArt('lib-course-a').key, 'cover:course:lib-course-a');
      expect(singleArt('lib-track-a').key, 'cover:single:lib-track-a');
      expect(teacherArt('ds-teacher-210').key, 'cover:teacher:ds-teacher-210');
    });
  });

  group('which picture wins', () {
    test('a real cover wins over generated art', () {
      expect(shownCoverUrl(courseArt('yt-playlist-x'), _thumb), _thumb);
      expect(shownCoverUrl(singleArt('lib-track-a'), _thumb), _thumb);
    });

    test('a Dharma Seed course or talk ignores the teacher photo it has', () {
      expect(shownCoverUrl(courseArt('ds-retreat-1'), _photo), isEmpty);
      expect(shownCoverUrl(singleArt('ds-talk-2'), _photo), isEmpty);
      expect(dsCoverUrl('ds-retreat-1', _photo), isEmpty);
      expect(dsHasPortraitCover('ds-teacher-210'), isFalse);
    });

    test('a teacher with a photo shows it', () {
      expect(shownCoverUrl(teacherArt('ds-teacher-210'), _photo), _photo);
    });
  });

  group('NetworkImageWidget', () {
    testWidgets('no address shows the art for the id', (tester) async {
      await tester.pumpWidget(
        _app(NetworkImageWidget(url: '', art: courseArt('ds-retreat-1'))),
      );
      expect(findArt(courseArt('ds-retreat-1')), findsOneWidget);
    });

    testWidgets('a real cover shows as a picture, not the art', (tester) async {
      await tester.pumpWidget(
        _app(NetworkImageWidget(url: _thumb, art: courseArt('yt-playlist-x'))),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ArtCover), findsNothing);
    });

    testWidgets('a Dharma Seed course ignores a teacher-photo coverUrl', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(NetworkImageWidget(url: _photo, art: courseArt('ds-retreat-1'))),
      );
      expect(findArt(courseArt('ds-retreat-1')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('an errorWidget still takes precedence over the art', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          NetworkImageWidget(
            url: '',
            art: courseArt('a'),
            errorWidget: const Text('mine'),
          ),
        ),
      );
      expect(find.text('mine'), findsOneWidget);
      expect(find.byType(ArtCover), findsNothing);
    });

    testWidgets('without art it keeps the placeholder', (tester) async {
      await tester.pumpWidget(_app(const NetworkImageWidget(url: '')));
      expect(find.byType(ArtCover), findsNothing);
    });
  });

  group('teachers and Dharma Seed cards', () {
    testWidgets('a teacher with a photo shows the photo', (tester) async {
      await tester.pumpWidget(
        _app(
          const TeacherAvatar(
            id: 'ds-teacher-210',
            name: 'Rob',
            photoUrl: _photo,
            size: 72,
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ArtCover), findsNothing);
    });

    testWidgets('a teacher with none gets art made for their id', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const TeacherAvatar(
            id: 'ds-teacher-9',
            name: 'Leigh',
            photoUrl: '',
            size: 72,
          ),
        ),
      );
      expect(findArt(teacherArt('ds-teacher-9')), findsOneWidget);
    });

    testWidgets('a course card is its art, with the photo as a corner avatar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(CardArt(art: courseArt('ds-retreat-1'), url: _photo)),
      );
      expect(findArt(courseArt('ds-retreat-1')), findsOneWidget);
      // The photo is the avatar, a picture of its own.
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('a course with no photo has no avatar', (tester) async {
      await tester.pumpWidget(_app(CardArt(art: courseArt('ds-retreat-1'))));
      expect(findArt(courseArt('ds-retreat-1')), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
