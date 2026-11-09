// Layout shots for #62: Home without an Add pill, and Library's "+" with the
// sheet it opens, at the S23+'s 411 dp and a 360 dp phone with 1.3x text,
// light and dark. Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/library_plus_62_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/library/library_view.dart';

import '../helpers/library_app.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';
final _boundary = GlobalKey();

final _pack = PackModel(
  id: 'lib-course-a',
  title: 'Practising the Jhānas',
  items: [
    for (var i = 0; i < 32; i++)
      PackItemsModel(
        type: 'track',
        id: 'a-$i',
        title: 'Session $i',
        path: '/tracks/a-$i',
        isCompleted: i < 4,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_pack);
}

final _items = [
  ContinueItem(
    trackId: 't1',
    path: '/tracks/t1',
    title: 'Developing Piti, Developing Focus',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 25),
    courseId: 'lib-course-a',
    courseTitle: 'Practising the Jhānas',
    resume: const ResumePoint(positionMs: 1800000, durationMs: 5340000),
    sessionNumber: 4,
    sessionTotal: 32,
  ),
];

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
  // The You button's and the Sounds tile's Material Symbols.
  final symbols =
      FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      );
  await symbols.load();
}

Widget _frame(Brightness brightness, double scale, Widget child) =>
    RepaintBoundary(
      key: _boundary,
      child: Theme(
        data: meditejoTheme(brightness, IdentityPalettes.byId(null)),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child,
          ),
        ),
      ),
    );

Future<void> _size(WidgetTester tester, double dp, double heightDp) async {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = Size(dp * 2.625, heightDp * 2.625);
  await tester.pump();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Everything on screen, including a bottom sheet above the page.
Future<void> _captureView(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var render = tester.element(find.byType(Navigator).first).renderObject!;
    while (!render.isRepaintBoundary) {
      render = render.parent!;
    }
    final layer = render.debugLayer! as OffsetLayer;
    final image = await layer.toImage(render.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    for (final (dp, scale) in [(411.0, 1.0), (360.0, 1.3)]) {
      final tag = '${dp.round()}-${scale}x-${brightness.name}';

      testWidgets('Home with pins 62, $tag', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
        await app.pump(
          tester,
          _frame(brightness, scale, const HomeView()),
          overrides: [
            continueItemsProvider.overrideWith((ref) async => _items),
            packProvider(packId: _pack.id).overrideWith(_FakePack.new),
          ],
        );
        await _size(tester, dp, 1100);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'home-pins-$tag');
      }, skip: !_enabled);

      testWidgets('Home empty 62, $tag', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(brightness, scale, const HomeView()),
          overrides: [continueItemsProvider.overrideWith((ref) async => [])],
        );
        await _size(tester, dp, 800);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'home-empty-$tag');
      }, skip: !_enabled);

      testWidgets('Library top bar 62, $tag', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await tester.runAsync(
          () => app.harness.store.add(
            const LibraryDraft(
              sourceId: 'lib-course-a',
              kind: LibraryKind.course,
              title: 'Practising the Jhānas',
              subtitle: 'Rob Burbea',
            ),
          ),
        );
        await app.pump(tester, _frame(brightness, scale, const LibraryView()));
        await _size(tester, dp, 400);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'library-top-$tag');

        // The "+" sheet, where there is one (after #62). It opens above
        // [_frame], so its text size comes from the platform.
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _size(tester, dp, 800);
        await tester.tap(find.byKey(const ValueKey('library_add')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        if (find
            .byKey(const ValueKey('library_add_sheet'))
            .evaluate()
            .isNotEmpty) {
          expect(tester.takeException(), isNull);
          await _captureView(tester, 'library-sheet-$tag');
        }
      }, skip: !_enabled);
    }
  }
}
