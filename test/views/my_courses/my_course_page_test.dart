import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/my_courses/my_course_edit_view.dart';
import 'package:medito/views/pack/pack_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/fake_session_source.dart';
import '../../helpers/library_app.dart';

MyItemDraft draft(String id) => MyItemDraft(
  id: id,
  title: 'Session $id',
  subtitle: 'Teacher of $id',
  durationMs: 600000,
);

/// A playlist (a "my course" in code) opened as a course page: PackView,
/// unchanged, reads it through `MyCourseSource`.
void main() {
  late LibraryTestApp app;
  late FakeSessionSource upstream;
  late MyCourseSource source;

  Future<String> setUp(WidgetTester tester, List<MyCourseLine> lines) async {
    app = await LibraryTestApp.create(tester);
    upstream = FakeSessionSource();
    source = MyCourseSource(
      db: app.harness.db,
      library: app.harness.store,
      sources: () => [upstream],
    );
    addTearDown(source.dispose);
    return (await tester.runAsync(
      () => source.create(title: 'My jhāna curriculum', lines: lines),
    ))!;
  }

  Future<void> pump(WidgetTester tester, String id) => app.pump(
    tester,
    PackView(id: id),
    asRoute: true,
    overrides: [myCourseSourceProvider.overrideWithValue(source)],
  );

  testWidgets('shows headings, sessions and Edit', (tester) async {
    final id = await setUp(tester, [
      const MyCourseLine.heading('Day 1'),
      MyCourseLine.session(draft('x-1')),
      MyCourseLine.session(draft('x-2')),
      const MyCourseLine.heading('Day 2'),
      MyCourseLine.session(draft('x-3')),
    ]);
    await pump(tester, id);

    expect(find.text('My jhāna curriculum'), findsWidgets);
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.text('Day 2'), findsOneWidget);
    for (final s in ['x-1', 'x-2', 'x-3']) {
      expect(find.text('Session $s'), findsOneWidget);
    }
    // Its own playlist: Edit, not "Add to library", and it says what it is
    // where a course shows its source.
    expect(find.byKey(const ValueKey('my_course_edit')), findsOneWidget);
    expect(find.text('Add to library'), findsNothing);
    expect(find.text('Playlist'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('my_course_edit')));
    await DharmaSeedTestApp.settle(tester);
    expect(find.byType(MyCourseEditView), findsOneWidget);
  });

  testWidgets('a session gone upstream stays, marked, and is not counted', (
    tester,
  ) async {
    final id = await setUp(tester, [
      MyCourseLine.session(draft('x-1')),
      MyCourseLine.session(draft('x-2')),
    ]);
    upstream.gone.add('x-1');
    await pump(tester, id);

    expect(find.text('Session x-1'), findsOneWidget);
    // The kind label, in capitals like every kind.
    expect(find.text('UNAVAILABLE'), findsOneWidget);
    // Progress counts the one session that can still be played.
    expect(find.textContaining('of 1'), findsWidgets);

    await tester.tap(find.text('Session x-1'));
    await DharmaSeedTestApp.settle(tester);
    expect(
      find.text('This session is no longer available from its source.'),
      findsOneWidget,
    );
    expect(find.byType(PackView), findsOneWidget);
  });

  testWidgets('an empty playlist says how to fill it', (tester) async {
    final id = await setUp(tester, const []);
    await pump(tester, id);

    expect(find.byKey(const ValueKey('my_course_empty')), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
  });
}
