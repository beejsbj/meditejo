import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/explore/widgets/explore_view.dart';

import '../../helpers/dharma_seed_app.dart';

Future<DharmaSeedTestApp> _withLibrary(WidgetTester tester) async {
  final app = await DharmaSeedTestApp.create(tester);
  await tester.runAsync(() async {
    await app.source.setSaved('ds-retreat-200', saved: true);
    await app.library.add(
      const LibraryDraft(
        sourceId: 'my-course-0123456789abcdef',
        kind: LibraryKind.course,
        title: 'Morning sits',
        subtitle: '3 sessions',
      ),
    );
  });
  return app;
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets('browse shows its sections in order', (tester) async {
    final app = await _withLibrary(tester);
    await app.pump(tester, const ExploreView());
    tester.view.physicalSize = const Size(430, 2400);
    await DharmaSeedTestApp.settle(tester);

    final order = [
      find.byKey(const ValueKey('explore_search_field')),
      find.byKey(const ValueKey('explore_chip_practice')),
      find.text('In your library'),
      find.text('Courses'),
      find.text('Teachers'),
      find.text('Latest guided practice'),
    ];
    for (final finder in order) {
      expect(finder, findsOneWidget, reason: '$finder');
    }
    for (var i = 1; i < order.length; i++) {
      expect(
        _top(tester, order[i - 1]),
        lessThan(_top(tester, order[i])),
        reason: '${order[i - 1]} before ${order[i]}',
      );
    }
    // The library strip says what each is; the course cards offer Add.
    expect(find.text('Playlist'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('explore_library_strip')),
        matching: find.text('Dharma Seed'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('add_to_library_ds-retreat-100')),
      findsOneWidget,
    );
    // With no chip, the latest sessions are guided practice.
    expect(find.text('Settling'), findsOneWidget);
    expect(find.text('Jhana basics'), findsNothing);
  });

  group('fits a 360 dp phone at twice the text size', () {
    Future<void> pumpLarge(WidgetTester tester, DharmaSeedTestApp app) async {
      await app.pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: const ExploreView(),
          ),
        ),
      );
      tester.view.physicalSize = const Size(360, 780);
      await DharmaSeedTestApp.settle(tester);
    }

    Future<void> scrollThrough(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.drag(
          find.byType(CustomScrollView).first,
          const Offset(0, -400),
        );
        await DharmaSeedTestApp.settle(tester, rounds: 2);
        expect(tester.takeException(), isNull);
      }
    }

    testWidgets('browse', (tester) async {
      final app = await _withLibrary(tester);
      await pumpLarge(tester, app);
      expect(tester.takeException(), isNull);
      await scrollThrough(tester);
    });

    testWidgets('search results', (tester) async {
      final app = await _withLibrary(tester);
      await pumpLarge(tester, app);
      await tester.enterText(find.byType(TextField), 'jhana');
      await tester.pump(const Duration(milliseconds: 450));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Jhana basics', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
      await scrollThrough(tester);
    });
  });
}
