import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/explore/widgets/explore_view.dart';
import 'package:medito/services/library/library_database.dart';

import '../../helpers/dharma_seed_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Explore', () {
    testWidgets('lists courses and teachers; singles wait for a chip', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());

      expect(find.text('Courses'), findsOneWidget);
      expect(find.text('Mixed Weekend'), findsOneWidget);
      expect(find.text('Jhana Retreat'), findsOneWidget);
      expect(find.text('Teachers'), findsOneWidget);
      // The name is also a search suggestion beside the field.
      expect(find.text('Rob Burbea'), findsNWidgets(2));
      expect(find.text('Latest talks'), findsNothing);
      expect(find.text('Latest guided practice'), findsNothing);
    });

    testWidgets('Practice narrows to guided practice, and clears on a second '
        'tap', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());
      // The search field and suggestions take room the lists used to have.
      tester.view.physicalSize = const Size(430, 2400);

      await tester.tap(find.byKey(const ValueKey('explore_chip_practice')));
      await DharmaSeedTestApp.settle(tester);

      expect(find.text('Latest guided practice'), findsOneWidget);
      expect(find.text('Dharma Talks Winter'), findsNothing); // a Talks course
      expect(find.text('Jhana Retreat'), findsOneWidget);
      expect(find.text('Settling'), findsOneWidget); // a guided meditation
      expect(find.text('Jhana basics'), findsNothing); // a talk

      await tester.tap(find.byKey(const ValueKey('explore_chip_practice')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Latest guided practice'), findsNothing);
      expect(find.text('Dharma Talks Winter'), findsOneWidget);
    });

    testWidgets('Talks shows talks, Q & A and untyped recordings', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());

      await tester.tap(find.byKey(const ValueKey('explore_chip_talks')));
      await DharmaSeedTestApp.settle(tester);

      expect(find.text('Latest talks'), findsOneWidget);
      expect(find.text('Dharma Talks Winter'), findsOneWidget);
      expect(find.text('Jhana Retreat'), findsNothing); // mostly practice
      expect(find.text('Winter questions'), findsOneWidget);
      expect(find.text('Untyped talk about jhana'), findsOneWidget);
      expect(find.text('Settling'), findsNothing);
    });

    testWidgets('library courses and saved teachers lead', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(() async {
        await app.source.setSaved('ds-retreat-200', saved: true);
        await app.source.setSaved('ds-teacher-2', saved: true);
      });
      await app.pump(tester, const ExploreView());

      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Saved teachers'), findsOneWidget);
      final library = tester.getTopLeft(find.text('In your library')).dy;
      final courses = tester.getTopLeft(find.text('Courses')).dy;
      expect(library, lessThan(courses));
      // The library course appears once, under In your library.
      expect(find.text('Dharma Talks Winter'), findsOneWidget);
    });

    testWidgets('library courses stay visible under a chip', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(
        () => app.source.setSaved('ds-retreat-200', saved: true),
      );
      await app.pump(tester, const ExploreView());

      // Practice chip: the library's Talks course is not hidden by it.
      await tester.tap(find.text('Practice'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('In your library'), findsOneWidget);
      expect(find.text('Dharma Talks Winter'), findsOneWidget);
      expect(find.text('Latest guided practice'), findsOneWidget);
    });

    testWidgets('before the first sync, a calm card explains', (tester) async {
      final app = await DharmaSeedTestApp.create(tester, seed: false);
      await app.pump(tester, const ExploreView());

      expect(find.text('The library is not synced yet'), findsOneWidget);
      expect(find.text('Courses'), findsNothing);
    });
  });

  group('Search (in Explore)', () {
    testWidgets('consumes a search focus request made before mount', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const SizedBox.shrink());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
      container.read(exploreFocusRequestProvider.notifier).request();
      await app.pump(tester, const ExploreView());
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(container.read(exploreFocusRequestProvider), 0);
      // A consumed request must not reopen the keyboard on a later mount.
      await app.pump(tester, const SizedBox.shrink());
      await app.pump(tester, const ExploreView());
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse,
      );
    });

    testWidgets('nothing typed browses; typing swaps in grouped results, '
        'debounced; clearing browses again', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());

      expect(
        find.byKey(const ValueKey('explore_search_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('explore_chip_practice')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('suggestion_metta')), findsOneWidget);
      expect(find.text('Mixed Weekend'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 100));
      // Still browsing: the 400 ms pause has not passed.
      expect(
        find.byKey(const ValueKey('explore_chip_practice')),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byKey(const ValueKey('explore_chip_practice')), findsNothing);
      expect(find.text('Talks'), findsOneWidget);
      expect(find.text('Jhana basics'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await DharmaSeedTestApp.settle(tester);
      expect(
        find.byKey(const ValueKey('explore_chip_practice')),
        findsOneWidget,
      );
      expect(find.text('Mixed Weekend'), findsOneWidget);
    });

    testWidgets('the library\'s own items come before Dharma Seed', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(
        () => app.libraryDb.upsertCourse(
          LibCoursesCompanion.insert(
            id: 'lib-course-zzz',
            origin: 'feed',
            title: 'Zebra jhana notes',
            createdAt: DateTime(2026, 10, 1),
          ),
        ),
      );
      await app.pump(tester, const ExploreView());
      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);

      final own = tester.getTopLeft(find.text('Zebra jhana notes')).dy;
      final catalogue = tester.getTopLeft(find.text('Jhana Retreat')).dy;
      expect(own, lessThan(catalogue));
    });

    testWidgets('renamed library titles match and replace source titles', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(() async {
        await app.source.setSaved('ds-retreat-200', saved: true);
        await app.library.setTitle('ds-retreat-200', 'My custom course');
        await app.library.add(
          const LibraryDraft(
            sourceId: 'lib-track-renamed',
            kind: LibraryKind.single,
            title: 'Original recording',
          ),
        );
        await app.library.setTitle('lib-track-renamed', 'My custom recording');
      });
      await app.pump(tester, const ExploreView());
      await tester.enterText(find.byType(TextField), 'custom');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('My custom course'), findsOneWidget);
      expect(find.text('My custom recording'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'winter');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('My custom course'), findsOneWidget);
      expect(find.text('Dharma Talks Winter'), findsNothing);
    });

    testWidgets('suggestions run the search when tapped', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());
      await tester.tap(find.byKey(const ValueKey('suggestion_jhana')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.widgetWithText(TextField, 'jhana'), findsOneWidget);
      expect(find.text('Jhana basics'), findsOneWidget);
    });

    testWidgets('opens on suggestions that run the search when tapped', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());

      await tester.tap(find.byKey(const ValueKey('suggestion_Rob Burbea')));
      await DharmaSeedTestApp.settle(tester);

      expect(find.widgetWithText(TextField, 'Rob Burbea'), findsOneWidget);
      expect(find.text('Teachers'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('teacher_row_ds-teacher-1')),
        findsOneWidget,
      );
    });

    testWidgets('groups teachers, courses and talks in that order', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(
        () => app.db.upsertTeacherRecords({
          7: {'name': 'Jhana Teacher', 'bio': '', 'photo': ''},
        }),
      );
      await app.pump(tester, const ExploreView());

      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);

      final teachers = tester.getTopLeft(find.text('Teachers')).dy;
      final courses = tester.getTopLeft(find.text('Courses')).dy;
      final talks = tester.getTopLeft(find.text('Talks')).dy;
      expect(teachers, lessThan(courses));
      expect(courses, lessThan(talks));
      expect(find.text('Jhana Teacher'), findsOneWidget);
      expect(find.text('Jhana Retreat'), findsOneWidget);
      expect(find.text('Jhana basics'), findsOneWidget);
    });

    testWidgets('the length filter narrows talks only', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());
      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      // 'Jhana basics' runs 60 minutes, the untyped talk 15.
      expect(find.text('Jhana basics'), findsOneWidget);
      expect(find.text('Untyped talk about jhana'), findsOneWidget);

      // Any, then the five buckets: the row scrolls, so bring each in view.
      final row = find.descendant(
        of: find.byKey(const ValueKey('length_filter')),
        matching: find.byType(Scrollable),
      );
      for (final key in [
        'length_any',
        'length_under10',
        'length_from10to20',
        'length_from20to30',
        'length_from30to45',
        'length_over45',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          100,
          scrollable: row,
        );
        expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('length_any')),
        -100,
        scrollable: row,
      );

      await tester.tap(find.byKey(const ValueKey('length_under10')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Jhana basics'), findsNothing);
      expect(find.text('Untyped talk about jhana'), findsNothing);
      expect(find.text('No results found for your search'), findsOneWidget);
      // The course is still there.
      expect(find.text('Jhana Retreat'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('length_from10to20')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Untyped talk about jhana'), findsOneWidget);
      expect(find.text('Jhana basics'), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('length_over45')),
        100,
        scrollable: row,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('length_over45')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('length_over45')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Jhana basics'), findsOneWidget);
      expect(find.text('Untyped talk about jhana'), findsNothing);

      // Tapping the chosen bucket again clears it.
      await tester.tap(find.byKey(const ValueKey('length_over45')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Untyped talk about jhana'), findsOneWidget);
    });

    testWidgets('a new query resets the length filter to Any', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());
      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);

      await tester.tap(find.byKey(const ValueKey('length_under10')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Jhana basics'), findsNothing);

      await tester.enterText(find.byType(TextField), 'untyped');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      // The 15-minute talk shows: under-10 no longer applies.
      expect(find.text('Untyped talk about jhana'), findsOneWidget);
    });

    testWidgets('diacritics are searched, not stripped from the query', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(
        () => app.db.upsertTeacherRecords({
          8: {'name': 'Ñāṇavīra Thera', 'bio': '', 'photo': ''},
        }),
      );
      await app.pump(tester, const ExploreView());

      await tester.enterText(find.byType(TextField), 'Ñāṇavīra');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);

      expect(find.text('Ñāṇavīra Thera'), findsOneWidget);
    });

    testWidgets('nothing found says so', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const ExploreView());
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('No results found for your search'), findsOneWidget);
      expect(find.text('Teachers'), findsNothing);
    });
  });
}
