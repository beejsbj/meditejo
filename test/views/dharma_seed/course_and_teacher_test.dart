import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_ui_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/views/track/track_view.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';

import '../../helpers/art_finders.dart';
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

/// A session's title in its row (the Play button names one too).
Finder _row(String title) => find.descendant(
  of: find.byType(PackItemWidget),
  matching: find.text(title),
);

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
    holdCuratedArt();
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

      expect(find.text('3 of 12 played'), findsOneWidget);
      // The one primary button names that next talk, and plays it.
      expect(
        find.descendant(
          of: find.byType(PackPlayButton),
          matching: find.text(l10n.packContinue),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PackPlayButton),
          matching: find.text('Long talk 4'),
        ),
        findsOneWidget,
      );
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
      // Nothing played: no progress bar yet.
      expect(find.byKey(const ValueKey('course_progress')), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PackPlayButton),
          matching: find.text(l10n.packStart),
        ),
        findsOneWidget,
      );
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

    testWidgets('rows show kind, title and length', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      // The course mixes kinds, so each row has its kind as a chip (#82).
      expect(
        find.descendant(
          of: find.byType(PackItemWidget),
          matching: find.text('Meditation'),
        ),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: find.byType(PackItemWidget),
          matching: find.text('Talk'),
        ),
        findsWidgets,
      );
      expect(_row('Long talk 1'), findsOneWidget);
      // Rob Burbea leads the course, so his rows do not repeat him, and the
      // day group says the date.
      expect(find.text('21\u00A0min'), findsOneWidget);
      expect(find.textContaining('Rob\u00A0Burbea'), findsNothing);
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
      final talk1 = tester.getTopLeft(_row('Long talk 1')).dy;
      final day2 = tester.getTopLeft(find.textContaining('Day 2 · ')).dy;
      expect(day1, lessThan(talk1));
      expect(talk1, lessThan(day2));
    });

    testWidgets('a short course is not grouped', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-100'));
      expect(find.textContaining('Day 1'), findsNothing);
      expect(_row('Settling'), findsOneWidget);
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

    testWidgets('Add to library adds and removes, and says so', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      // An icon toggle beside Pin, named by its tooltip (#81).
      final toggle = find.byKey(const ValueKey('course_library'));
      expect(find.byTooltip('Add to library'), findsOneWidget);
      await tester.tap(toggle);
      await DharmaSeedTestApp.settle(tester);
      expect(find.byTooltip('In library'), findsOneWidget);
      expect(find.text(l10n.libraryAddedSnack), findsOneWidget);
      expect(
        (await tester.runAsync(app.library.entries))!.map((e) => e.sourceId),
        ['ds-retreat-500'],
      );

      // Moved to Talks in the Library, then taken out from the header.
      await tester.runAsync(
        () => app.library.setGroup('ds-retreat-500', LibraryGroup.talks),
      );
      await tester.tap(toggle);
      await DharmaSeedTestApp.settle(tester);
      expect(find.byTooltip('Add to library'), findsOneWidget);
      expect(find.text(l10n.libraryRemovedSnack), findsOneWidget);
      expect(await tester.runAsync(app.library.entries), isEmpty);

      // Undo puts it back as it was, as the Library's own Undo does.
      await tester.tap(find.text(l10n.undo));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byTooltip('In library'), findsOneWidget);
      final entries = (await tester.runAsync(app.library.entries))!;
      expect(entries.map((e) => e.sourceId), ['ds-retreat-500']);
      expect(entries.single.group, LibraryGroup.talks);
    });

    testWidgets('a course already in the library opens as In library', (
      tester,
    ) async {
      final app = await createApp(tester);
      await tester.runAsync(
        () => app.source.setSaved('ds-retreat-500', saved: true),
      );
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));
      expect(find.byTooltip('In library'), findsOneWidget);
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
      expect(_row('Long talk 1'), findsNothing);

      await tester.tap(find.text('Teacher'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('Taught at Gaia House.'), findsOneWidget);
      expect(find.byKey(const ValueKey('course_open_teacher')), findsOneWidget);

      await tester.tap(find.text('Sessions'));
      await DharmaSeedTestApp.settle(tester);
      expect(_row('Long talk 1'), findsOneWidget);
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

    testWidgets('a course header is the course\'s art, by its id', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-300'));
      // Whatever the teacher's photo, the header is the course's own art.
      expect(findArt(courseArt('ds-retreat-300')), findsWidgets);
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
      await tester.tap(_row('Long talk 2'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(TrackView), findsOneWidget);
      await back();

      // Press the one primary button: a talk has one voice and one file,
      // nothing to choose, so it plays the first talk at once rather than
      // opening its page. Nothing is marked played by starting it.
      await tester.tap(
        find.bySemanticsLabel(RegExp('^${l10n.packStart}: ')).first,
      );
      await DharmaSeedTestApp.settle(tester);
      // The player precaches the teacher's photo, which cannot load here.
      while (tester.takeException() != null) {}
      expect(find.byType(TrackView), findsNothing);
      expect(find.byType(PlayerView), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerView)),
      );
      expect(container.read(playerProvider)?.title, 'Long talk 1');
      Navigator.of(tester.element(find.byType(PlayerView))).pop();
      await DharmaSeedTestApp.settle(tester);

      // The real stats store exists by now, and no talk is checked off.
      final stats = app.prefs.getString('local_all_stats');
      expect(stats, isNotNull);
      final checked = (jsonDecode(stats!) as Map)['tracks_checked'];
      expect(checked == null || (checked as List).isEmpty, isTrue);
      expect(find.byKey(const ValueKey('course_progress')), findsNothing);
    });
  });

  group('track details', () {
    testWidgets('show course, teacher, kind and date, length on Play, then '
        'credit and licence', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TrackView(trackId: 'ds-talk-2'));

      expect(find.text('Jhana basics'), findsOneWidget);
      // The retreat it is part of, and who gave it, each a link (#84).
      expect(find.textContaining('Part of Jhana Retreat'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('track_teacher')),
          matching: find.text('Rob Burbea'),
        ),
        findsOneWidget,
      );
      expect(find.text('Talk · Mar 1, 2014'), findsOneWidget);
      expect(find.text('Play · 60 min'), findsOneWidget);
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
      // Dharma Seed has no archive: the plain Talks section, as before.
      expect(find.text('Archive'), findsNothing);
      expect(find.text('Latest talks'), findsNothing);
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

    testWidgets('Adding a teacher puts them in the library', (tester) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const TeacherView(teacherId: 'ds-teacher-1'));

      await tester.tap(find.text('Add to library'));
      await DharmaSeedTestApp.settle(tester);
      expect(find.text('In library'), findsOneWidget);
      final entries = (await tester.runAsync(app.library.entries))!;
      expect(entries.single.sourceId, 'ds-teacher-1');
      expect(entries.single.kind, LibraryKind.teacher);
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

      await tester.ensureVisible(
        find.byKey(const ValueKey('teacher_show_more')),
      );
      await tester.pumpAndSettle();
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

    testWidgets('a page that loads after a refresh is dropped, not appended', (
      tester,
    ) async {
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
      final gate = Completer<void>();
      final slow = _SlowTeacherTalks(app.db, gate.future);
      await app.pump(
        tester,
        const TeacherView(teacherId: 'ds-teacher-3'),
        withSource: slow,
      );
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('teacher_show_more')),
        300,
        scrollable: scrollable,
      );
      await tester.tap(find.byKey(const ValueKey('teacher_show_more')));
      await tester.pump();

      // A sync lands while the second page is still loading.
      ProviderScope.containerOf(
        tester.element(find.byType(TeacherView)),
      ).invalidate(catalogueTeacherProvider('ds-teacher-3'));
      await DharmaSeedTestApp.settle(tester);
      gate.complete();
      await DharmaSeedTestApp.settle(tester);

      // The stale page was dropped: the fresh first page still offers more.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('teacher_show_more')),
        300,
        scrollable: scrollable,
      );
      expect(find.byKey(const ValueKey('teacher_show_more')), findsOneWidget);
      expect(find.text('Prolific talk 01'), findsNothing);
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

/// A source whose further teacher talks arrive only once [gate] opens.
class _SlowTeacherTalks extends DharmaSeedSource {
  _SlowTeacherTalks(DharmaSeedDatabase db, this.gate)
    : super(db: db, browseLimit: 10);

  final Future<void> gate;

  @override
  Future<List<PackItemsModel>> teacherTalks(
    String id, {
    required int offset,
    int limit = 30,
  }) async {
    await gate;
    return super.teacherTalks(id, offset: offset, limit: limit);
  }
}
