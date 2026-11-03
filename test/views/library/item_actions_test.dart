import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/player/download/audio_downloader_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/pack/widgets/course_actions.dart';
import 'package:medito/views/track/track_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

LibraryEntry entry(String id, {LibraryKind kind = LibraryKind.single}) =>
    LibraryEntry(
      sourceId: id,
      kind: kind,
      detectedGroup: LibraryGroup.practice,
      title: 'Title of $id',
      addedAt: DateTime(2026, 10, 1),
    );

void main() {
  group('which actions apply (pure)', () {
    test('a session in a course: everything a session can do', () {
      final actions = itemActionsFor(
        ItemActionsSpec(
          id: 'ds-talk-1',
          teacherId: 'ds-teacher-9',
          isComplete: false,
          onSetComplete: (_) async => true,
        ),
        canSave: true,
      );
      expect(actions, [
        ItemAction.play,
        ItemAction.addToPlaylist,
        ItemAction.save,
        ItemAction.download,
        ItemAction.markPlayed,
        ItemAction.goToTeacher,
        ItemAction.share,
      ]);
    });

    test('a course header\'s ⋮ hides what it shows as buttons; the '
        'Library\'s ⋮ and a row\'s keep them', () {
      final all = itemActionsFor(
        const ItemActionsSpec(id: 'ds-retreat-1'),
        saved: true,
      );
      expect(
        all,
        containsAll([ItemAction.play, ItemAction.pin, ItemAction.share]),
      );
      final header = itemActionsFor(
        const ItemActionsSpec(
          id: 'ds-retreat-1',
          hide: CourseMoreButton.shownAsButtons,
        ),
        saved: true,
      );
      expect(header, [
        for (final action in all)
          if (action != ItemAction.play &&
              action != ItemAction.pin &&
              action != ItemAction.share)
            action,
      ]);
      expect(
        itemActionsFor(
          ItemActionsSpec(
            id: 'ds-retreat-1',
            entry: entry('ds-retreat-1', kind: LibraryKind.course),
          ),
        ),
        containsAll([ItemAction.play, ItemAction.pin, ItemAction.share]),
      );
    });

    test('a course header\'s ⋮ never repeats its Add to library or Edit; '
        'an episode page\'s leaves out its own buttons (#84)', () {
      // Not yet saved: the header shows Add to library as a button.
      final unsaved = itemActionsFor(
        const ItemActionsSpec(id: 'ds-retreat-1'),
        canSave: true,
      );
      expect(unsaved, contains(ItemAction.save));
      expect(
        itemActionsFor(
          const ItemActionsSpec(
            id: 'ds-retreat-1',
            hide: CourseMoreButton.shownAsButtons,
          ),
          canSave: true,
        ),
        isNot(contains(ItemAction.save)),
      );
      // A playlist the user made: the header shows Edit as a button.
      const mine = 'my-course-0123456789abcdef';
      expect(
        itemActionsFor(const ItemActionsSpec(id: mine)),
        contains(ItemAction.edit),
      );
      final header = itemActionsFor(
        const ItemActionsSpec(id: mine, hide: CourseMoreButton.shownAsButtons),
      );
      expect(header, isNot(contains(ItemAction.edit)));
      expect(header, contains(ItemAction.delete));

      final episode = itemActionsFor(
        const ItemActionsSpec(
          id: 'ds-talk-1',
          teacherId: 'ds-teacher-1',
          hide: {...TrackView.shownAsButtons, ItemAction.save},
        ),
        canSave: true,
      );
      expect(episode, [ItemAction.download, ItemAction.markPlayed]);
      // Its Add to library button hidden (a saved course holds it), the ⋮
      // keeps Add to library.
      expect(
        itemActionsFor(
          const ItemActionsSpec(
            id: 'ds-talk-1',
            hide: TrackView.shownAsButtons,
          ),
          canSave: true,
        ),
        [ItemAction.save, ItemAction.download, ItemAction.markPlayed],
      );
    });

    test('no teacher id hides Go to teacher (a YouTube row)', () {
      final actions = itemActionsFor(const ItemActionsSpec(id: 'yt-video-a'));
      expect(actions, isNot(contains(ItemAction.goToTeacher)));
    });

    test('Mark as played is offered on any session, not a course or a lost '
        'one', () {
      expect(
        itemActionsFor(const ItemActionsSpec(id: 'ds-talk-1')),
        contains(ItemAction.markPlayed),
      );
      expect(
        itemActionsFor(const ItemActionsSpec(id: 'ds-retreat-1')),
        isNot(contains(ItemAction.markPlayed)),
      );
      expect(
        itemActionsFor(const ItemActionsSpec(id: 'x-1', playable: false)),
        isNot(contains(ItemAction.markPlayed)),
      );
    });

    test('Download is hidden for audio already on the device', () {
      final actions = itemActionsFor(
        const ItemActionsSpec(id: 'lib-track-1'),
        downloadable: false,
      );
      expect(actions, isNot(contains(ItemAction.download)));
    });

    test('Play on a course starts the first session not yet played', () {
      PackItemsModel track(String id) => PackItemsModel(
        type: TypeConstants.track,
        id: id,
        title: id,
        path: '/tracks/$id',
      );
      final pack = PackModel(
        id: 'ds-retreat-1',
        title: 'R',
        items: [for (var i = 1; i <= 8; i++) track('t$i')],
      );
      // Lesson 6 is next for someone who has played 1 to 5, though the raw
      // pack knows nothing about completion.
      expect(nextSessionIn(pack, {'t1', 't2', 't3', 't4', 't5'})!.id, 't6');
      expect(nextSessionIn(pack, const {})!.id, 't1');
      // A session left partway wins, as on the course page and Home.
      expect(
        nextSessionIn(
          pack,
          {'t1', 't2'},
          partial: {'t5': DateTime(2026, 10, 1)},
        )!.id,
        't5',
      );
      expect(
        nextSessionIn(pack, {for (var i = 1; i <= 8; i++) 't$i'})!.id,
        't1',
      );
    });

    test('a downloaded session does not offer Download again', () {
      final actions = itemActionsFor(
        const ItemActionsSpec(id: 'ds-talk-1'),
        downloaded: true,
      );
      expect(actions, isNot(contains(ItemAction.download)));
    });

    test('a download in progress for the session is detected', () {
      final state = AudioDownloaderState(
        audioDownloadState: {
          'ds-talk-1-f1.mp3': AudioDownloadState.downloading,
          'ds-talk-2-f1.mp3': AudioDownloadState.downloading,
          'ds-talk-3-f1.mp3': AudioDownloadState.downloaded,
          'ds-talk-12-f1.mp3': AudioDownloadState.downloading,
        },
      );
      expect(isDownloadInProgress(state, 'ds-talk-1'), isTrue);
      expect(isDownloadInProgress(state, 'ds-talk-3'), isFalse);
      // A longer id that merely starts the same is a different session.
      expect(isDownloadInProgress(state, 'ds-talk-1'), isTrue);
      expect(isDownloadInProgress(state, 'ds-talk-2'), isTrue);
      expect(isDownloadInProgress(state, 'ds-talk-4'), isFalse);
      expect(isDownloadInProgress(state, 'ds-talk-123'), isFalse);
      expect(isDownloadInProgress(const AudioDownloaderState(), 'x'), isFalse);
    });

    test('a course: no Download or Mark as played; Pin only once saved', () {
      const course = ItemActionsSpec(id: 'ds-retreat-1');
      final unsaved = itemActionsFor(course, canSave: true);
      expect(unsaved, [
        ItemAction.play,
        ItemAction.addToPlaylist,
        ItemAction.duplicate,
        ItemAction.save,
        ItemAction.share,
      ]);
      final saved = itemActionsFor(course, saved: true, canSave: true);
      expect(saved, contains(ItemAction.pin));
      expect(saved, isNot(contains(ItemAction.save)));
    });

    test('device-local things cannot be shared', () {
      for (final id in ['my-course-1', 'lib-course-1', 'lib-track-1']) {
        expect(
          itemActionsFor(ItemActionsSpec(id: id), saved: true),
          isNot(contains(ItemAction.share)),
          reason: id,
        );
      }
    });

    test('a playlist adds Edit and Delete', () {
      final actions = itemActionsFor(
        const ItemActionsSpec(id: 'my-course-1'),
        saved: true,
      );
      expect(actions, containsAll([ItemAction.edit, ItemAction.delete]));
      expect(actions, isNot(contains(ItemAction.remove)));
    });

    test('a library entry adds its own actions, and Remove', () {
      final actions = itemActionsFor(
        ItemActionsSpec(id: 'ds-talk-1', entry: entry('ds-talk-1')),
      );
      expect(
        actions,
        containsAll([
          ItemAction.moveToTalks,
          ItemAction.rename,
          ItemAction.labels,
          ItemAction.remove,
        ]),
      );
      expect(actions, isNot(contains(ItemAction.save)));
    });

    test('a session in the Library can be pinned; one outside cannot', () {
      expect(
        itemActionsFor(
          ItemActionsSpec(id: 'ds-talk-1', entry: entry('ds-talk-1')),
        ),
        contains(ItemAction.pin),
      );
      expect(
        itemActionsFor(const ItemActionsSpec(id: 'ds-talk-1'), saved: true),
        contains(ItemAction.pin),
      );
      expect(
        itemActionsFor(const ItemActionsSpec(id: 'ds-talk-1'), canSave: true),
        isNot(contains(ItemAction.pin)),
      );
    });

    test('a teacher entry can only be removed', () {
      final actions = itemActionsFor(
        ItemActionsSpec(
          id: 'ds-teacher-1',
          entry: entry('ds-teacher-1', kind: LibraryKind.teacher),
        ),
      );
      expect(actions, [ItemAction.remove]);
    });

    test('a lost session offers no Play, Download or Share', () {
      final actions = itemActionsFor(
        const ItemActionsSpec(id: 'x-1', playable: false),
      );
      expect(actions, [ItemAction.addToPlaylist]);
    });
  });

  group('the sheet', () {
    late LibraryTestApp app;

    Future<Set<String>> open(
      WidgetTester tester,
      ContentActionsButton button,
    ) async {
      app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        Scaffold(body: Center(child: button)),
        asRoute: true,
      );
      await tester.tap(find.byKey(ValueKey('content_actions_${button.id}')));
      await settle(tester);
      return {
        for (final tile in tester.widgetList<ListTile>(
          find.descendant(
            of: find.byKey(const ValueKey('item_actions_sheet')),
            matching: find.byType(ListTile),
          ),
        ))
          (tile.title! as Text).data!,
      };
    }

    testWidgets('a session row shows its items, with Go to teacher', (
      tester,
    ) async {
      final items = await open(
        tester,
        ContentActionsButton(
          id: 'ds-talk-5',
          teacherId: 'ds-teacher-210',
          isComplete: false,
          onSetComplete: (_) async => true,
        ),
      );
      expect(
        items,
        containsAll([
          'Play',
          'Add to playlist…',
          'Download audio',
          'Mark as played',
          'Go to teacher',
          'Share',
        ]),
      );
      // The owner removed Favourites; Pin is for what is in the Library.
      expect(items.any((t) => t.contains('avourite')), isFalse);
      expect(items, isNot(contains('Pin to Home')));
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.favorite), findsNothing);
    });

    testWidgets('a played row offers Mark as unplayed, and flips it', (
      tester,
    ) async {
      bool? asked;
      final items = await open(
        tester,
        ContentActionsButton(
          id: 'ds-talk-5',
          isComplete: true,
          onSetComplete: (complete) async {
            asked = complete;
            return true;
          },
        ),
      );
      expect(items, contains('Mark as unplayed'));
      await tester.tap(find.text('Mark as unplayed'));
      await settle(tester);
      expect(asked, isFalse);
    });

    testWidgets('no teacher id: Go to teacher is hidden', (tester) async {
      final items = await open(
        tester,
        const ContentActionsButton(id: 'yt-video-abc'),
      );
      expect(items, contains('Play'));
      expect(items, isNot(contains('Go to teacher')));
      // Played state is global, so any session can be marked.
      expect(items, contains('Mark as played'));
      // The sheet names what it is for.
      expect(find.byKey(const ValueKey('item_actions_title')), findsNothing);
    });

    testWidgets('a course row: no Download, no Mark as played', (tester) async {
      final items = await open(
        tester,
        const ContentActionsButton(id: 'ds-retreat-4496', title: 'R'),
      );
      expect(
        items,
        containsAll(['Play', 'Add to playlist…', 'Copy as playlist', 'Share']),
      );
      expect(items, isNot(contains('Download audio')));
      expect(items, isNot(contains('Mark as played')));
      expect(items, isNot(contains('Edit playlist')));
    });

    testWidgets('a playlist row adds Edit and Delete', (tester) async {
      final items = await open(
        tester,
        const ContentActionsButton(id: 'my-course-0123456789abcdef'),
      );
      expect(items, containsAll(['Play', 'Edit playlist', 'Delete playlist']));
    });
  });

  testWidgets('the sheet shows the item title and the played state', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const Scaffold(
        body: Center(
          child: ContentActionsButton(id: 'ds-talk-5', title: 'Equanimity'),
        ),
      ),
      asRoute: true,
      played: const ['ds-talk-5'],
    );
    await tester.tap(find.byKey(const ValueKey('content_actions_ds-talk-5')));
    await settle(tester);
    expect(find.text('Equanimity'), findsOneWidget);
    expect(find.text('Mark as unplayed'), findsOneWidget);
  });

  testWidgets('a failed Mark as played says so', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      Scaffold(
        body: Center(
          child: ContentActionsButton(
            id: 'ds-talk-5',
            isComplete: false,
            onSetComplete: (_) async => false,
          ),
        ),
      ),
      asRoute: true,
    );
    await tester.tap(find.byKey(const ValueKey('content_actions_ds-talk-5')));
    await settle(tester);
    await tester.tap(find.text('Mark as played'));
    await settle(tester);
    expect(
      find.textContaining('Couldn\'t update the played state'),
      findsOneWidget,
    );
  });

  testWidgets('long-pressing a session row opens the same sheet', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    const item = PackItemsModel(
      type: TypeConstants.track,
      id: 'ds-talk-77',
      title: 'Equanimity',
      path: '/tracks/ds-talk-77',
      teacherId: 'ds-teacher-210',
    );
    await app.pump(
      tester,
      const Scaffold(
        body: CustomScrollView(
          slivers: [
            SessionRowsSliver(items: [item]),
          ],
        ),
      ),
      asRoute: true,
    );
    await tester.longPress(find.text('Equanimity'));
    await settle(tester);
    expect(find.byKey(const ValueKey('item_actions_sheet')), findsOneWidget);
    expect(find.text('Go to teacher'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });
}
