import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/dharma_seed/widgets/session_rows_sliver.dart';
import 'package:medito/views/library/item_actions.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';

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

    test('no teacher id hides Go to teacher (a YouTube row)', () {
      final actions = itemActionsFor(const ItemActionsSpec(id: 'yt-video-a'));
      expect(actions, isNot(contains(ItemAction.goToTeacher)));
    });

    test('Mark as played needs a course to write the state to', () {
      final actions = itemActionsFor(const ItemActionsSpec(id: 'ds-talk-1'));
      expect(actions, isNot(contains(ItemAction.markPlayed)));
    });

    test('a downloaded session does not offer Download again', () {
      final actions = itemActionsFor(
        const ItemActionsSpec(id: 'ds-talk-1'),
        downloaded: true,
      );
      expect(actions, isNot(contains(ItemAction.download)));
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
      // The owner removed Favourites; Pin is for courses only.
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
      expect(items, isNot(contains('Mark as played')));
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
