import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/share_intake.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/library/share_intake_host.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';
import '../../helpers/library_fixtures.dart';

const feedUrl = 'https://example.org/evening.rss';
Map<String, http.Response> get routes => {
  feedUrl: xmlResponse(libraryFixture('rss_podcast.xml')),
};

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

void main() {
  testWidgets('"Share → Meditejo" with a link opens the import preview', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(
      tester,
      routes: routes,
      shared: const SharedPayload(
        text: 'Evening Sits https://example.org/evening.rss',
      ),
    );
    await app.pump(
      tester,
      const ShareIntakeHost(child: Scaffold(body: Text('main'))),
    );

    expect(find.byType(ImportView), findsOneWidget);
    expect(find.byKey(const ValueKey('import_preview')), findsOneWidget);
    expect(find.text('Evening Sits'), findsOneWidget);
    expect(app.harness.web.urls, [
      feedUrl,
    ], reason: 'one request, for the shared link');
  });

  testWidgets('sharing audio opens the preview of the file and adds it', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester, probe: (_) async => 600000);
    late PickedFile file;
    await tester.runAsync(() async {
      file = PickedFile(
        path: app.harness.writeAudio('Body scan.mp3').path,
        name: 'Body scan.mp3',
        mimeType: 'audio/mpeg',
      );
    });
    app.share.first = SharedPayload(files: [file]);
    await app.pump(
      tester,
      const ShareIntakeHost(child: Scaffold(body: Text('main'))),
    );

    expect(find.byType(ImportView), findsOneWidget);
    expect(find.text('Body scan'), findsOneWidget);
    expect(find.text('1 session · 10 min'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('import_add')));
    await settle(tester);
    expect(find.byType(ImportView), findsNothing);
    final entry = (await tester.runAsync(app.harness.store.entries))!.single;
    expect(entry.kind, LibraryKind.single);
    expect(find.text('Added to your library'), findsOneWidget);
  });

  testWidgets('a share that arrives while the app is open opens it too', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester, routes: routes);
    await app.pump(
      tester,
      const ShareIntakeHost(child: Scaffold(body: Text('main'))),
    );
    expect(find.byType(ImportView), findsNothing);

    app.share.controller.add(const SharedPayload(text: feedUrl));
    await settle(tester);
    expect(find.byType(ImportView), findsOneWidget);
    expect(find.text('Evening Sits'), findsOneWidget);
  });

  testWidgets('a normal start does nothing', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const ShareIntakeHost(child: Scaffold(body: Text('main'))),
    );
    expect(find.byType(ImportView), findsNothing);
    expect(find.text('main'), findsOneWidget);
  });
}
