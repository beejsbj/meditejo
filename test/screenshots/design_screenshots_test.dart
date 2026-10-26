// Screenshots for the design pass's PR, written to docs/fork/design/. Not
// part of the normal run (they render real fonts and write files):
//
//   MEDITEJO_SCREENSHOTS=1 flutter test test/screenshots
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';
import 'package:medito/services/my_courses/my_course_source.dart';
import 'package:medito/views/my_courses/my_course_actions.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/library/library_view.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/you_view.dart';

import '../helpers/dharma_seed_app.dart';
import '../helpers/fake_session_source.dart';
import '../helpers/library_app.dart';
import '../helpers/stats_fixtures.dart';
import '../helpers/update_fakes.dart';
import '../helpers/soundscape_fakes.dart';

const _out = 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  // The tester runs from bin/cache/artifacts/engine/<host>/ in the SDK.
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
  // The tab bar's and the Sounds screen's Material Symbols.
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

final _boundary = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
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

/// Everything on screen, including routes above the page (a bottom sheet).
Future<void> _captureView(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    var render = tester.element(find.byType(Navigator).first).renderObject!;
    while (!render.isRepaintBoundary) {
      render = render.parent!;
    }
    final layer = render.debugLayer! as OffsetLayer;
    // The render view's bounds are already in physical pixels.
    final image = await layer.toImage(render.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// [child] in [brightness], still (reduced motion), captured whole.
Widget _frame(Brightness brightness, Widget child) => RepaintBoundary(
  key: _boundary,
  child: Theme(
    data: meditejoTheme(brightness),
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child,
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  // An S23+-shaped screen: 1080 × 2340 at 2.625.
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2340);
  await tester.pump();
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
  ContinueItem(
    trackId: 't2',
    path: '/tracks/t2',
    title: 'Metta for a difficult person',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 24),
    courseId: 'lib-course-b',
    courseTitle: 'The Loving Kindness Retreat',
    sessionNumber: 3,
    sessionTotal: 10,
  ),
];

final _pack = PackModel(
  id: 'lib-course-c',
  title: 'The Art of Concentration',
  items: [
    for (var i = 0; i < 9; i++)
      PackItemsModel(
        type: 'track',
        id: 'c-$i',
        title: 'Talk',
        path: '/tracks/c',
        isCompleted: i < 3,
      ),
  ],
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(_pack);
}

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

/// [page] on the fixed stats history and an update harness, in [brightness].
Future<void> _pumpYou(
  WidgetTester tester,
  Brightness brightness,
  Widget page,
) async {
  // The reminder row asks for the notification permission.
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissions, (call) async => 0);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null),
  );
  final h = await UpdateHarness.create();
  final container = ProviderContainer(
    overrides: [
      ...h.overrides,
      statsProvider.overrideWith(() => _Stats(richStats(fixtureNow))),
      practiceClockProvider.overrideWithValue(() => fixtureNow),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: meditejoTheme(brightness),
        home: _frame(brightness, page),
      ),
    ),
  );
  await _phone(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  const nav = [
    MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
    MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
    MeditoNavItem(icon: Symbols.graphic_eq_rounded, label: 'Sounds'),
    MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
    MeditoNavItem(icon: Symbols.person_rounded, label: 'You'),
  ];

  for (final brightness in Brightness.values) {
    testWidgets('Home, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
      await app.pump(
        tester,
        _frame(
          brightness,
          Scaffold(
            body: const HomeView(),
            bottomNavigationBar: MeditoNavBar(
              items: nav,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => _items),
          packProvider(packId: _pack.id).overrideWith(_FakePack.new),
        ],
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'home-${brightness.name}');
      // The whole page, pinned courses included.
      tester.view.physicalSize = const Size(1080, 3150);
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, 'home-full-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('five tabs, ${brightness.name}', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _frame(
            brightness,
            Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: MeditoNavBar(
                items: nav,
                selectedIndex: 2,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      // The narrowest common phone width.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(1080, 360);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _capture(tester, 'navbar-five-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('You and Settings, ${brightness.name}', (tester) async {
      await _pumpYou(tester, brightness, const YouView());
      await _capture(tester, 'you-${brightness.name}');
      tester.view.physicalSize = const Size(1080, 6200);
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, 'settings-${brightness.name}');
    }, skip: !_enabled);

    for (final days in [7, 30]) {
      testWidgets('Stats, $days days, ${brightness.name}', (tester) async {
        await _pumpYou(tester, brightness, const StatsScreen());
        if (days == 30) {
          await tester.tap(find.text('30 days'));
          await tester.pump(const Duration(seconds: 1));
        }
        await _capture(tester, 'stats-top-$days-${brightness.name}');
        tester.view.physicalSize = const Size(1080, 4950);
        await tester.pump(const Duration(seconds: 1));
        await _capture(tester, 'stats-$days-${brightness.name}');
      }, skip: !_enabled);
    }

    // The Sounds tab: the starter mix (three layers) docked under the
    // presets and the library; the same mix open; an empty mix (which stays
    // docked); and a wide window with the panel beside the library.
    for (final (name, empty, open, wide) in [
      ('sounds', false, false, false),
      ('sounds-mix', false, true, false),
      ('sounds-empty', true, false, false),
      ('sounds-wide', false, false, true),
    ]) {
      testWidgets('$name, ${brightness.name}', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(
            brightness,
            Scaffold(
              body: const SoundsView(),
              bottomNavigationBar: wide
                  ? null
                  : MeditoNavBar(
                      items: nav,
                      selectedIndex: 2,
                      onSelected: (_) {},
                    ),
            ),
          ),
          overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
        );
        if (wide) {
          // A tablet in landscape.
          tester.view.devicePixelRatio = 2;
          tester.view.physicalSize = const Size(2560, 1600);
          await tester.pump();
        } else {
          await _phone(tester);
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SoundsView)),
        );
        final mixer = container.read(soundscapeProvider.notifier);
        if (empty) {
          mixer.clearMix();
        } else {
          mixer.togglePlay();
        }
        await tester.pump(const Duration(seconds: 1));
        if (open) {
          await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
          await tester.pump(const Duration(seconds: 1));
        }
        expect(tester.takeException(), isNull);
        await _capture(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
    }

    // Decision 18: what the user makes is a Playlist, what a source gives is
    // a Course. The Library lists both; the add-to sheet offers playlists.
    Future<(MyCourseSource, String)> seedPlaylists(
      WidgetTester tester,
      LibraryTestApp app,
    ) async {
      final upstream = FakeSessionSource();
      final source = MyCourseSource(
        db: app.harness.db,
        library: app.harness.store,
        sources: () => [upstream],
      );
      addTearDown(source.dispose);
      MyItemDraft session(String id) => MyItemDraft(
        id: id,
        title: 'Session $id',
        subtitle: 'Teacher of $id',
        durationMs: 600000,
      );
      late String morning;
      await tester.runAsync(() async {
        final store = app.harness.store;
        for (final (id, title, author) in [
          ('ds-retreat-1', 'Jhāna Retreat', 'Rob Burbea'),
          ('lib-course-a', 'Metta, week by week', 'Sharon Salzberg'),
          (
            'yt-playlist-a',
            'Vervaeke: Awakening from the Meaning Crisis',
            'YouTube',
          ),
        ]) {
          await store.add(
            LibraryDraft(
              sourceId: id,
              kind: LibraryKind.course,
              title: title,
              subtitle: author,
            ),
          );
        }
        morning = (await source.create(
          title: 'Morning sits',
          lines: [
            for (final n in [1, 2, 3, 4, 5])
              MyCourseLine.session(session('x-$n')),
          ],
        ));
        await source.create(
          title: 'Evening wind-down',
          lines: [MyCourseLine.session(session('x-6'))],
        );
        await source.create(title: 'For hard days', lines: const []);
      });
      return (source, morning);
    }

    testWidgets('Library with courses and playlists, ${brightness.name}', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      final (source, morning) = await seedPlaylists(tester, app);
      await app.pump(
        tester,
        _frame(brightness, const LibraryView()),
        played: const ['x-1', 'x-2'],
        overrides: [
          myCourseSourceProvider.overrideWithValue(source),
          packTrackIdsProvider.overrideWith(
            (ref) async => {
              morning: ['x-1', 'x-2', 'x-3', 'x-4', 'x-5'],
              'ds-retreat-1': ['d-1', 'd-2', 'd-3'],
            },
          ),
        ],
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'library-playlists-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Add to playlist sheet, ${brightness.name}', (tester) async {
      final app = await LibraryTestApp.create(tester);
      final (source, _) = await seedPlaylists(tester, app);
      // No debug ribbon in the corner of the capture.
      WidgetsApp.debugAllowBannerOverride = false;
      addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
      late Future<void> Function() open;
      await app.pump(
        tester,
        _frame(
          brightness,
          Consumer(
            builder: (context, ref, _) {
              open = () => showAddToCourse(
                context,
                ref,
                id: 'x-6',
                fallback: const MyItemDraft(
                  id: 'x-6',
                  title: 'Session x-6',
                  subtitle: 'Teacher of x-6',
                  durationMs: 600000,
                ),
              );
              return const LibraryView();
            },
          ),
        ),
        overrides: [myCourseSourceProvider.overrideWithValue(source)],
      );
      await _phone(tester);
      unawaited(open());
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      await _captureView(tester, 'add-to-playlist-${brightness.name}');
    }, skip: !_enabled);

    for (final (name, page) in [
      ('timer', const TimerView()),
      ('library', const LibraryView()),
    ]) {
      testWidgets('$name (inherits the theme), ${brightness.name}', (
        tester,
      ) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(tester, _frame(brightness, page));
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, '$name-${brightness.name}');
      }, skip: !_enabled);
    }
  }

  testWidgets('the mark, frame by frame', (tester) async {
    // 40 frames over one breath (10 s, a sixth of the loop) for the GIF;
    // every fifth also goes into a strip.
    const frames = 40;
    for (final brightness in Brightness.values) {
      final scheme = meditejoColorScheme(brightness);
      for (var i = 0; i < frames; i++) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                child: CustomPaint(
                  size: const Size.square(240),
                  painter: MeditejoMarkPainter.forScheme(
                    AlwaysStoppedAnimation(i / frames / 6),
                    scheme,
                  ),
                ),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(280, 280);
        await tester.pump();
        await _capture(
          tester,
          'mark-frames/${brightness.name}-${i.toString().padLeft(3, '0')}',
        );
      }
    }
  }, skip: !_enabled);
}
