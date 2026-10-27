import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cover_art.dart';

import '../../helpers/art_finders.dart';
import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

const _photo = 'https://www.dharmaseed.org/api/1/teachers/210/p.png/?maxW=400';
const _thumb = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';

const _course = 'ds-retreat-1';
const _playlist = 'my-course-0123456789abcdef';
const _talk = 'ds-talk-2';
const _teacher = 'ds-teacher-210';

Future<void> _add(
  WidgetTester tester,
  LibraryStore store,
  String id,
  String title,
  LibraryKind kind, {
  String coverUrl = '',
}) => tester.runAsync(
  () => store.add(
    LibraryDraft(sourceId: id, kind: kind, title: title, coverUrl: coverUrl),
  ),
);

final _overrides = [
  packTrackIdsProvider.overrideWith((ref) async => const {}),
  inProgressItemsProvider.overrideWith((ref) async => const []),
];

void main() {
  setUpAll(holdCuratedArt);

  testWidgets('the library draws each entry\'s art by its id and kind', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    final store = app.harness.store;
    // A Dharma Seed course and talk as they were stored, with the lead
    // teacher's photo as their coverUrl.
    await _add(
      tester,
      store,
      _course,
      'Practising the Jhānas',
      LibraryKind.course,
      coverUrl: _photo,
    );
    await _add(tester, store, _playlist, 'Morning sits', LibraryKind.course);
    await _add(
      tester,
      store,
      _talk,
      'On emptiness',
      LibraryKind.single,
      coverUrl: _photo,
    );
    await _add(
      tester,
      store,
      _teacher,
      'Rob Burbea',
      LibraryKind.teacher,
      coverUrl: _photo,
    );
    await app.pump(tester, const LibraryView(), overrides: _overrides);

    expect(findArt(courseArt(_course)), findsOneWidget);
    expect(
      findArt(const ArtSubject.cover(ArtCoverKind.playlist, _playlist)),
      findsOneWidget,
    );
    expect(findArt(singleArt(_talk)), findsOneWidget);
    // The teacher shows their photo; there is no art for them.
    expect(findArt(teacherArt(_teacher)), findsNothing);
    expect(
      artKeys(tester),
      containsAll([
        'cover:course:$_course',
        'cover:playlist:$_playlist',
        'cover:single:$_talk',
      ]),
    );
  });

  testWidgets('a renamed library entry keeps its art', (tester) async {
    final app = await LibraryTestApp.create(tester);
    final store = app.harness.store;
    await _add(tester, store, _playlist, 'Morning sits', LibraryKind.course);
    await app.pump(tester, const LibraryView(), overrides: _overrides);
    final before = artKeys(tester);
    expect(before, contains('cover:playlist:$_playlist'));

    await tester.runAsync(() => store.setTitle(_playlist, 'Evening sits'));
    await tester.pump();
    await DharmaSeedTestApp.settle(tester);

    expect(find.text('Evening sits', skipOffstage: false), findsWidgets);
    expect(artKeys(tester), before);
  });

  testWidgets('a real cover still wins in the library', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await _add(
      tester,
      app.harness.store,
      'yt-playlist-q',
      'Qualia Mastery',
      LibraryKind.course,
      coverUrl: _thumb,
    );
    await app.pump(tester, const LibraryView(), overrides: _overrides);
    expect(find.byType(ArtCover), findsNothing);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('a course is the same subject in the library, on a card and '
      'pinned to Home', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await _add(
      tester,
      app.harness.store,
      _course,
      'Practising the Jhānas',
      LibraryKind.course,
    );

    Future<Set<String>> keysOf(Widget page) async {
      await app.pump(tester, page, overrides: _overrides);
      return artKeys(tester);
    }

    final inLibrary = await keysOf(const LibraryView());
    final onCard = await keysOf(
      Scaffold(
        body: CustomScrollView(
          slivers: [
            CourseRowsSliver(
              courses: const [
                PackItemsModel(
                  type: 'pack',
                  id: _course,
                  title: 'A different title from the search',
                  path: '/packs/$_course',
                ),
              ],
            ),
          ],
        ),
      ),
    );
    final pinned = await keysOf(
      const Scaffold(body: PinnedCourseTile(id: _course)),
    );

    final expected = {'cover:course:$_course'};
    expect(inLibrary.where((k) => k.contains(_course)), expected);
    expect(onCard, expected);
    expect(pinned, expected);
  });
}
