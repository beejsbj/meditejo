import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/views/library/library_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/library_app.dart';

// #80: Practice and Talks are chips that go by what a course's sessions are,
// read from Dharma Seed's stored talks, not by one kind per course.

Future<void> _settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

Future<void> _tap(WidgetTester tester, String filter) async {
  final chip = find.byKey(ValueKey('library_filter_$filter'));
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await _settle(tester);
}

Future<void> _add(
  WidgetTester tester,
  LibraryStore store,
  String id,
  String title, {
  LibraryKind kind = LibraryKind.course,
  LibraryGroup group = LibraryGroup.practice,
}) => tester.runAsync(
  () => store.add(
    LibraryDraft(sourceId: id, kind: kind, title: title, group: group),
  ),
);

Finder _shown(String title) => find.text(title, skipOffstage: false);

/// The shared catalogue (retreat 100: three sittings and a talk; 200: a talk
/// and a Q & A; 300: a sitting and a talk; talk 9 with no recording type) and
/// a library holding some of it, filed as Dharma Seed files it: retreats as
/// Practice.
Future<LibraryTestApp> _library(WidgetTester tester) async {
  final app = await LibraryTestApp.create(tester);
  await tester.runAsync(() => seedDharmaSeedCatalogue(app.harness.dsDb));
  final store = app.harness.store;
  await _add(tester, store, 'ds-retreat-100', 'Jhana Retreat');
  await _add(tester, store, 'ds-retreat-200', 'Dharma Talks Winter');
  // Saved before its talks were stored: nothing known about its sessions.
  await _add(tester, store, 'ds-retreat-999', 'Not synced yet');
  await _add(
    tester,
    store,
    'ds-talk-9',
    'Untyped talk about jhana',
    kind: LibraryKind.single,
    group: LibraryGroup.talks,
  );
  return app;
}

Future<void> _pump(WidgetTester tester, LibraryTestApp app) => app.pump(
  tester,
  const LibraryView(),
  overrides: [inProgressItemsProvider.overrideWith((ref) async => const [])],
);

void main() {
  testWidgets('a mixed Dharma Seed retreat shows under both chips', (
    tester,
  ) async {
    final app = await _library(tester);
    await _pump(tester, app);

    await _tap(tester, 'practice');
    expect(_shown('Jhana Retreat'), findsOneWidget);
    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsOneWidget);
  });

  testWidgets('talks in a retreat add Talks; it keeps the Practice it was '
      'filed under', (tester) async {
    final app = await _library(tester);
    await _pump(tester, app);

    await _tap(tester, 'talks');
    expect(_shown('Dharma Talks Winter'), findsOneWidget);
    await _tap(tester, 'practice');
    expect(_shown('Dharma Talks Winter'), findsOneWidget);
  });

  testWidgets('with no sessions known, an entry shows under its own kind', (
    tester,
  ) async {
    final app = await _library(tester);
    await _pump(tester, app);

    await _tap(tester, 'practice');
    expect(_shown('Not synced yet'), findsOneWidget);
    expect(_shown('Untyped talk about jhana'), findsNothing);
    await _tap(tester, 'talks');
    expect(_shown('Not synced yet'), findsNothing);
    expect(_shown('Untyped talk about jhana'), findsOneWidget);
    // Practice: the three retreats; Talks: two retreats and the talk.
    expect(find.text('Practice 3'), findsOneWidget);
    expect(find.text('Talks 3'), findsOneWidget);
  });

  testWidgets('Move to Talks puts a mixed retreat under Talks alone', (
    tester,
  ) async {
    final app = await _library(tester);
    await tester.runAsync(
      () => app.harness.store.setGroup('ds-retreat-100', LibraryGroup.talks),
    );
    await _pump(tester, app);

    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsOneWidget);
    await _tap(tester, 'practice');
    expect(_shown('Jhana Retreat'), findsNothing);
    expect(find.text('Practice 2'), findsOneWidget);

    // Moving it back to what the app filed it as clears the choice: under
    // both again.
    await tester.runAsync(
      () => app.harness.store.setGroup('ds-retreat-100', null),
    );
    await _settle(tester);
    expect(_shown('Jhana Retreat'), findsOneWidget);
  });
}
