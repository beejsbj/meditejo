import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/categories/category_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/category_service.dart';
import 'package:medito/services/categories/entry_labels.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/views/categories/category_chips.dart';
import 'package:medito/views/categories/category_view.dart';
import 'package:medito/views/library/library_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

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

final _catalogue = CategoryCatalogue.parse(
  File(categoriesAsset).readAsStringSync(),
);

List<Override> _overrides(LibraryTestApp app) => [
  dharmaSeedDatabaseProvider.overrideWithValue(app.harness.dsDb),
  inProgressItemsProvider.overrideWith((ref) async => const []),
  packTrackIdsProvider.overrideWith((ref) async => const {}),
  categoryCatalogueProvider.overrideWith((ref) async => _catalogue),
];

Future<LibraryTestApp> _library(WidgetTester tester) async {
  final app = await LibraryTestApp.create(tester);
  final store = app.harness.store;
  await _add(tester, store, 'ds-retreat-1', 'Practising the Jhānas');
  await _add(tester, store, 'yt-playlist-q', 'Qualia Mastery');
  await _add(
    tester,
    store,
    'lib-track-a',
    'Body scan',
    kind: LibraryKind.single,
  );
  await _add(
    tester,
    store,
    'ds-talk-2',
    'On emptiness',
    kind: LibraryKind.single,
    group: LibraryGroup.talks,
  );
  return app;
}

Finder _text(String text) => find.text(text, skipOffstage: false);

