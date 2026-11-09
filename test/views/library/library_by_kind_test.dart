import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/categories/category_catalogue.dart';
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

Future<void> _pump(WidgetTester tester, LibraryTestApp app) =>
    app.pump(tester, const LibraryView());

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

  testWidgets('a retreat saved while the Library is open shows under Talks', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await tester.runAsync(() => seedDharmaSeedCatalogue(app.harness.dsDb));
    await _add(
      tester,
      app.harness.store,
      'lib-track-a',
      'Body scan',
      kind: LibraryKind.single,
    );
    await _pump(tester, app);
    // Read once already, before the retreat is in the library.
    expect(find.text('Talks 0'), findsOneWidget);

    await _add(tester, app.harness.store, 'ds-retreat-100', 'Jhana Retreat');
    await _settle(tester);
    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsOneWidget);
    expect(find.text('Talks 1'), findsOneWidget);
  });

  testWidgets('a retreat saved before its talks are stored moves under '
      'Talks once the sync stores them', (tester) async {
    final app = await LibraryTestApp.create(tester);
    final db = app.harness.dsDb;
    // The retreat's own record, with its talk IDs, but none of its talks.
    await tester.runAsync(
      () => db.upsertRetreatRecords({
        100: {
          'name': 'Jhana Retreat',
          'description': '',
          'start_date': '2014-03-01',
          'talks': [1, 2],
        },
      }),
    );
    await _add(tester, app.harness.store, 'ds-retreat-100', 'Jhana Retreat');
    // Stands in for the background sync's "stored more" signal.
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await app.pump(
      tester,
      const LibraryView(),
      overrides: [
        dharmaSeedRevisionProvider.overrideWith(
          () => ValueListenableNotifier((ref) => revision),
        ),
      ],
    );
    expect(find.text('Practice 1'), findsOneWidget);
    expect(find.text('Talks 0'), findsOneWidget);

    await tester.runAsync(
      () => db.upsertTalkRecords({
        1: dsTalkRecord(
          'Settling',
          teacher: 1,
          retreat: 100,
          type: 'Meditation',
        ),
        2: dsTalkRecord('Jhana basics', teacher: 1, retreat: 100),
      }),
    );
    revision.value++;
    await tester.pump();
    // Not at once: the re-read waits out the debounce.
    expect(find.text('Talks 0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await _settle(tester);
    expect(find.text('Talks 1'), findsOneWidget);
  });

  testWidgets('a retreat cached with an empty list is read again', (
    tester,
  ) async {
    final app = await _library(tester);
    // As if the track lists were read before the retreat's record was
    // stored: known, but empty.
    await app.pump(
      tester,
      const LibraryView(),
      overrides: [
        packTrackIdsProvider.overrideWith(
          (ref) async => {'ds-retreat-100': <String>[]},
        ),
      ],
    );
    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsOneWidget);
  });

  Future<Set<String>> menuOf(WidgetTester tester, String id) async {
    final menu = find.byKey(ValueKey('library_menu_$id'));
    await tester.ensureVisible(menu);
    await tester.tap(menu);
    await _settle(tester);
    final items = {
      for (final tile in tester.widgetList<ListTile>(
        find.descendant(
          of: find.byKey(const ValueKey('item_actions_sheet')),
          matching: find.byType(ListTile),
        ),
      ))
        (tile.title! as Text).data!,
    };
    return items;
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await tester.tap(find.text(item));
    await _settle(tester);
  }

  testWidgets('a mixed retreat can be put under Practice alone, and back', (
    tester,
  ) async {
    final app = await _library(tester);
    await _pump(tester, app);
    const id = 'ds-retreat-100';

    // Under both: either move is offered; there is no choice to forget.
    var menu = await menuOf(tester, id);
    expect(menu, containsAll(['Move to Practice', 'Move to Talks']));
    expect(menu, isNot(contains('Show by sessions')));
    await choose(tester, 'Move to Practice');

    // Kept, though it is what the app detected.
    final entry = await tester.runAsync(() => app.harness.store.entry(id));
    expect(entry!.groupOverride, LibraryGroup.practice);
    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsNothing);
    await _tap(tester, 'practice');
    expect(_shown('Jhana Retreat'), findsOneWidget);

    menu = await menuOf(tester, id);
    expect(menu, contains('Move to Talks'));
    expect(menu, isNot(contains('Move to Practice')));
    expect(menu, contains('Show by sessions'));
    await choose(tester, 'Show by sessions');

    final cleared = await tester.runAsync(() => app.harness.store.entry(id));
    expect(cleared!.groupOverride, isNull);
    await _tap(tester, 'talks');
    expect(_shown('Jhana Retreat'), findsOneWidget);
  });

  testWidgets('a label that leaves nothing says so, not the chip\'s words', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await _add(
      tester,
      app.harness.store,
      'lib-track-a',
      'Body scan',
      kind: LibraryKind.single,
    );
    await _add(
      tester,
      app.harness.store,
      'ds-talk-2',
      'On emptiness',
      kind: LibraryKind.single,
      group: LibraryGroup.talks,
    );
    final catalogue = CategoryCatalogue.parse(
      File(categoriesAsset).readAsStringSync(),
    );
    await app.pump(
      tester,
      const LibraryView(),
      overrides: [
        categoryCatalogueProvider.overrideWith((ref) async => catalogue),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('library_label_body')));
    await _settle(tester);
    await _tap(tester, 'talks');

    expect(find.byKey(const ValueKey('library_empty_label')), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.text('No talks here yet'), findsNothing);
  });
}
