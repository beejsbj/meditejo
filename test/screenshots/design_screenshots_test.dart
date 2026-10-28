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
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';
import 'package:medito/services/dhammatalks/dhammatalks_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/views/explore/widgets/explore_view.dart';
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
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/you_view.dart';

import '../helpers/dharma_seed_app.dart';
import '../helpers/dharma_seed_catalogue.dart';
import '../helpers/fake_session_source.dart';
import '../helpers/library_app.dart';
import '../helpers/stats_fixtures.dart';
import '../helpers/update_fakes.dart';
import '../helpers/soundscape_fakes.dart';

/// Where captures go, and under which palette (the generated art's
/// screenshots run this twice: MEDITEJO_SHOT_PALETTE=tide and another, into
/// `docs/fork/design/art/<palette>`).
final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _palette = IdentityPalettes.byId(
  Platform.environment['MEDITEJO_SHOT_PALETTE'],
);
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

/// Lets the generated art finish: its stills rasterise off the test's fake
/// clock, then land on the next frame.
Future<void> _settleArt(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _settleArt(tester);
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
  await _settleArt(tester);
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
    data: meditejoTheme(brightness, _palette),
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

/// A Dharma Seed catalogue that reads like the real one, for Explore.
Future<void> _seedRealisticCatalogue(DharmaSeedDatabase db) async {
  await db.upsertTeacherRecords({
    1: {'name': 'Rob Burbea', 'bio': '', 'photo': ''},
    2: {'name': 'Leigh Brasington', 'bio': '', 'photo': ''},
    3: {'name': 'Sharon Salzberg', 'bio': '', 'photo': ''},
    4: {'name': 'Gil Fronsdal', 'bio': '', 'photo': ''},
    5: {'name': 'Ajahn Sucitto', 'bio': '', 'photo': ''},
    6: {'name': 'Tara Brach', 'bio': '', 'photo': ''},
  });
  final retreats = <int, (String, String, int, String)>{
    4496: ('Practising the Jhānas', '2019-03-01', 1, 'Meditation'),
    1084: (
      'The Loving Kindness (Metta) Retreat',
      '2010-02-01',
      3,
      'Meditation',
    ),
    1183: ('The Art of Concentration', '2008-05-01', 2, 'Meditation'),
    1308: ('Samatha Meditation', '2007-09-01', 4, 'Talk'),
    2200: (
      'Forest Refuge: Dwelling in the Body',
      '2016-07-01',
      5,
      'Meditation',
    ),
  };
  final talks = <int, Map<String, Object?>>{};
  var id = 1;
  final retreatTalks = <int, List<int>>{};
  for (final MapEntry(key: r, value: (name, date, teacher, type))
      in retreats.entries) {
    for (var n = 1; n <= 6; n++) {
      retreatTalks.putIfAbsent(r, () => []).add(id);
      talks[id] = dsTalkRecord(
        n.isEven ? '$name: talk $n' : 'Guided practice, day $n',
        teacher: teacher,
        retreat: r,
        type: n.isEven ? 'Talk' : type,
        minutes: 20.0 + n * 7,
        date: '$date 0$n:00:00',
      );
      id++;
    }
  }
  for (final (title, teacher, minutes) in [
    ('Metta for a difficult person', 3, 32.0),
    ('Settling the body, settling the mind', 4, 24.0),
    ('Breath as a home', 6, 18.0),
    ('Opening to what is here', 5, 41.0),
  ]) {
    talks[id++] = dsTalkRecord(
      title,
      teacher: teacher,
      type: 'Guided Meditation',
      minutes: minutes,
      date: '2026-10-${10 + id % 9} 08:00:00',
    );
  }
  await db.upsertRetreatRecords({
    for (final MapEntry(key: r, value: (name, date, _, _)) in retreats.entries)
      r: {
        'name': name,
        'description': '',
        'start_date': date,
        'talks': retreatTalks[r]!,
      },
  });
  await db.upsertTalkRecords(talks);
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
        theme: meditejoTheme(brightness, _palette),
        home: _frame(brightness, page),
      ),
    ),
  );
  await _phone(tester);
  await tester.pump(const Duration(seconds: 1));
  expect(tester.takeException(), isNull);
}

