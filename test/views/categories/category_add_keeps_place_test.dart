import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/categories/category_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/dharma_seed_catalogue.dart';

final _catalogue = CategoryCatalogue.parse(
  File(categoriesAsset).readAsStringSync(),
);

/// Thirty jhāna retreats, so the page is several screens long.
Future<DharmaSeedTestApp> _longJhanaPage(WidgetTester tester) async {
  final app = await DharmaSeedTestApp.create(tester);
  await tester.runAsync(() async {
    await app.db.upsertRetreatRecords({
      for (var i = 0; i < 30; i++)
        1000 + i: {
          'name': 'Practising the Jhānas, part ${i + 1}',
          'description': 'A jhana retreat.',
          'start_date':
              '2019-${(i ~/ 28 + 1).toString().padLeft(2, '0')}-'
              '${(i % 28 + 1).toString().padLeft(2, '0')}',
          'talks': [5000 + i],
        },
    });
    await app.db.upsertTalkRecords({
      for (var i = 0; i < 30; i++)
        5000 + i: dsTalkRecord(
          'Opening talk ${i + 1}',
          teacher: 1,
          retreat: 1000 + i,
        ),
    });
  });
  return app;
}

void main() {
  testWidgets('Add to library on a row keeps the page where it was scrolled, '
      'with one snackbar', (tester) async {
    final app = await _longJhanaPage(tester);
    await app.pump(
      tester,
      const CategoryView(categoryId: 'jhana'),
      overrides: [
        packTrackIdsProvider.overrideWith((ref) async => const {}),
        categoryCatalogueProvider.overrideWith((ref) async => _catalogue),
        dharmaSeedDatabaseProvider.overrideWithValue(app.db),
      ],
    );

    final page = find.byKey(const ValueKey('category_page_jhana'));
    expect(page, findsOneWidget);
    final scrollable = find.descendant(
      of: page,
      matching: find.byType(Scrollable),
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(scrollable.first).position;

    // Well down the page: a row some way into the courses.
    const id = 'ds-retreat-1012';
    final add = find.byKey(const ValueKey('add_to_library_$id'));
    await tester.scrollUntilVisible(
      add,
      300,
      scrollable: scrollable.first,
      maxScrolls: 60,
    );
    await DharmaSeedTestApp.settle(tester, rounds: 2);
    final before = position().pixels;
    expect(before, greaterThan(400));
    final rowBefore = tester.getTopLeft(
      find.byKey(const ValueKey('course_$id')),
    );

    await tester.tap(add);
    // The frames while the library and then the listing are re-read: the
    // list is never swapped for a spinner.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(page, findsOneWidget, reason: 'frame $i');
      expect(position().pixels, before, reason: 'frame $i');
    }
    expect(await tester.runAsync(() => app.library.contains(id)), isTrue);

    // Still there, in the same place, now ticked; one Undo snackbar.
    expect(position().pixels, before);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('course_$id'))),
      rowBefore,
    );
    expect(tester.widget<IconButton>(add).tooltip, 'In library');
    expect(find.byKey(const ValueKey('library_$id')), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Added to your library'), findsOneWidget);

    // Undo puts it back as it was, and the page still does not move.
    await tester.tap(find.text('Undo'));
    await DharmaSeedTestApp.settle(tester);
    expect(await tester.runAsync(() => app.library.contains(id)), isFalse);
    expect(position().pixels, before);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('course_$id'))),
      rowBefore,
    );
    expect(tester.widget<IconButton>(add).tooltip, 'Add to library');
  });

  group('CategoryListing.keepingPlace', () {
    final jhana = _catalogue.category('jhana')!;
    PackItemsModel item(String id) =>
        PackItemsModel(type: 'pack', id: id, title: id, path: '/packs/$id');
    LibraryEntry entry(
      String id, {
      LibraryGroup group = LibraryGroup.practice,
    }) => LibraryEntry(
      sourceId: id,
      kind: LibraryKind.course,
      detectedGroup: group,
      title: id,
      addedAt: DateTime.utc(2026, 10, 1),
    );

    test('a row added to the library stays in its place', () {
      final shown = CategoryListing(
        category: jhana,
        libraryPractice: [entry('ds-retreat-9')],
        courses: [
          item('ds-retreat-1'),
          item('ds-retreat-2'),
          item('ds-retreat-3'),
        ],
        talkSessions: [item('ds-talk-7'), item('ds-talk-8')],
      );
      final next = CategoryListing(
        category: jhana,
        libraryPractice: [entry('ds-retreat-2'), entry('ds-retreat-9')],
        libraryTalks: [entry('ds-talk-8', group: LibraryGroup.talks)],
        courses: [item('ds-retreat-1'), item('ds-retreat-3')],
        talkSessions: [item('ds-talk-7')],
      ).keepingPlace(shown);

      expect(next.courses.map((c) => c.id), [
        'ds-retreat-1',
        'ds-retreat-2',
        'ds-retreat-3',
      ]);
      expect(next.libraryPractice.map((e) => e.sourceId), ['ds-retreat-9']);
      expect(next.talkSessions.map((c) => c.id), ['ds-talk-7', 'ds-talk-8']);
      expect(next.libraryTalks, isEmpty);
    });

    test('a row that left for another reason goes; a new one is added', () {
      final shown = CategoryListing(
        category: jhana,
        courses: [item('ds-retreat-1'), item('ds-retreat-2')],
      );
      final next = CategoryListing(
        category: jhana,
        courses: [item('ds-retreat-2'), item('ds-retreat-4')],
      );
      final kept = next.keepingPlace(shown);
      expect(identical(kept, next), isTrue);
      expect(kept.courses.map((c) => c.id), ['ds-retreat-2', 'ds-retreat-4']);
    });
  });
}
