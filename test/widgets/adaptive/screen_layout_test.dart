import 'package:medito/views/explore/widgets/explore_view.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import '../../helpers/fake_savable_source.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/views/end_screen/end_screen_view.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/models/explore/explore_list_item.dart';
import 'package:medito/models/track/track.dart' as model;
import 'package:medito/views/settings/settings_screen.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/artist_title_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_speed_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/views/player/widgets/duration_indicator_widget.dart';
import 'package:medito/views/player/widgets/player_buttons/player_buttons_widget.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_sidebar.dart';
import 'package:medito/widgets/adaptive/adaptive_content.dart';

import 'package:medito/views/settings/battery_optimization_screen.dart';
import 'package:medito/views/intro/intro_view.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/stats_provider.dart';

import 'adaptive_layout_test.dart' show destinations;

/// A Dharma Seed style course: ten sessions over four days, with a teacher
/// and the credit the licence asks for.
final coursePack = PackModel(
  id: 'ds-retreat-1',
  title: 'Jhana Retreat',
  subtitle: 'Rob Burbea · 2014 · 10 talks',
  coverUrl: '',
  path: '/packs/ds-retreat-1',
  description: 'Seven days of jhana practice.',
  isPublished: true,
  teacher: const PackTeacher(
    id: 'ds-teacher-1',
    name: 'Rob Burbea',
    bio: 'Taught at Gaia House.',
    pageUrl: 'https://dharmaseed.org/teacher/1/',
  ),
  attribution: const SourceAttribution(
    source: 'Dharma Seed',
    creator: 'Rob Burbea',
    url: 'https://dharmaseed.org/retreats/1/',
    licenseName: 'CC BY-NC-ND 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
  ),
  items: [
    for (var i = 0; i < 10; i++)
      PackItemsModel(
        type: 'track',
        id: 'ds-talk-$i',
        title: 'Talk $i',
        subtitle: 'Talk · Rob Burbea · ${20 + i} min',
        path: '/tracks/ds-talk-$i',
        kind: i % 3 == 0 ? 'Guided meditation' : 'Talk',
        teacher: 'Rob Burbea',
        durationMs: (20 + i) * 60000,
        date: '2014-03-0${1 + i ~/ 3}',
      ),
  ],
);

const request = PlaybackRequest(
  trackId: 'preview',
  fileId: 'preview-file',
  title: 'Noting Thoughts',
  description: '',
  coverUrl: 'https://preview.medito.test/cover.png',
  remoteUrl: 'https://example.test/audio.mp3',
  duration: 600000,
  hasBackgroundSound: true,
  guideName: 'Will',
);

class _PreviewAudio extends AudioStateNotifier {
  @override
  PlaybackState build() => PlaybackState(
    position: 154000,
    duration: 600000,
    isPlaying: false,
    isBuffering: false,
    isSeeking: false,
    isCompleted: false,
    speed: Speed(speed: 1),
    volume: 100,
    track: Track(
      id: 'preview',
      title: 'Noting Thoughts',
      fileId: 'preview-file',
      description: '',
      imageUrl: '',
      artist: 'Will',
    ),
  );
}

class _OnboardingStats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => previewStats;
}

