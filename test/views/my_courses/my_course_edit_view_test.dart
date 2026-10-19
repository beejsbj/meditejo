import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/my_courses/my_course_edit_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/fake_session_source.dart';
import '../../helpers/library_app.dart';

MyItemDraft draft(String id) => MyItemDraft(
  id: id,
  title: 'Session $id',
  subtitle: 'Teacher of $id',
  durationMs: 600000,
);

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

void main() {
  late LibraryTestApp app;
  late FakeSessionSource upstream;
  late MyCourseSource source;

  Future<void> setUpApp(WidgetTester tester) async {
    app = await LibraryTestApp.create(tester);
    upstream = FakeSessionSource();
    source = MyCourseSource(
      db: app.harness.db,
      library: app.harness.store,
      sources: () => [upstream],
    );
    addTearDown(source.dispose);
  }

  Future<String> course(
    WidgetTester tester,
    String title,
    List<MyCourseLine> lines,
  ) async =>
      (await tester.runAsync(() => source.create(title: title, lines: lines)))!;

  Future<void> pump(WidgetTester tester, Widget page) => app.pump(
    tester,
    page,
    asRoute: true,
    overrides: [myCourseSourceProvider.overrideWithValue(source)],
  );

  List<String> lineIds(MyCourseEdit edit) => [
    for (final line in edit.lines)
      line.isHeading ? '# ${line.heading}' : line.item!.id,
  ];

  group('the course edit screen', () {
    testWidgets('shows the course: title, kind, sessions and headings', (
      tester,
    ) async {
      await setUpApp(tester);
      final id = await course(tester, 'My jhāna curriculum', [
        const MyCourseLine.heading('Day 1'),
        MyCourseLine.session(draft('x-1')),
        MyCourseLine.session(draft('x-2'), unavailable: true),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      expect(find.text('Edit course'), findsOneWidget);
      expect(find.text('My jhāna curriculum'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Day 1'), findsOneWidget);
      expect(find.text('Session x-1'), findsOneWidget);
      expect(find.textContaining('Unavailable'), findsOneWidget);
    });

    testWidgets('saves a rename, a removal, a new heading and the kind', (
      tester,
    ) async {
      await setUpApp(tester);
      final id = await course(tester, 'Before', [
        MyCourseLine.session(draft('x-1')),
        MyCourseLine.session(draft('x-2')),
        MyCourseLine.session(draft('x-3')),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      await tester.enterText(
        find.byKey(const ValueKey('my_course_title')),
        'After',
      );
      await tester.tap(find.text('Talks'));
      await tester.pump();
      // Rows are keyed in load order: x-1 is 0, x-2 is 1.
      await tester.tap(find.byKey(const ValueKey('my_course_remove_1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('my_course_add_heading')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('my_course_heading_3')),
        'Week 1',
      );
      await tester.tap(find.byKey(const ValueKey('my_course_save')));
      await settle(tester);

      expect(find.text('root'), findsOneWidget);
      final saved = (await tester.runAsync(() => source.edit(id)))!;
      expect(saved.title, 'After');
      expect(saved.group, LibraryGroup.talks);
      expect(lineIds(saved), ['# Week 1', 'x-1', 'x-3']);
    });

    testWidgets('drags a session into a new place', (tester) async {
      await setUpApp(tester);
      final id = await course(tester, 'C', [
        MyCourseLine.session(draft('x-1')),
        MyCourseLine.session(draft('x-2')),
        MyCourseLine.session(draft('x-3')),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      final handle = find.byIcon(Icons.drag_handle_rounded).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('my_course_save')));
      await settle(tester);

      final saved = (await tester.runAsync(() => source.edit(id)))!;
      expect(lineIds(saved).first, isNot('x-1'));
      expect(lineIds(saved).toSet(), {'x-1', 'x-2', 'x-3'});
    });

    testWidgets('chooses a cover from the sessions\' artwork', (tester) async {
      await setUpApp(tester);
      final id = await course(tester, 'C', [
        MyCourseLine.session(
          const MyItemDraft(
            id: 'x-1',
            title: 'One',
            coverUrl: 'https://img.test/x-1.jpg',
          ),
        ),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      await tester.tap(find.byKey(const ValueKey('my_course_cover_1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('my_course_save')));
      await settle(tester);

      final saved = (await tester.runAsync(() => source.edit(id)))!;
      expect(saved.coverUrl, 'https://img.test/x-1.jpg');
    });

    testWidgets('leaving with changes asks, and Discard keeps the course', (
      tester,
    ) async {
      await setUpApp(tester);
      final id = await course(tester, 'Kept', [
        MyCourseLine.session(draft('x-1')),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      await tester.enterText(
        find.byKey(const ValueKey('my_course_title')),
        'Changed',
      );
      // The frame that applies the typing, as one always does on a device.
      await tester.pump();
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my_course_discard')));
      await settle(tester);

      expect(find.text('root'), findsOneWidget);
      expect((await tester.runAsync(() => source.edit(id)))!.title, 'Kept');
    });

    testWidgets('deleting asks first and leaves the sessions alone', (
      tester,
    ) async {
      await setUpApp(tester);
      final id = await course(tester, 'Doomed', [
        MyCourseLine.session(draft('x-1')),
      ]);
      await pump(tester, MyCourseEditView(courseId: id));

      await tester.ensureVisible(
        find.byKey(const ValueKey('my_course_delete')),
      );
      await tester.tap(find.byKey(const ValueKey('my_course_delete')));
      await settle(tester);
      expect(find.text('Delete this course?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my_course_delete_confirm')));
      await settle(tester);

      expect(find.text('root'), findsOneWidget);
      expect(await tester.runAsync(() => source.edit(id)), isNull);
      expect(await tester.runAsync(() => app.harness.store.entry(id)), isNull);
    });
  });

  group('Add to course…', () {
    testWidgets('adds a session to a course the user picks', (tester) async {
      await setUpApp(tester);
      final id = await course(tester, 'Evening sits', const []);
      await pump(
        tester,
        Scaffold(
          body: Center(
            child: ContentActionsButton(id: 'x-7', fallback: draft('x-7')),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('content_actions_x-7')));
      await settle(tester);
      await tester.tap(find.text('Add to course…'));
      await settle(tester);
      expect(find.text('New course'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('add_to_$id')));
      await settle(tester);

      expect(find.text('Added to Evening sits'), findsOneWidget);
      final edit = (await tester.runAsync(() => source.edit(id)))!;
      expect(lineIds(edit), ['x-7']);
    });

    testWidgets('or starts a new course with it', (tester) async {
      await setUpApp(tester);
      await pump(
        tester,
        Scaffold(
          body: Center(
            child: ContentActionsButton(id: 'x-7', fallback: draft('x-7')),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('content_actions_x-7')));
      await settle(tester);
      await tester.tap(find.text('Add to course…'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('add_to_new_course')));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('new_course_name')),
        'My jhāna curriculum',
      );
      await tester.tap(find.byKey(const ValueKey('new_course_create')));
      await settle(tester);

      final made = (await tester.runAsync(() => source.courses()))!.single;
      expect(made.title, 'My jhāna curriculum');
      expect(made.sessionCount, 1);
      final entry = await tester.runAsync(
        () => app.harness.store.entry(made.id),
      );
      expect(entry!.group, LibraryGroup.practice);
    });

    testWidgets('a course row also offers Make my own copy', (tester) async {
      await setUpApp(tester);
      await pump(
        tester,
        const Scaffold(
          body: Center(
            child: ContentActionsButton(id: 'ds-retreat-4496', title: 'R'),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('content_actions_ds-retreat-4496')),
      );
      await settle(tester);
      expect(find.text('Add to course…'), findsOneWidget);
      expect(find.text('Make my own copy'), findsOneWidget);
      expect(find.text('Edit course'), findsNothing);
    });

    test('a personal course\'s actions include Edit and Delete', () {
      expect(contentActionsFor('my-course-1'), [
        ContentAction.edit,
        ContentAction.addToCourse,
        ContentAction.duplicate,
        ContentAction.delete,
      ]);
      expect(contentActionsFor('x-1', inCourse: 'my-course-1'), [
        ContentAction.addToCourse,
        ContentAction.removeFromCourse,
      ]);
      expect(contentActionsFor('x-1', inCourse: 'ds-retreat-1'), [
        ContentAction.addToCourse,
      ]);
    });
  });
}
