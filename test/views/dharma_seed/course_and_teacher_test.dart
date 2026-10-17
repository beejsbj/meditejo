import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/generated_artwork.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/dharma_seed_catalogue.dart';

/// A twelve-talk retreat over four days (2020-05-01 to 05-04, three a day),
/// by teacher 1: the first talk of each day is a guided meditation.
Future<void> seedLongRetreat(DharmaSeedDatabase db) async {
  await db.upsertRetreatRecords({
    500: {
      'name': 'Long Retreat',
      'description': 'Seven days of silence, then four days of talks.',
      'start_date': '2020-05-01',
      'talks': [for (var i = 1; i <= 12; i++) 500 + i],
    },
  });
  await db.upsertTalkRecords({
    for (var i = 1; i <= 12; i++)
      500 + i: dsTalkRecord(
        'Long talk $i',
        teacher: 1,
        retreat: 500,
        type: (i - 1) % 3 == 0 ? 'Meditation' : 'Talk',
        minutes: 20.0 + i,
        date:
            '2020-05-0${1 + (i - 1) ~/ 3} '
            '${(8 + (i - 1) % 3 * 4).toString().padLeft(2, '0')}:00:00',
      ),
  });
}

Future<DharmaSeedTestApp> createApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
}) async {
  final app = await DharmaSeedTestApp.create(tester, prefs: prefs);
  await tester.runAsync(() => seedLongRetreat(app.db));
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('course page', () {
    testWidgets('says how much is left and what plays next', (tester) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        played: ['ds-talk-501', 'ds-talk-502', 'ds-talk-503'],
      );

      expect(find.text('9 of 12 left'), findsOneWidget);
      expect(find.text('Resume: Long talk 4'), findsOneWidget);
      // The one primary button plays that next talk. (The page also keeps an
      // invisible placeholder copy in the tree; it has no semantics.)
      expect(
        find
            .bySemanticsLabel(
              RegExp(
                '^${l10n.packContinue}: Long talk 4\\. '
                '${l10n.upNextProgress(3, 12)}',
              ),
            )
            .first,
        findsOneWidget,
      );
    });

    testWidgets('a fresh course offers Start', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));
      expect(find.text('12 of 12 left'), findsOneWidget);
      expect(find.text('Start: Long talk 1'), findsOneWidget);
    });

    testWidgets('a finished course says so', (tester) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        played: [for (var i = 1; i <= 12; i++) 'ds-talk-${500 + i}'],
      );
      expect(find.text('All 12 played'), findsOneWidget);
    });

    testWidgets('rows show kind, title, teacher and length', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      expect(find.text('GUIDED MEDITATION'), findsWidgets);
      expect(find.text('TALK'), findsWidgets);
      expect(find.text('Long talk 1'), findsOneWidget);
      expect(find.text('Rob Burbea · 21 min'), findsOneWidget);
    });

    testWidgets('a long retreat is grouped by day, numbered from the first', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      expect(find.textContaining('Day 1 · '), findsOneWidget);
      expect(find.textContaining('Day 2 · '), findsOneWidget);
      // The heading sits above its own talks.
      final day1 = tester.getTopLeft(find.textContaining('Day 1 · ')).dy;
      final talk1 = tester.getTopLeft(find.text('Long talk 1')).dy;
      final day2 = tester.getTopLeft(find.textContaining('Day 2 · ')).dy;
      expect(day1, lessThan(talk1));
      expect(talk1, lessThan(day2));
    });

    testWidgets('a short course is not grouped', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-100'));
      expect(find.textContaining('Day 1'), findsNothing);
      expect(find.text('Settling'), findsOneWidget);
    });

    testWidgets('shows which sessions are played and which are downloaded', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        played: ['ds-talk-501'],
        downloaded: {'ds-talk-501', 'ds-talk-502'},
      );

      expect(find.bySemanticsLabel(l10n.markTrackIncomplete), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsNWidgets(2));
    });

    testWidgets('Save course saves and unsaves, and says so', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      expect(find.text('Save course'), findsOneWidget);
      await tester.tap(find.text('Save course'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        await tester.runAsync(() => app.db.savedIds(DsSavedKind.retreat)),
        [500],
      );

      await tester.tap(find.text('Saved'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Save course'), findsOneWidget);
      expect(
        await tester.runAsync(() => app.db.savedIds(DsSavedKind.retreat)),
        isEmpty,
      );
    });

    testWidgets('an already saved course opens as Saved', (tester) async {
      final app = await createApp(tester);
      await tester.runAsync(
        () => app.db.setSaved(DsSavedKind.retreat, 500, saved: true),
      );
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('Summary and Teacher tabs, with the credit throughout', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      // Sessions tab: the credit closes the page.
      await tester.scrollUntilVisible(
        find.byType(AttributionNotice),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Licence: CC BY-NC-ND 4.0'), findsOneWidget);
      expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
      expect(find.text('Streamed as recorded, unmodified.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Summary'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Summary'));
      await DharmaSeedTestApp.settle(tester);
      expect(
        find.textContaining('Seven days of silence, then four days of talks.'),
        findsOneWidget,
      );
      expect(find.text('Long talk 1'), findsNothing);

      await tester.tap(find.text('Teacher'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Taught at Gaia House.'), findsOneWidget);
      expect(find.byKey(const ValueKey('course_open_teacher')), findsOneWidget);

      await tester.tap(find.text('Sessions'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Long talk 1'), findsOneWidget);
    });

    testWidgets('a course with no description says so in Summary', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-300'));
      await tester.tap(find.text('Summary'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('This course has no written summary.'), findsOneWidget);
    });

    testWidgets('a course with no teacher photo gets generated art', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-300'));
      // Leigh Brasington has no photo: the header art is generated.
      expect(find.byType(GeneratedArtwork), findsWidgets);
    });

    testWidgets('opening a course, a talk or Start marks nothing played', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        realStats: true,
      );
      expect(find.byType(PackCompleteBadge), findsNothing);

      Future<void> back() async {
        Navigator.of(tester.element(find.byType(TrackView))).pop();
        await DharmaSeedTestApp.settle(tester);
      }

      // Open a talk from the list, then come back.
      await tester.tap(find.text('Long talk 2'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(TrackView), findsOneWidget);
      await back();

      // Press the one primary button: it opens the first talk, not played.
      await tester.tap(
        find.bySemanticsLabel(RegExp('^${l10n.packStart}: ')).first,
      );
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(TrackView), findsOneWidget);
      expect(find.text('Long talk 1'), findsWidgets);
      await back();

      // The real stats store exists by now, and no talk is checked off.
      final stats = app.prefs.getString('local_all_stats');
      expect(stats, isNotNull);
      final checked = (jsonDecode(stats!) as Map)['tracks_checked'];
      expect(checked == null || (checked as List).isEmpty, isTrue);
      expect(find.text('12 of 12 left'), findsOneWidget);
    });
  });

  group('track details', () {
    testWidgets('show kind, teacher and length, then credit and licence', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TrackView(trackId: 'ds-talk-2'));

      expect(find.text('Jhana basics'), findsOneWidget);
      expect(find.text('Talk · Rob Burbea · 60 min'), findsOneWidget);
      expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
      expect(find.text('Licence: CC BY-NC-ND 4.0'), findsOneWidget);
      expect(find.text('Streamed as recorded, unmodified.'), findsOneWidget);
    });
  });

  group('teacher page', () {
    testWidgets('shows who they are, their courses and their talks', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-1'));

      expect(find.text('Rob Burbea'), findsWidgets);
      expect(find.text('6 talks · 2 courses'), findsOneWidget);
      expect(find.text('Taught at Gaia House.'), findsOneWidget);
      expect(find.text('Jhana Retreat'), findsOneWidget);
      expect(find.text('Dharma Talks Winter'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Untyped talk about jhana'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Untyped talk about jhana'), findsOneWidget);
      // The credit with the talks.
      await tester.scrollUntilVisible(
        find.byType(AttributionNotice),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Licence: CC BY-NC-ND 4.0'), findsOneWidget);
    });

    testWidgets('Save teacher saves and shows Saved', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-1'));

      await tester.tap(find.text('Save teacher'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Saved'), findsOneWidget);
      expect(
        await tester.runAsync(() => app.db.savedIds(DsSavedKind.teacher)),
        [1],
      );
    });

    testWidgets('a teacher without a biography says so', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-2'));
      expect(find.text('No biography on Dharma Seed.'), findsOneWidget);
    });

    testWidgets('Show more talks loads the next page', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await tester.runAsync(() async {
        await app.db.upsertTeacherRecords({
          3: {'name': 'Prolific Teacher', 'bio': '', 'photo': ''},
        });
        await app.db.upsertTalkRecords({
          for (var i = 1; i <= 35; i++)
            1000 + i: dsTalkRecord(
              'Prolific talk ${i.toString().padLeft(2, '0')}',
              teacher: 3,
              date: '2019-01-${i.toString().padLeft(2, '0')} 10:00:00',
            ),
        });
      });
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-3'));
      final scrollable = find.byType(Scrollable).first;

      // Newest first: the oldest talk is on the second page.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('teacher_show_more')),
        300,
        scrollable: scrollable,
      );
      expect(find.text('Prolific talk 01'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('teacher_show_more')));
      await DharmaSeedTestApp.settle(tester);
      await tester.scrollUntilVisible(
        find.text('Prolific talk 01'),
        300,
        scrollable: scrollable,
      );
      expect(find.text('Prolific talk 01'), findsOneWidget);
      expect(find.byKey(const ValueKey('teacher_show_more')), findsNothing);
    });

    testWidgets('an unknown teacher says so', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-404'));
      expect(
        find.text('This teacher is not in the library yet.'),
        findsOneWidget,
      );
    });
  });
}
