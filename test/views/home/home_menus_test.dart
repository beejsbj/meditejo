import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/home/pinned_courses_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/pack/pack_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

Future<void> settle(WidgetTester tester) => DharmaSeedTestApp.settle(tester);

const _pack = PackModel(
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

ContinueItem _item({bool resume = true}) => ContinueItem(
  trackId: 't1',
  path: '/tracks/t1',
  title: 'Title t1',
  group: LibraryGroup.practice,
  lastPlayed: DateTime(2026, 10, 19),
  courseId: 'lib-course-a',
  courseTitle: 'Course A',
  resume: resume
      ? const ResumePoint(positionMs: 120000, durationMs: 600000)
      : null,
  sessionNumber: 4,
  sessionTotal: 32,
);

class _FakePack extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) =>
      const AsyncData(_pack);
}

Future<LibraryTestApp> _pumpHome(
  WidgetTester tester, {
  bool resume = true,
  bool pinned = false,
}) async {
  final app = await LibraryTestApp.create(tester);
  if (pinned) await app.prefs.setStringList('pinned_course_ids', [_pack.id]);
  await app.pump(
    tester,
    const HomeView(),
    overrides: [
      continueItemsProvider.overrideWith(
        (ref) async => pinned ? [] : [_item(resume: resume)],
      ),
      packProvider(packId: _pack.id).overrideWith(_FakePack.new),
    ],
  );
  return app;
}

void main() {
  group('Continue card menu', () {
    for (final how in ['long-press', 'the more button']) {
      testWidgets('opens with $how and offers all three actions', (
        tester,
      ) async {
        await _pumpHome(tester);
        if (how == 'long-press') {
          await tester.longPress(find.byKey(const ValueKey('continue_t1')));
        } else {
          await tester.tap(find.byTooltip('More options'));
        }
        await settle(tester);
        expect(find.text('Open course'), findsOneWidget);
        expect(find.text('Restart'), findsOneWidget);
        expect(find.text('Remove from Continue'), findsOneWidget);
      });
    }

    testWidgets('a course start has nothing to restart', (tester) async {
      await _pumpHome(tester, resume: false);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      expect(find.text('Open course'), findsOneWidget);
      expect(find.text('Restart'), findsNothing);
    });

    testWidgets('Open course shows the course page', (tester) async {
      await _pumpHome(tester);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_open_course')));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('Restart forgets where it stopped', (tester) async {
      final app = await _pumpHome(tester);
      await tester.runAsync(
        () => app.harness.store.savePosition('t1', 120000, 600000),
      );
      expect(
        await tester.runAsync(() => app.harness.store.resumePoint('t1')),
        isNotNull,
      );
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_restart')));
      await settle(tester);
      expect(
        await tester.runAsync(() => app.harness.store.resumePoint('t1')),
        isNull,
      );
    });

    testWidgets('Remove from Continue records it by course', (tester) async {
      final app = await _pumpHome(tester);
      await tester.longPress(find.byKey(const ValueKey('continue_t1')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('continue_menu_remove')));
      await settle(tester);
      final saved = app.prefs.getStringList('continue_dismissed');
      expect(saved, hasLength(1));
      expect(saved!.single, startsWith('lib-course-a|'));
    });

    testWidgets('keeps "Session 4 of 32" whole beside a long course title', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith(
            (ref) async => [
              ContinueItem(
                trackId: 't1',
                path: '/tracks/t1',
                title: 'Developing Piti, Developing Focus',
                group: LibraryGroup.practice,
                lastPlayed: DateTime(2026, 10, 19),
                courseId: 'c',
                courseTitle: 'Practising the Jhānas: A Complete Course',
                resume: const ResumePoint(
                  positionMs: 1800000,
                  durationMs: 5340000,
                ),
                sessionNumber: 4,
                sessionTotal: 32,
              ),
            ],
          ),
        ],
      );
      expect(find.text('Session 4 of 32 ·'), findsOneWidget);
      expect(find.text('59:00 left'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Pinned card menu', () {
    for (final how in ['long-press', 'the more button']) {
      testWidgets('opens with $how', (tester) async {
        await _pumpHome(tester, pinned: true);
        if (how == 'long-press') {
          await tester.longPress(
            find.byKey(const ValueKey('pinned_lib-course-a')),
          );
        } else {
          await tester.tap(find.byTooltip('More options'));
        }
        await settle(tester);
        expect(find.text('Open'), findsOneWidget);
        expect(find.text('Play'), findsOneWidget);
        expect(find.text('Unpin from Home'), findsOneWidget);
      });
    }

    testWidgets('Open shows the course page', (tester) async {
      await _pumpHome(tester, pinned: true);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pinned_menu_open')));
      await settle(tester);
      expect(find.byType(PackView), findsOneWidget);
    });

    testWidgets('Unpin offers Undo, which pins it back in place', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setStringList('pinned_course_ids', [_pack.id, 'other']);
      await app.pump(
        tester,
        const HomeView(),
        overrides: [
          continueItemsProvider.overrideWith((ref) async => []),
          packProvider(packId: _pack.id).overrideWith(_FakePack.new),
          packProvider(packId: 'other').overrideWith(_FakePack.new),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );

      await tester.tap(find.byTooltip('More options').first);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pinned_menu_unpin')));
      await settle(tester);
      expect(container.read(pinnedCoursesProvider), ['other']);
      expect(find.text('Unpinned from Home'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester);
      expect(container.read(pinnedCoursesProvider), [_pack.id, 'other']);
      expect(app.prefs.getStringList('pinned_course_ids'), [_pack.id, 'other']);
    });
  });
}