class _JourneyTracks extends Tracks {
  @override
  Future<model.Track> build({required String trackId}) async => model.Track(
    id: trackId,
    title: 'Noting Thoughts',
    description:
        'Learn to notice your thoughts without getting caught up in them. This guided meditation helps you gently return your attention to the present moment.',
    coverUrl: request.coverUrl,
    isPublished: true,
    hasBackgroundSound: true,
    voices: [
      model.TrackVoice(
        guideName: 'Will',
        audioFiles: [
          model.TrackAudioFile(
            id: 'sample',
            path: 'https://example.test/audio.mp3',
            duration: 600000,
          ),
        ],
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    for (final entry in {
      'Google Sans': 'assets/fonts/google-sans/GoogleSans-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  testWidgets('Home fits tablet and foldable widths', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = ContinueItem(
      trackId: 'track-4',
      path: '/tracks/track-4',
      title: 'Noting Thoughts',
      group: LibraryGroup.practice,
      lastPlayed: DateTime(2026, 10, 19),
      courseId: previewPack.id,
      courseTitle: previewPack.title,
      sessionNumber: 4,
      sessionTotal: 7,
    );
    for (final size in [
      const Size(360, 640),
      const Size(1200, 900),
      const Size(820, 900),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        PreviewShell(
          prefs: prefsDark,
          overrides: [
            continueItemsProvider.overrideWith((ref) async => [item]),
            statsProvider.overrideWith(_OnboardingStats.new),
          ],
          // Home's mark moves while shown; still it so the page settles.
          child: _still(
            size.width >= 700
                ? Scaffold(
                    body: Row(
                      children: [
                        MeditoSidebar(
                          extended: size.width >= 1100,
                          items: destinations,
                          selectedIndex: 0,
                          onSelected: (_) {},
                        ),
                        const Expanded(
                          child: AdaptiveContent(child: HomeView()),
                        ),
                      ],
                    ),
                  )
                : const HomeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continue_track-4')), findsOneWidget);
      final timer = find.byKey(const ValueKey('shortcut_timer'));
      expect(timer.hitTestable(), findsOneWidget);
      await tester.tap(timer);
      await tester.pumpAndSettle();
      expect(find.byType(TimerView), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'real player preserves controls and close/speed callbacks at all sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var closed = false;
      double? speed;
      for (final size in [
        const Size(1200, 800),
        const Size(820, 800),
        const Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        final bytes = await rootBundle.load(
          'assets/images/personal_insights.png',
        );
        final codec = await tester.runAsync(
          () => ui.instantiateImageCodec(bytes.buffer.asUint8List()),
        );
        final frame = await tester.runAsync(() => codec!.getNextFrame());
        final provider = ResizeImage.resizeIfNeeded(
          size.width.toInt(),
          null,
          const NetworkImage('https://preview.medito.test/cover.png'),
        );
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame!.image.clone())),
          ),
        );
        frame!.image.dispose();
        codec!.dispose();
        await tester.pumpWidget(
          PreviewShell(
            prefs: prefsDark,
            overrides: [
              audioStateProvider.overrideWith(_PreviewAudio.new),
              // The speed sheet opens on the session's kind.
              cueScopeForRequestProvider.overrideWith(
                (ref, request) async => const CueScope(CueKind.talks),
              ),
            ],
            child: PlayerScreenLayout(
              currentlyPlayingTrack: request,
              isPlaying: false,
              isAudioLoading: false,
              isBackgroundSoundSelected: false,
              onPlayPausePressed: () {},
              onSpeedChanged: (value) => speed = value,
              onClosePressed: () => closed = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final type in [
          ArtistTitleWidget,
          DurationIndicatorWidget,
          PlayerButtonsWidget,
          PlayerActionBar,
        ]) {
          expect(find.byType(type), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      }
      // The speed chip opens a sheet; tapping a speed applies it.
      await tester.tap(find.byType(AudioSpeedWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('speed_option_0.6×')));
      await tester.pump();
      expect(speed, 0.6);
      Navigator.of(tester.element(find.byType(SpeedSheet))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    },
  );
  testWidgets('the intro and the battery page fit every size and large text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pages = <String, Widget Function()>{
      'intro': () => const IntroView(firstRun: true),
      'intro-about': () => const IntroView(),
      'battery': () => const BatteryOptimizationScreen(),
    };
    for (final entry in pages.entries) {
      for (final configuration in [
        (const Size(360, 640), 1.0, ThemeMode.dark),
        (const Size(820, 900), 1.0, ThemeMode.dark),
        (const Size(1200, 900), 1.0, ThemeMode.dark),
        (const Size(1024, 500), 1.0, ThemeMode.dark),
        (const Size(1200, 900), 1.6, ThemeMode.dark),
        (const Size(360, 640), 1.6, ThemeMode.dark),
        (const Size(1200, 900), 1.0, ThemeMode.light),
      ]) {
        final (size, scale, mode) = configuration;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          PreviewShell(
            prefs: mode == ThemeMode.dark ? prefsDark : prefsLight,
            themeMode: mode,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  // The mark is still, so the page settles.
                  disableAnimations: true,
                ),
                child: entry.value(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.takeException(),
          isNull,
          reason: '${entry.key}: $size text $scale',
        );
        // Exercise the scroll view so lower-page text is laid out too.
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -1200));
          await tester.pump(const Duration(seconds: 1));
          expect(
            tester.takeException(),
            isNull,
            reason: '${entry.key} scrolled: $size text $scale',
          );
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('local settings fit wide and compact sizes', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 0,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_dynamic_icon'),
          (call) async => null,
        );
    for (final size in [
      const Size(1200, 900),
      const Size(820, 900),
      const Size(390, 844),
      const Size(1024, 500),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        PreviewShell(
          prefs: prefsDark,
          child: Scaffold(
            body: Row(
              children: [
                if (size.width >= 700)
                  MeditoSidebar(
                    extended: size.width >= 1100,
                    items: destinations,
                    selectedIndex: 3,
                    onSelected: (_) {},
                  ),
                const Expanded(child: AdaptiveContent(child: SettingsScreen())),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
  testWidgets(
    'Explore, Search and detail screens fit wide and compact viewports',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('flutter.baseflow.com/permissions/methods'),
            (call) async => 0,
          );
      final packs =
          [
                'Beginner’s Guide',
                'Daily Meditations',
                'Sleep',
                'Stress & Anxiety',
                'Mindfulness',
                'Compassion',
              ]
              .asMap()
              .entries
              .map(
                (e) => PackItem(
                  id: 'pack-${e.key}',
                  title: e.value,
                  subtitle: 'Meditations for every day',
                  coverUrl: request.coverUrl,
                  path: 'packs/${e.key}',
                ),
              )
              .toList();
      ui.FrameInfo? frame;
      await tester.runAsync(() async {
        final bytes = await rootBundle.load(
          'assets/images/personal_insights.png',
        );
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        frame = await codec.getNextFrame();
      });
      for (final url in [
        request.coverUrl,
        previewPack.coverUrl,
        ...previewPack.items.map((e) => e.coverUrl),
      ].whereType<String>()) {
        PaintingBinding.instance.imageCache.putIfAbsent(
          CachedNetworkImageProvider(url),
          () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: frame!.image.clone())),
          ),
        );
      }
      for (final size in [
        const Size(1200, 900),
        const Size(820, 900),
        const Size(390, 844),
        const Size(1024, 500),
      ]) {
        tester.view.physicalSize = size;
        for (final name in [
          'explore',
          'pack',
          'course',
          'teacher',
          'track',
          'completion',
        ]) {
          Widget page = switch (name) {
            'explore' => const ExploreView(),
            'pack' => PackView(id: previewPack.id),
            'course' => PackView(id: coursePack.id),
            'teacher' => const TeacherView(teacherId: 'ds-teacher-1'),
            'track' => const TrackView(trackId: 'preview'),
            _ => const EndScreenView(request: request),
          };
          if (name == 'explore') {
            page = Scaffold(
              body: Row(
                children: [
                  if (size.width >= 700)
                    MeditoSidebar(
                      extended: size.width >= 1100,
                      items: destinations,
                      selectedIndex: 1,
                      onSelected: (_) {},
                    ),
                  Expanded(child: AdaptiveContent(child: page)),
                ],
              ),
            );
          }
          await tester.pumpWidget(
            PreviewShell(
              prefs: prefsDark,
              overrides: [
                contentRouterProvider.overrideWithValue(
                  ContentRouter(sources: [FakeSavableSource()]),
                ),
                catalogueExploreProvider(null).overrideWith(
                  (ref) async => CatalogueExplore(
                    hasCatalogue: true,
                    courses: [
                      for (final pack in packs)
                        PackItemsModel(
                          type: 'pack',
                          id: pack.id,
                          title: pack.title,
                          subtitle: pack.subtitle,
                          coverUrl: pack.coverUrl,
                          path: pack.path,
                        ),
                    ],
                    teachers: [
                      CatalogueTeacher(
                        id: 'ds-teacher-1',
                        name: 'Rob Burbea',
                        photoUrl: request.coverUrl,
                      ),
                      const CatalogueTeacher(
                        id: 'ds-teacher-2',
                        name: 'No Photo',
                      ),
                    ],
                  ),
                ),
                for (final length in [null, SessionLength.under10])
                  catalogueSearchProvider((
                    query: 'mind',
                    length: length,
                  )).overrideWith(
                    (ref) async => CatalogueSearchResults(
                      teachers: const [
                        CatalogueTeacher(
                          id: 'ds-teacher-1',
                          name: 'Mind Teacher',
                          talkCount: 12,
                        ),
                      ],
                      courses: [
                        PackItemsModel(
                          type: 'pack',
                          id: 'ds-retreat-1',
                          title: 'Mind Retreat',
                          subtitle: 'Rob Burbea · 2014 · 9 talks',
                          coverUrl: request.coverUrl,
                          path: '/packs/ds-retreat-1',
                        ),
                      ],
                      talks: length == null
                          ? [
                              PackItemsModel(
                                type: 'track',
                                id: 'preview',
                                title: 'Mindful Breathing',
                                subtitle: 'Guided meditation · Will · 10 min',
                                coverUrl: request.coverUrl,
                                path: 'tracks/preview',
                                kind: 'Guided meditation',
                                teacher: 'Will',
                                durationMs: 600000,
                              ),
                            ]
                          : const [],
                    ),
                  ),
                catalogueTeacherProvider('ds-teacher-1').overrideWith(
                  (ref) async => CatalogueTeacherPage(
                    teacher: CatalogueTeacher(
                      id: 'ds-teacher-1',
                      name: 'Rob Burbea',
                      photoUrl: request.coverUrl,
                      bio: 'Taught at Gaia House.\n\nWrote Seeing That Frees.',
                      website: 'https://hermesamara.org/',
                      pageUrl: 'https://dharmaseed.org/teacher/1/',
                      talkCount: 439,
                      retreatCount: 31,
                    ),
                    courses: const [
                      PackItemsModel(
                        type: 'pack',
                        id: 'ds-retreat-1',
                        title: 'Jhana Retreat',
                        subtitle: 'Rob Burbea · 2014 · 38 talks',
                        path: '/packs/ds-retreat-1',
                      ),
                    ],
                    talks: [coursePack.items.first, coursePack.items[1]],
                    hasMoreTalks: true,
                  ),
                ),
                packDataProvider(
                  packId: coursePack.id,
                ).overrideWith((ref) async => coursePack),
                packDataProvider(
                  packId: previewPack.id,
                ).overrideWith((ref) async => previewPack),
                tracksProvider(
                  trackId: 'preview',
                ).overrideWith(_JourneyTracks.new),
                statsProvider.overrideWith(_OnboardingStats.new),
              ],
              child: RepaintBoundary(
                key: const ValueKey('capture'),
                child: page,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          if (name == 'search') {
            await tester.enterText(find.byType(TextField), 'mind');
            await tester.pump(const Duration(milliseconds: 600));
            await tester.pump(const Duration(seconds: 1));
          }
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull, reason: '$name at $size');
          if (name == 'track') {
            final image = find
                .descendant(
                  of: find.byType(TrackView),
                  matching: find.byType(AspectRatio),
                )
                .first;
            final title = find.text('Noting Thoughts').first;
            expect(
              tester.getBottomLeft(image).dy,
              lessThan(tester.getTopLeft(title).dy),
            );
            expect(tester.getSize(image).width, lessThanOrEqualTo(560));
          }

          if (name == 'search') {
            expect(find.text('Mind Teacher'), findsOneWidget);
            expect(find.text('Mind Retreat'), findsOneWidget);
            expect(find.text('Mindful Breathing'), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('length_under10')));
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
          }
          if (name == 'course') {
            expect(find.textContaining('10 sessions'), findsOneWidget);
            // On a short viewport the tabs start below the fold.
            await tester.scrollUntilVisible(
              find.text('Teacher'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.tap(find.text('Teacher'));
            await tester.pump(const Duration(seconds: 1));
            expect(find.textContaining('Taught at Gaia House'), findsWidgets);
            expect(tester.takeException(), isNull);
          }
          if (name == 'teacher') {
            expect(
              find.byKey(const ValueKey('teacher_counts')),
              findsOneWidget,
            );
          }
          if (name == 'search') {
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            await tester.pump();
            expect(
              tester.getBottomLeft(find.byType(TextField)).dy,
              lessThan(size.height - 300),
            );
            expect(tester.takeException(), isNull);
            tester.view.resetViewInsets();
            await tester.pump();
          }
          if (name == 'completion') {
            await tester.drag(
              find.byType(SingleChildScrollView).first,
              const Offset(0, -500),
            );
            await tester.pump(const Duration(seconds: 1));
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        }
      }
    },
  );
}

/// [child] as reduced motion shows it.
Widget _still(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);