void main() {
  group('the Library\'s category and label chips', () {
    testWidgets('appear for what the library holds, and narrow it', (
      tester,
    ) async {
      final app = await _library(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides(app));

      // Jhāna, Body and Emptiness come from the titles; Qualia has none.
      for (final id in ['jhana', 'body', 'emptiness']) {
        expect(
          find.byKey(ValueKey('library_label_$id')),
          findsOneWidget,
          reason: id,
        );
      }
      expect(find.byKey(const ValueKey('library_label_metta')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('library_label_body')));
      await settle(tester);
      expect(_text('Body scan'), findsOneWidget);
      expect(_text('Practising the Jhānas'), findsNothing);
      expect(_text('Qualia Mastery'), findsNothing);
      expect(_text('On emptiness'), findsNothing);

      // Tapping the chosen chip again shows everything.
      await tester.tap(find.byKey(const ValueKey('library_label_body')));
      await settle(tester);
      expect(_text('Practising the Jhānas'), findsOneWidget);
      expect(_text('Qualia Mastery'), findsOneWidget);
    });

    testWidgets('are not shown when nothing is labelled', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await _add(tester, app.harness.store, 'yt-playlist-q', 'Qualia Mastery');
      await app.pump(tester, const LibraryView(), overrides: _overrides(app));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              (w.key! as ValueKey).value.toString().startsWith(
                'library_label_',
              ),
        ),
        findsNothing,
      );
    });

    testWidgets('the entry menu sets a category, and a label of one\'s own', (
      tester,
    ) async {
      final app = await _library(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides(app));

      await tester.tap(
        find.byKey(const ValueKey('library_menu_yt-playlist-q')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('library_menu_labels')));
      await settle(tester);

      // Metta is not ticked; ticking it pins it.
      final metta = find.byKey(const ValueKey('labels_category_metta'));
      expect(tester.widget<FilterChip>(metta).selected, isFalse);
      await tester.tap(metta);
      await settle(tester);
      expect(tester.widget<FilterChip>(metta).selected, isTrue);

      // 36 chips: the field sits below the fold.
      final field = find.byKey(const ValueKey('labels_field'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Evening');
      await tester.tap(find.byKey(const ValueKey('labels_add')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('labels_custom_Evening')),
        findsOneWidget,
      );

      final stored = await tester.runAsync(app.harness.store.userLabels);
      expect(stored!['yt-playlist-q']!.added, {
        'metta': '',
        'evening': 'Evening',
      });

      // Close the sheet: the Library now offers both as filters.
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await settle(tester);
      expect(find.byKey(const ValueKey('library_label_metta')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('library_label_evening')),
        findsOneWidget,
      );
    });

    testWidgets('unticking a guessed category removes it for good', (
      tester,
    ) async {
      final app = await _library(tester);
      await app.pump(tester, const LibraryView(), overrides: _overrides(app));
      expect(find.byKey(const ValueKey('library_label_body')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library_menu_lib-track-a')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('library_menu_labels')));
      await settle(tester);
      final body = find.byKey(const ValueKey('labels_category_body'));
      expect(tester.widget<FilterChip>(body).selected, isTrue);
      await tester.tap(body);
      await settle(tester);
      expect(tester.widget<FilterChip>(body).selected, isFalse);

      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await settle(tester);
      expect(find.byKey(const ValueKey('library_label_body')), findsNothing);
      final stored = await tester.runAsync(app.harness.store.userLabels);
      expect(stored!['lib-track-a']!.excluded, {'body'});
    });
  });

  group('a category page', () {
    CategoryListing listing({
      List<LibraryEntry> practice = const [],
      List<LibraryEntry> talks = const [],
      List<PackItemsModel> courses = const [],
      List<PackItemsModel> practiceSessions = const [],
      List<PackItemsModel> talkSessions = const [],
    }) => CategoryListing(
      category: _catalogue.category('jhana')!,
      libraryPractice: practice,
      libraryTalks: talks,
      courses: courses,
      practiceSessions: practiceSessions,
      talkSessions: talkSessions,
    );

    PackItemsModel course(String id, String title) => PackItemsModel(
      type: 'pack',
      id: id,
      title: title,
      subtitle: 'Rob Burbea · 2019 · 32 talks',
      path: '/packs/$id',
    );

    PackItemsModel session(String id, String title) => PackItemsModel(
      type: 'track',
      id: id,
      title: title,
      subtitle: 'Talk · Rob Burbea · 40 min',
      path: '/tracks/$id',
    );

    LibraryEntry entry(
      String id,
      String title, {
      LibraryKind kind = LibraryKind.course,
      LibraryGroup group = LibraryGroup.practice,
    }) => LibraryEntry(
      sourceId: id,
      kind: kind,
      detectedGroup: group,
      title: title,
      addedAt: DateTime.utc(2026, 10, 1),
    );

    testWidgets(
      'lists Practice before Talks, the library before the catalogue',
      (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          const CategoryView(categoryId: 'jhana'),
          overrides: [
            ..._overrides(app),
            categoryListingProvider('jhana').overrideWith(
              (ref) async => listing(
                practice: [entry('ds-retreat-1', 'My jhāna retreat')],
                talks: [
                  entry(
                    'lib-track-t',
                    'My jhāna talk',
                    kind: LibraryKind.single,
                    group: LibraryGroup.talks,
                  ),
                ],
                courses: [course('ds-retreat-2', 'Catalogue jhāna retreat')],
                practiceSessions: [session('ds-talk-3', 'Guided jhāna sit')],
                talkSessions: [session('ds-talk-4', 'A talk on jhāna')],
              ),
            ),
          ],
        );

        expect(find.text('Jhāna'), findsOneWidget); // the app bar
        expect(find.textContaining('meditative absorptions'), findsOneWidget);
        final order = [
          'Practice',
          'My jhāna retreat',
          'Catalogue jhāna retreat',
          'Guided jhāna sit',
          'Talks',
          'My jhāna talk',
          'A talk on jhāna',
        ];
        final tops = [
          for (final text in order) tester.getTopLeft(_text(text).first).dy,
        ];
        expect(
          tops,
          orderedEquals([...tops]..sort()),
          reason: order.join(', '),
        );
        expect(
          find.byKey(const ValueKey('library_ds-retreat-1')),
          findsOneWidget,
        );
      },
    );

    testWidgets('says so when nothing is in it', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const CategoryView(categoryId: 'tmi'),
        overrides: [
          ..._overrides(app),
          categoryListingProvider('tmi').overrideWith(
            (ref) async =>
                CategoryListing(category: _catalogue.category('tmi')!),
          ),
        ],
      );
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Practice'), findsNothing);
    });
  });

  group('the entry points', () {
    testWidgets('Explore offers the categories with something in them', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: ExploreCategoryChips()),
        ),
        overrides: [
          ..._overrides(app),
          browsableCategoriesProvider.overrideWith(
            (ref) async => {'metta', 'breath', 'walking'},
          ),
          categoryListingProvider('breath').overrideWith(
            (ref) async =>
                CategoryListing(category: _catalogue.category('breath')!),
          ),
        ],
      );
      for (final c in _catalogue.categories) {
        expect(
          find.byKey(ValueKey('category_${c.id}'), skipOffstage: false),
          {'metta', 'breath', 'walking'}.contains(c.id)
              ? findsOneWidget
              : findsNothing,
          reason: c.id,
        );
      }
      final chip = find.byKey(const ValueKey('category_breath'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await settle(tester);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Breath'), findsWidgets);
    });

    testWidgets('a course page shows its categories and the user\'s labels', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const Scaffold(
          body: CategoryChips(subject: (id: 'ds-retreat-1', title: 'x')),
        ),
        overrides: [
          ..._overrides(app),
          labelsOfProvider((id: 'ds-retreat-1', title: 'x')).overrideWith(
            (ref) async => const EntryLabels(
              categories: [
                CategoryAssignment('metta', CategorySource.curated),
                CategoryAssignment('jhana', CategorySource.user),
              ],
              custom: ['Evening'],
            ),
          ),
        ],
      );
      expect(find.byKey(const ValueKey('category_chip_metta')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_chip_jhana')), findsOneWidget);
      expect(find.byKey(const ValueKey('label_chip_Evening')), findsOneWidget);
    });

    testWidgets('an unlabelled item shows no chips and takes no room', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const Scaffold(
          body: CategoryChips(
            subject: (id: 'yt-playlist-q', title: 'Qualia Mastery'),
            padding: EdgeInsets.all(40),
          ),
        ),
        overrides: _overrides(app),
      );
      expect(find.byType(Wrap), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });
  });
}
