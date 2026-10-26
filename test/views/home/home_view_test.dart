import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/customise_home_layout_screen.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/home/widgets/pinned/pinned_section.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/timer/timer_view.dart';

import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

ContinueItem _item(String id, {bool resume = true}) => ContinueItem(
  trackId: id,
  path: '/tracks/$id',
  title: 'Title $id',
  group: LibraryGroup.practice,
  lastPlayed: DateTime(2026, 10, 19),
  courseId: 'lib-course-a',
  courseTitle: 'Course A',
  resume: resume
      ? const ResumePoint(positionMs: 120000, durationMs: 600000)
      : null,
  sessionNumber: 2,
  sessionTotal: 5,
);

/// A section's screen-reader heading: Home draws none.
Finder sectionHeader(String label) =>
    find.byWidgetPredicate((w) => w is HomeSectionHeader && w.title == label);

void main() {
  testWidgets('shows Continue, shortcuts and no score or streak', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [
        continueItemsProvider.overrideWith(
          (ref) async => [_item('t1'), _item('t2', resume: false)],
        ),
      ],
    );

    expect(sectionHeader('Continue'), findsOneWidget);
    expect(sectionHeader('Shortcuts'), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut_timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('continue_t1')), findsOneWidget);
    expect(find.text('Title t1'), findsOneWidget);
    expect(find.textContaining('Course A · Session 2 of 5'), findsNWidgets(2));
    expect(find.textContaining('8:00 left'), findsOneWidget);
    // Resume where it was left; Start for the next session of a course.
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    expect(find.textContaining('Consistency'), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
    expect(sectionHeader('Pinned'), findsNothing);
  });

  testWidgets('draws no section headings, but announces them as headers', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setStringList('pinned_course_ids', ['lib-course-a']);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [
        continueItemsProvider.overrideWith((ref) async => [_item('t1')]),
        packProvider(packId: 'lib-course-a').overrideWith(
          () =>
              _FakePack(const PackModel(id: 'lib-course-a', title: 'Course A')),
        ),
      ],
    );

    // Nothing says Continue, Shortcuts, Quick links or Pinned on screen.
    for (final heading in ['Continue', 'Shortcuts', 'Quick links', 'Pinned']) {
      expect(find.text(heading), findsNothing, reason: '$heading is drawn');
    }
    // Each group is still a heading to TalkBack, with nothing to look at.
    for (final heading in ['Continue', 'Shortcuts', 'Pinned']) {
      final finder = sectionHeader(heading);
      expect(finder, findsOneWidget, reason: heading);
      expect(
        tester.getSemantics(finder),
        matchesSemantics(isHeader: true, label: heading),
        reason: heading,
      );
      // Android sets its heading flag only for a positive level.
      expect(
        tester.getSemantics(finder).getSemanticsData().headingLevel,
        2,
        reason: heading,
      );
      // No area to look at, but enough for a screen reader to land on.
      expect(tester.getSize(finder).height, 1, reason: '$heading height');
    }
    semantics.dispose();
  });

  testWidgets('starting from Continue notes the course it is shown under', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [
        continueItemsProvider.overrideWith(
          (ref) async => [_item('t2', resume: false)],
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('continue_t2')));
    await settle(tester);

    expect(
      await tester.runAsync(() => app.harness.store.sessionContext('t2')),
      'lib-course-a',
    );
  });

  testWidgets('an unavailable pin can be removed to free its slot', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setStringList('pinned_course_ids', ['lib-course-gone']);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [
        continueItemsProvider.overrideWith((ref) async => []),
        packProvider(
          packId: 'lib-course-gone',
        ).overrideWith(() => _MissingPack()),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    expect(find.byTooltip('Unpin from Home'), findsOneWidget);
    await tester.tap(find.byTooltip('Unpin from Home'));
    await settle(tester);
    expect(container.read(pinnedCoursesProvider), isEmpty);
    expect(app.prefs.getStringList('pinned_course_ids'), isEmpty);
  });

  testWidgets('the shortcut tiles grow with the text size without overflow', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );
    expect(tester.takeException(), isNull);
    final tile = tester.getSize(find.byKey(const ValueKey('shortcut_timer')));
    expect(tile.height, greaterThan(116));
  });

  testWidgets('with nothing to continue it says so and keeps the shortcuts', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );
    expect(find.byKey(const ValueKey('continue_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut_timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut_sounds')), findsOneWidget);
    expect(find.byKey(const ValueKey('shortcut_add')), findsOneWidget);
  });

  group('shortcuts', () {
    Future<LibraryTestApp> home(WidgetTester tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [continueItemsProvider.overrideWith((ref) async => [])],
      );
      return app;
    }

    testWidgets('Timer opens the timer', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const ValueKey('shortcut_timer')));
      await settle(tester);
      expect(find.byType(TimerView), findsOneWidget);
    });

    testWidgets('Sounds opens the Sounds tab', (tester) async {
      await home(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );
      expect(container.read(mainTabProvider), MainTab.home);
      await tester.tap(find.byKey(const ValueKey('shortcut_sounds')));
      await settle(tester);
      expect(container.read(mainTabProvider), MainTab.sounds);
    });

    testWidgets('Add opens import', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const ValueKey('shortcut_add')));
      await settle(tester);
      expect(find.byType(ImportView), findsOneWidget);
    });
  });

  testWidgets('pinned courses show with progress, and open the course', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    const pack = PackModel(
      id: 'lib-course-a',
      title: 'Course A',
      items: [
        PackItemsModel(
          type: 'track',
          id: 'lib-track-1',
          title: 'One',
          path: '/tracks/lib-track-1',
          isCompleted: true,
        ),
        PackItemsModel(
          type: 'track',
          id: 'lib-track-2',
          title: 'Two',
          path: '/tracks/lib-track-2',
          isCompleted: false,
        ),
        // A session its source has lost is not one of the course's.
        PackItemsModel(
          type: 'track',
          id: 'lib-track-3',
          title: 'Three',
          path: '/tracks/lib-track-3',
          unavailable: true,
        ),
      ],
    );
    await app.pump(
      tester,
      const HomeView(),
      overrides: [
        continueItemsProvider.overrideWith((ref) async => []),
        packProvider(packId: pack.id).overrideWith(() => _FakePack(pack)),
      ],
    );
    expect(find.byType(PinnedCourseTile), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    await tester.runAsync(() async {
      await app.harness.store.add(
        const LibraryDraft(
          sourceId: 'lib-course-a',
          kind: LibraryKind.course,
          title: 'Course A',
          group: LibraryGroup.practice,
        ),
      );
      await app.harness.store.setTitle(pack.id, 'My course');
    });
    await container.read(pinnedCoursesProvider.notifier).pin(pack.id);
    await settle(tester);

    expect(find.byType(PinnedCourseTile), findsOneWidget);
    expect(find.text('My course'), findsOneWidget);
    await tester.runAsync(
      () => app.harness.store.setTitle(pack.id, 'Renamed again'),
    );
    await settle(tester);
    expect(find.text('Renamed again'), findsOneWidget);
    expect(find.byKey(const ValueKey('pinned_lib-course-a')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });

  testWidgets(
    'desktop Customize toggles and reorders without overlapping controls',
    (tester) async {
      // Reset inside the body: addTearDown runs after Flutter's invariant
      // check, which fails the test if the override is still set.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final app = await LibraryTestApp.create(tester);
        await app.pump(tester, const CustomiseHomeLayoutScreen());
        final toggle = find.byKey(const ValueKey('home_section_homeShortcuts'));
        await tester.tap(toggle);
        await settle(tester);
        expect(tester.widget<Switch>(toggle).value, isFalse);
        final handle = find.byType(ReorderableDragStartListener).first;
        final destination = tester.getCenter(
          find.byKey(const ValueKey('pinned')),
        );
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.moveTo(destination + const Offset(0, 90));
        await tester.pump(const Duration(milliseconds: 200));
        await gesture.up();
        await settle(tester);
        expect(
          app.prefs
              .getStringList(SharedPreferenceConstants.homeWidgetOrder)
              ?.last,
          'upNext',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('Customize turns sections off and the change shows on Home', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );

    await tester.tap(find.byKey(const ValueKey('home_customize')));
    await settle(tester);
    expect(find.byType(CustomiseHomeLayoutScreen), findsOneWidget);
    final shortcutsSwitch = find.byKey(
      ValueKey('home_section_${HomeWidgetType.homeShortcuts.name}'),
    );
    expect(tester.widget<Switch>(shortcutsSwitch).value, isTrue);

    await tester.tap(shortcutsSwitch);
    await settle(tester);
    expect(tester.widget<Switch>(shortcutsSwitch).value, isFalse);

    Navigator.of(tester.element(find.byType(CustomiseHomeLayoutScreen))).pop();
    await settle(tester);
    expect(find.byKey(const ValueKey('shortcut_timer')), findsNothing);
    expect(sectionHeader('Shortcuts'), findsNothing);
    expect(sectionHeader('Continue'), findsOneWidget);
  });

  group('design pass: mark, shortcuts, pinned', () {
    const pack = PackModel(
      id: 'lib-course-a',
      title: 'Course A',
      items: [
        PackItemsModel(
          type: 'track',
          id: 'lib-track-1',
          title: 'One',
          path: '/tracks/lib-track-1',
          isCompleted: true,
        ),
      ],
    );

    // Scrolled away, the mark is offstage but still built (cache extent).
    MeditejoMarkState mark(WidgetTester tester) =>
        tester.state<MeditejoMarkState>(
          find.byType(MeditejoMark, skipOffstage: false),
        );

    testWidgets('Home leads with the mark, then shortcuts, then pinned', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [pack.id]);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => [_item('t1')]),
          packProvider(packId: pack.id).overrideWith(() => _FakePack(pack)),
        ],
      );

      double top(Finder f) => tester.getTopLeft(f).dy;
      final markTop = top(find.byType(MeditejoMark));
      final continueTop = top(find.byKey(const ValueKey('continue_t1')));
      final timerTop = top(find.byKey(const ValueKey('shortcut_timer')));
      final pinnedTop = top(find.byKey(const ValueKey('pinned_lib-course-a')));
      expect(markTop, lessThan(continueTop));
      expect(continueTop, lessThan(timerTop));
      expect(timerTop, lessThan(pinnedTop));
      // The mark sits at the top centre.
      expect(
        tester.getCenter(find.byType(MeditejoMark)).dx,
        closeTo(tester.getSize(find.byType(HomeView)).width / 2, 1),
      );
      expect(mark(tester).isRunning, isTrue);
    });

    testWidgets('with reduced motion the mark is still', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const HomeView(),
          ),
        ),
        overrides: [continueItemsProvider.overrideWith((ref) async => [])],
      );
      expect(mark(tester).isRunning, isFalse);
      expect(mark(tester).isStill, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(mark(tester).seconds, 0);
    });

    testWidgets('the mark rests once Home is scrolled past it', (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith(
            (ref) async => [_item('t1'), _item('t2'), _item('t3')],
          ),
        ],
      );
      tester.view.physicalSize = const Size(430, 640);
      await tester.pump();
      expect(mark(tester).isRunning, isTrue);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
      expect(mark(tester).isRunning, isFalse);
      final held = mark(tester).seconds;
      await tester.pump(const Duration(seconds: 2));
      expect(mark(tester).seconds, held);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pump();
      expect(mark(tester).isRunning, isTrue);
    });

    testWidgets('preset tiles show the newest saved presets, then built-ins', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      const mine = SoundPreset(
        id: 'user-1',
        name: 'My rain',
        mix: SoundMix([SoundLayer(soundId: 'rain-terrace', volume: 0.5)]),
      );
      SoundscapeStore(app.prefs).writePresets([mine]);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [continueItemsProvider.overrideWith((ref) async => [])],
      );
      expect(
        find.byKey(const ValueKey('shortcut_preset_user-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('shortcut_preset_${kStarterPresets.first.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('shortcut_preset_${kStarterPresets[1].id}')),
        findsNothing,
      );
      expect(find.text('My rain'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Start the timer with My rain'),
        findsOneWidget,
      );
    });
  });
}

class _FakePack extends Pack {
  _FakePack(this.model);
  final PackModel model;

  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(model);
}

class _MissingPack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) =>
      AsyncError(StateError('Removed'), StackTrace.current);
}
