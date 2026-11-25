import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/pack/pack_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/fake_session_source.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

final _add = find.byKey(const ValueKey('library_add'));
final _sheet = find.byKey(const ValueKey('library_add_sheet'));
final _import = find.byKey(const ValueKey('library_add_import'));
final _newPlaylist = find.byKey(const ValueKey('library_add_new_playlist'));

/// Library's "+" (#62): one sheet with everything that used to be under
/// Home's Add (Import) and Library's own new-playlist button.
void main() {
  late LibraryTestApp app;
  late MyCourseSource source;

  Future<void> pump(WidgetTester tester) async {
    app = await LibraryTestApp.create(tester);
    source = MyCourseSource(
      db: app.harness.db,
      library: app.harness.store,
      sources: () => [FakeSessionSource()],
    );
    addTearDown(source.dispose);
    await app.pump(
      tester,
      const LibraryView(),
      asRoute: true,
      overrides: [myCourseSourceProvider.overrideWithValue(source)],
    );
  }

  testWidgets('"+" opens a sheet with Import and New playlist', (tester) async {
    await pump(tester);
    await tester.tap(_add);
    await settle(tester);

    expect(_sheet, findsOneWidget);
    expect(
      find.descendant(of: _sheet, matching: find.text('Add to your library')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _import, matching: find.text('Import')),
      findsOne,
    );
    expect(
      find.descendant(
        of: _import,
        matching: find.text(
          'A link, a podcast feed, a YouTube playlist, or files on your phone',
        ),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: _newPlaylist, matching: find.text('New playlist')),
      findsOne,
    );
    // Each row is a full-width 48 dp (or taller) target.
    expect(tester.getSize(_import).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(_newPlaylist).height, greaterThanOrEqualTo(48));
  });

  testWidgets('Import closes the sheet and opens the import screen', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(_add);
    await settle(tester);
    await tester.tap(_import);
    await settle(tester);

    expect(_sheet, findsNothing);
    expect(find.byType(ImportView), findsOneWidget);
  });

  testWidgets('New playlist names one, makes it and opens it', (tester) async {
    await pump(tester);
    await tester.tap(_add);
    await settle(tester);
    await tester.tap(_newPlaylist);
    await settle(tester);

    expect(_sheet, findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('new_course_name')),
      'Morning sits',
    );
    await tester.tap(find.byKey(const ValueKey('new_course_create')));
    await settle(tester);

    final made = (await tester.runAsync(() => source.courses()))!.single;
    expect(made.title, 'Morning sits');
    expect(find.byType(PackView), findsOneWidget);
  });

  testWidgets('dismissing the sheet does nothing', (tester) async {
    await pump(tester);
    await tester.tap(_add);
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    expect(_sheet, findsNothing);
    expect(find.byType(ImportView), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
