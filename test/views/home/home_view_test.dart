import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/background_sound/background_sound_view.dart';
import 'package:medito/views/home/customise_home_layout_screen.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/timer/timer_view.dart';

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

void main() {
  testWidgets('shows Continue, quick links and no score or streak', (
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

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Quick links'), findsOneWidget);
    expect(find.byKey(const ValueKey('continue_t1')), findsOneWidget);
    expect(find.text('Title t1'), findsOneWidget);
    expect(find.textContaining('Course A · Session 2 of 5'), findsNWidgets(2));
    expect(find.textContaining('8:00 left'), findsOneWidget);
    // Resume where it was left; Start for the next session of a course.
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start'), findsOneWidget);
    expect(find.textContaining('Consistency'), findsNothing);
    expect(find.textContaining('streak'), findsNothing);
    expect(find.text('Pinned courses'), findsNothing);
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

  testWidgets('with nothing to continue it says so and keeps the quick links', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );
    expect(find.byKey(const ValueKey('continue_empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick_timer')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick_sounds')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick_add')), findsOneWidget);
  });

  group('quick links', () {
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
      await tester.tap(find.byKey(const ValueKey('quick_timer')));
      await settle(tester);
      expect(find.byType(TimerView), findsOneWidget);
    });

    testWidgets('Sounds opens the background sound picker', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const ValueKey('quick_sounds')));
      await settle(tester);
      expect(find.byType(BackgroundSoundView), findsOneWidget);
    });

    testWidgets('Add opens import', (tester) async {
      await home(tester);
      await tester.tap(find.byKey(const ValueKey('quick_add')));
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
    expect(find.text('Pinned courses'), findsNothing);

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

    expect(find.text('Pinned courses'), findsOneWidget);
    expect(find.text('My course'), findsOneWidget);
    await tester.runAsync(
      () => app.harness.store.setTitle(pack.id, 'Renamed again'),
    );
    await settle(tester);
    expect(find.text('Renamed again'), findsOneWidget);
    expect(find.byKey(const ValueKey('pinned_lib-course-a')), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
  });

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
    final quickLinksSwitch = find.byKey(
      ValueKey('home_section_${HomeWidgetType.quickLinks.name}'),
    );
    expect(tester.widget<Switch>(quickLinksSwitch).value, isTrue);

    await tester.tap(quickLinksSwitch);
    await settle(tester);
    expect(tester.widget<Switch>(quickLinksSwitch).value, isFalse);

    Navigator.of(tester.element(find.byType(CustomiseHomeLayoutScreen))).pop();
    await settle(tester);
    expect(find.text('Quick links'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
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
