/// Screen goldens at Galaxy S23+ size. Font rendering differs between
/// Linux and macOS, so these are generated and checked on Linux only;
/// skip them elsewhere with `flutter test -x golden`.
@Tags(['golden'])
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/views/pack/pack_view.dart';

import '../helpers/art_finders.dart';
import '../helpers/dharma_seed_app.dart';
import '../views/dharma_seed/course_and_teacher_test.dart' show createApp;

/// Loads every font the app bundles (Google Sans, Material Icons, Material
/// Symbols) so goldens show real text instead of Ahem boxes.
Future<void> loadAppFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Galaxy S23+ at its default display size: 1080 x 2340 px, 384 x 832 dp.
Future<void> asS23Plus(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 1080 / 384;
  await DharmaSeedTestApp.settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    holdCuratedArt();
    await loadAppFonts();
  });

  testWidgets('course page, three talks played', (tester) async {
    final app = await createApp(tester);
    await app.pump(
      tester,
      const PackView(id: 'ds-retreat-500'),
      played: ['ds-talk-501', 'ds-talk-502', 'ds-talk-503'],
    );
    await asS23Plus(tester);

    await expectLater(
      find.byType(PackView),
      matchesGoldenFile('s23plus/course_page.png'),
    );
  });
}
