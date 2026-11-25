// Layout shots for #80: the Library by form (Playlists · Courses · Sessions)
// with Practice and Talks as chips that filter by what a course's sessions
// are. A realistic library: three Dharma Seed retreats (one mixed, one of
// talks, one of sittings), two playlists, single sessions, an imported feed,
// a YouTube series, a saved teacher and two downloads. At the S23+'s 411 dp, light and dark,
// and a 360 dp phone with 1.3x German text. Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/library_by_form_80_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/library/library_view.dart';

import '../helpers/dharma_seed_catalogue.dart';
import '../helpers/library_app.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';
final _boundary = GlobalKey();

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

Widget _frame(Brightness brightness, double scale, String lang, Widget child) =>
    RepaintBoundary(
      key: _boundary,
      child: Theme(
        data: meditejoTheme(brightness, IdentityPalettes.byId(null)),
        child: Builder(
          builder: (context) => Localizations.override(
            context: context,
            locale: Locale(lang),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(scale),
              ),
              child: child,
            ),
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

const _jhanas = 'ds-retreat-100';
const _emptiness = 'ds-retreat-200';
const _metta = 'ds-retreat-300';
const _morning = 'my-course-0123456789abcdef';
const _evening = 'my-course-fedcba9876543210';
const _tara = 'lib-course-tara';
const _vervaeke = 'yt-playlist-vervaeke';

String _talk(int id) => 'ds-talk-$id';

/// Talks of retreat 100 (32: sittings and talks), 200 (18: talks and a
/// Q & A), 300 (6 sittings), and two singles.
Future<void> _seedTalks(LibraryTestApp app) async {
  final records = <int, Map<String, Object?>>{
    for (var i = 1; i <= 32; i++)
      i: dsTalkRecord(
        i.isOdd ? 'Guided meditation $i' : 'Talk $i',
        teacher: 1,
        retreat: 100,
        type: i.isOdd ? 'Meditation' : 'Talk',
      ),
    for (var i = 101; i <= 118; i++)
      i: dsTalkRecord(
        'Talk $i',
        teacher: 1,
        retreat: 200,
        type: i == 118 ? 'Q & A' : 'Talk',
      ),
    for (var i = 201; i <= 206; i++)
      i: dsTalkRecord(
        'Metta $i',
        teacher: 2,
        retreat: 300,
        type: 'Meditation',
      ),
    901: dsTalkRecord(
      'Developing Piti, Developing Focus, Developing Wellbeing',
      teacher: 1,
      type: 'Meditation',
    ),
    902: dsTalkRecord('On emptiness', teacher: 1),
  };
  await app.harness.dsDb.upsertTalkRecords(records);
}

Future<void> _seedLibrary(LibraryTestApp app) async {
  final store = app.harness.store;
  for (final draft in [
    const LibraryDraft(
      sourceId: 'ds-teacher-1',
      kind: LibraryKind.teacher,
      title: 'Rob Burbea',
      subtitle: '1,200 talks',
    ),
    const LibraryDraft(
      sourceId: _tara,
      kind: LibraryKind.course,
      title: 'Tara Brach',
      subtitle: 'Meditation and talks · podcast',
      group: LibraryGroup.talks,
      itemCount: 40,
    ),
    const LibraryDraft(
      sourceId: 'lib-track-body',
      kind: LibraryKind.single,
      title: 'Body scan, 20 minutes',
      subtitle: 'My recording',
    ),
    const LibraryDraft(
      sourceId: 'ds-talk-902',
      kind: LibraryKind.single,
      title: 'On emptiness',
      subtitle: 'Talk · Rob Burbea · 52 min',
      group: LibraryGroup.talks,
    ),
    const LibraryDraft(
      sourceId: 'ds-talk-901',
      kind: LibraryKind.single,
      title: 'Developing Piti, Developing Focus, Developing Wellbeing',
      subtitle: 'Guided meditation · Rob Burbea · 89 min',
    ),
    const LibraryDraft(
      sourceId: _evening,
      kind: LibraryKind.course,
      title: 'Evening listening',
      subtitle: '4 sessions',
      group: LibraryGroup.talks,
      itemCount: 4,
    ),
    const LibraryDraft(
      sourceId: _morning,
      kind: LibraryKind.course,
      title: 'Morning sits',
      subtitle: '5 sessions',
      itemCount: 5,
    ),
    const LibraryDraft(
      sourceId: _vervaeke,
      kind: LibraryKind.course,
      title: 'Awakening from the Meaning Crisis',
      subtitle: 'John Vervaeke',
      group: LibraryGroup.talks,
      itemCount: 18,
    ),
    const LibraryDraft(
      sourceId: _metta,
      kind: LibraryKind.course,
      title: 'Metta Weekend',
      subtitle: 'Ajahn Sucitto · 2016 · 6 talks',
      itemCount: 6,
    ),
    const LibraryDraft(
      sourceId: _emptiness,
      kind: LibraryKind.course,
      title:
          'Emptiness and the Middle Way: Insight into Dependent Arising and Freedom',
      subtitle: 'Rob Burbea · 2014 · 18 talks',
      itemCount: 18,
    ),
    const LibraryDraft(
      sourceId: _jhanas,
      kind: LibraryKind.course,
      title: 'Practising the Jhānas',
      subtitle: 'Rob Burbea · 2019 · 32 talks',
      itemCount: 32,
    ),
  ]) {
    await store.add(draft);
  }
}

final _trackIds = {
  _jhanas: [for (var i = 1; i <= 32; i++) _talk(i)],
  _emptiness: [for (var i = 101; i <= 118; i++) _talk(i)],
  _metta: [for (var i = 201; i <= 206; i++) _talk(i)],
  _morning: [_talk(1), _talk(3), _talk(201), _talk(202), 'lib-track-body'],
  _evening: [_talk(2), _talk(902), 'yt-v-2', 'yt-v-3'],
  _tara: [for (var i = 0; i < 40; i++) 'lib-track-tara-$i'],
  _vervaeke: [for (var i = 1; i <= 18; i++) 'yt-v-$i'],
};

/// Taps Practice or Talks, as a chip (#80) or, before it, a segment.
Future<void> _choose(WidgetTester tester, String group) async {
  final chip = find.byKey(ValueKey('library_filter_$group'));
  final target = chip.evaluate().isNotEmpty
      ? chip
      : find.byKey(ValueKey('library_group_$group'));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  // Two frames: the chips' check marks finish moving.
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    for (final (dp, scale, lang) in [
      (411.0, 1.0, 'en'),
      (360.0, 1.3, 'de'),
    ]) {
      final tag = '${dp.round()}-${scale}x-$lang-${brightness.name}';

      testWidgets('Library by form 80, $tag', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await tester.runAsync(() async {
          await _seedTalks(app);
          await _seedLibrary(app);
        });
        await app.pump(
          tester,
          _frame(brightness, scale, lang, const LibraryView()),
          played: [
            for (var i = 1; i <= 6; i++) _talk(i),
            'yt-v-1',
            'yt-v-2',
            _talk(201),
          ],
          // Something downloaded, so the Downloads chip shows (#80).
          downloaded: const {'ds-talk-901', 'yt-v-1'},
          overrides: [
            packTrackIdsProvider.overrideWith((ref) async => _trackIds),
          ],
        );
        await _size(tester, dp, 2340 / 2.625);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'library-all-$tag');

        if (lang == 'en') {
          await _size(tester, dp, 3000);
          await tester.pump(const Duration(seconds: 1));
          await _capture(tester, 'library-all-full-$tag');
          await _size(tester, dp, 2340 / 2.625);
        }

        for (final group in ['practice', 'talks']) {
          await _choose(tester, group);
          expect(tester.takeException(), isNull);
          await _capture(tester, 'library-$group-$tag');
        }
      }, skip: !_enabled);
    }
  }
}
