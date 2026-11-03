// Layout shots for #92's Pinned tile and Library chip row, at the S23+'s 411 dp
// and a 360 dp phone, light and dark, at 1.0x and 1.3x text. Not part of the
// normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/layout_92b_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
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
        isCompleted: false,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_pack);
}

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

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    for (final dp in [411.0, 360.0]) {
      for (final scale in [1.0, 1.3]) {
        final tag = '${dp.round()}-${scale}x-${brightness.name}';

        testWidgets('Pinned 92b, $tag', (tester) async {
          final app = await LibraryTestApp.create(tester);
          await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
          await app.pump(
            tester,
            _frame(
              brightness,
              scale,
              const Scaffold(body: SafeArea(child: PinnedSection())),
            ),
            overrides: [
              packProvider(packId: _pack.id).overrideWith(_FakePack.new),
            ],
          );
          await _size(tester, dp, 200);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _capture(tester, 'pinned-$tag');
        }, skip: !_enabled);

        testWidgets('Library chips 92b, $tag', (tester) async {
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
          await app.pump(
            tester,
            _frame(brightness, scale, const LibraryView()),
          );
          await _size(tester, dp, 360);
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          await _capture(tester, 'library-chips-$tag');
        }, skip: !_enabled);
      }
    }
  }
}