/// The Customize sheet over a quiet page, opened as the player opens it.
Future<ProviderContainer> _pumpCustomize(
  WidgetTester tester,
  Brightness brightness, {
  required CueScope scope,
  required CueSettings settings,
  bool beforeStart = false,
  int positionMs = 0,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(cueSettingsProvider(scope).notifier)
      .update(settings, courseOverride: scope.courseId != null);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: navigator,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: meditejoTheme(brightness, _palette),
        home: _frame(
          brightness,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: Text(
                  'Developing Piti, Developing Focus',
                  style: context.typography.emphasized.titleLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await _phone(tester);
  unawaited(
    showModalBottomSheet<void>(
      context: navigator.currentContext!,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MediaQuery(
        data: MediaQuery.of(
          navigator.currentContext!,
        ).copyWith(disableAnimations: true),
        child: CustomizeSheet(
          scope: scope,
          isActive: !beforeStart,
          audioDurationMs: 45 * 60000,
          positionMs: positionMs,
          onStart: beforeStart ? () {} : null,
          clock: () => DateTime(2026, 10, 26, 7, 30),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return container;
}

/// Opens a Customize row by its title.
Future<void> _openRow(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title).first);
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
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

    // The Customize sheet (design PR 5): before a Practice session, during
    // a course's session, a wheel in use, and the Timer with its duration.
    const practiceCues = CueSettings(
      startSound: 'assets/audio/bell_bowl_medium.wav',
      endSound: 'assets/audio/bell_bowl_deep.wav',
      intervalHalfway: true,
      intervalMinutes: 15,
      extendMinutes: 5,
      countdownSeconds: 5,
    );
    testWidgets('Customize before a session, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      await _captureView(tester, 'customize-before-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize bell picker, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues,
        beforeStart: true,
      );
      // Open the starting bell's list: every bell with its icon.
      await tester.tap(find.text('Starting bell'));
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-bells-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize during a session, ${brightness.name}', (
      tester,
    ) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice, courseId: 'lib-course-a'),
        settings: practiceCues.copyWith(
          intervalHalfway: false,
          randomWindowMinutes: 3,
          pulseSound: 'assets/audio/pulse_heartbeat.wav',
          pulseBpm: 60,
          pulseEndBpm: 48,
          pulseRampMinutes: 10,
        ),
        positionMs: 12 * 60000,
      );
      await _captureView(tester, 'customize-during-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Customize wheel in use, ${brightness.name}', (tester) async {
      await _pumpCustomize(
        tester,
        brightness,
        scope: const CueScope(CueKind.practice),
        settings: practiceCues.copyWith(
          intervalHalfway: false,
          randomWindowMinutes: 3,
        ),
        beforeStart: true,
      );
      await _openRow(tester, 'Interval bell');
      // The row's header at the top, its wheels and list under it.
      await tester.ensureVisible(find.text('Interval bell'));
      await tester.pumpAndSettle();
      await _captureView(tester, 'customize-wheel-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('Timer setup with its duration open, ${brightness.name}', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        _frame(brightness, const TimerView()),
        overrides: soundscapeTestOverrides(FakeSoundscapeEngine()),
      );
      await _phone(tester);
      await tester.pump(const Duration(seconds: 1));
      await _openRow(tester, 'Duration');
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _capture(tester, 'timer-duration-${brightness.name}');
    }, skip: !_enabled);

    // Design pass PR 4: the Library with a realistic mix (two courses in
    // progress, two playlists, three singles, a saved teacher), in the list
    // and the grid.
    for (final grid in [false, true]) {
      testWidgets('Library mix${grid ? ' grid' : ''}, ${brightness.name}', (
        tester,
      ) async {
        final app = await LibraryTestApp.create(tester);
        final (source, morning) = await seedPlaylists(tester, app);
        await tester.runAsync(() async {
          final store = app.harness.store;
          for (final (id, title, subtitle, group) in [
            (
              'ds-talk-60864',
              'Developing Piti, Developing Focus, Developing Wellbeing',
              'Guided Meditation · Rob Burbea · 89 min',
              LibraryGroup.practice,
            ),
            (
              'lib-track-body',
              'Body scan, 20 minutes',
              'My recording',
              LibraryGroup.practice,
            ),
            (
              'ds-talk-2',
              'Emptiness and the middle way',
              'Talk · Rob Burbea · 52 min',
              LibraryGroup.talks,
            ),
          ]) {
            await store.add(
              LibraryDraft(
                sourceId: id,
                kind: LibraryKind.single,
                title: title,
                subtitle: subtitle,
                group: group,
              ),
            );
          }
          await store.add(
            const LibraryDraft(
              sourceId: 'ds-teacher-210',
              kind: LibraryKind.teacher,
              title: 'Rob Burbea',
              subtitle: '1,200 talks',
            ),
          );
          if (grid) await app.prefs.setString('library_layout', 'grid');
        });
        await app.pump(
          tester,
          _frame(brightness, const LibraryView()),
          played: const ['x-1', 'x-2', 'd-1', 'd-2', 'd-3', 'y-1'],
          overrides: [
            myCourseSourceProvider.overrideWithValue(source),
            packTrackIdsProvider.overrideWith(
              (ref) async => {
                morning: ['x-1', 'x-2', 'x-3', 'x-4', 'x-5'],
                'ds-retreat-1': ['d-1', 'd-2', 'd-3', 'd-4', 'd-5', 'd-6'],
                'yt-playlist-a': ['y-1', 'y-2', 'y-3', 'y-4'],
              },
            ),
            inProgressItemsProvider.overrideWith(
              (ref) async => [
                ContinueItem(
                  trackId: 'd-4',
                  path: '/tracks/d-4',
                  title: 'Developing Piti, Developing Focus',
                  group: LibraryGroup.practice,
                  lastPlayed: DateTime(2026, 10, 25),
                  courseId: 'ds-retreat-1',
                  courseTitle: 'Jhāna Retreat',
                  resume: const ResumePoint(
                    positionMs: 1800000,
                    durationMs: 5340000,
                  ),
                  sessionNumber: 4,
                  sessionTotal: 6,
                  completedSessions: 3,
                ),
                ContinueItem(
                  trackId: 'y-2',
                  path: '/tracks/y-2',
                  title: 'Episode 2: Relevance realization',
                  group: LibraryGroup.talks,
                  lastPlayed: DateTime(2026, 10, 24),
                  courseId: 'yt-playlist-a',
                  courseTitle: 'Vervaeke: Awakening from the Meaning Crisis',
                  sessionNumber: 2,
                  sessionTotal: 4,
                  completedSessions: 1,
                ),
              ],
            ),
          ],
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        final name = 'library-mix${grid ? '-grid' : ''}-${brightness.name}';
        await _capture(tester, name);
        // The whole page.
        tester.view.physicalSize = Size(1080, grid ? 5600 : 5000);
        await tester.pump(const Duration(seconds: 1));
        await _capture(
          tester,
          name.replaceFirst('library-mix', 'library-mix-full'),
        );
      }, skip: !_enabled);
    }

    // Explore: browse with nothing typed, and grouped search results.
    for (final query in [null, 'jhāna']) {
      testWidgets('Explore ${query == null ? 'browse' : 'search'}, '
          '${brightness.name}', (tester) async {
        final app = await DharmaSeedTestApp.create(tester, seed: false);
        await tester.runAsync(() async {
          await _seedRealisticCatalogue(app.db);
          await app.source.setSaved('ds-retreat-1084', saved: true);
          await app.source.setSaved('ds-teacher-1', saved: true);
          await app.library.add(
            const LibraryDraft(
              sourceId: 'yt-playlist-a',
              kind: LibraryKind.course,
              title: 'Qualia Mastery',
              subtitle: 'Qualia Research Institute',
            ),
          );
        });
        await app.pump(tester, _frame(brightness, const ExploreView()));
        await _phone(tester);
        if (query != null) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pump(const Duration(milliseconds: 450));
        }
        await DharmaSeedTestApp.settle(tester);
        expect(tester.takeException(), isNull);
        final name =
            'explore-${query == null ? 'browse' : 'search'}-${brightness.name}';
        await _capture(tester, name);
        tester.view.physicalSize = const Size(1080, 4400);
        await DharmaSeedTestApp.settle(tester);
        await _capture(
          tester,
          name
              .replaceFirst('-browse', '-browse-full')
              .replaceFirst('-search', '-search-full'),
        );
      }, skip: !_enabled);
    }

    // Explore with two catalogues: every source, then only Dhammatalks (the
    // real bundled snapshot).
    testWidgets('Explore with both catalogues, ${brightness.name}', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester, seed: false);
      await tester.runAsync(() async {
        await _seedRealisticCatalogue(app.db);
        await app.source.setSaved('ds-retreat-1084', saved: true);
      });
      final snapshot = DtCatalogue.fromJson(
        DtCatalogue.decode(
          File('assets/dhammatalks/catalogue.json.gz').readAsBytesSync(),
        ),
      );
      await app.pump(
        tester,
        _frame(brightness, const ExploreView()),
        dhammatalks: DhammatalksSource(
          loadSnapshot: () async => snapshot,
          library: app.library,
        ),
      );
      await _phone(tester);
      await DharmaSeedTestApp.settle(tester);
      expect(tester.takeException(), isNull);
      final name = 'explore-catalogues-${brightness.name}';
      await _capture(tester, name);
      tester.view.physicalSize = const Size(1080, 4400);
      await DharmaSeedTestApp.settle(tester);
      await _capture(tester, '$name-full');
    }, skip: !_enabled);

    for (final (name, page) in [
      ('timer', const TimerView()),
      ('library-empty', const LibraryView()),
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
    // Today's mark (2026-10-26) drawing in, then one breath (10 s): 40
    // frames for the GIF, every fifth also for a strip.
    const frames = 40;
    final mark = MarkGenerator.build(
      DailyMark.forDay(DateTime(2026, 10, 26)).seed,
    );
    for (final brightness in Brightness.values) {
      final theme = meditejoTheme(brightness, _palette);
      final scheme = theme.colorScheme;
      final colors = theme.extension<MeditejoPalette>()!.markColors(scheme);
      for (var i = 0; i < frames; i++) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                child: CustomPaint(
                  size: const Size.square(240),
                  painter: MarkPainter(
                    mark: mark,
                    colors: colors,
                    time: ValueNotifier(
                      i < 10 ? i * 0.35 : 3.5 + (i - 10) / 30 * 10,
                    ),
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
