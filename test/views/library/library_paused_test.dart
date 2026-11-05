import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/widgets/save_button.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

void main() {
  testWidgets(
    'pinning and removing a course from its own page, with the Library underneath',
    (tester) async {
      final app = await LibraryTestApp.create(
        tester,
        routes: {
          'https://example.org/evening.rss': xmlResponse(
            libraryFixture('rss_podcast.xml'),
          ),
        },
      );
      await tester.runAsync(() async {
        final preview = await app.harness.service.resolve(
          'https://example.org/evening.rss',
        );
        await app.harness.service.add(
          preview,
          const ImportChoice(
            kind: LibraryKind.course,
            group: LibraryGroup.practice,
          ),
        );
      });
      await app.pump(tester, const LibraryView());
      await tester.tap(find.text('Evening Sits'));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('course_pin')));
      await settle(tester);
      // The header's Library toggle (#81).
      await tester.ensureVisible(find.byType(SaveIconButton));
      await tester.tap(find.byType(SaveIconButton));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Remove from library'),
        ),
      );
      await settle(tester);
      expect(find.byType(PackView), findsNothing);
      expect(find.text('Your library is empty'), findsOneWidget);
    },
  );
}
