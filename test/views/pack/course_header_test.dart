import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/pack/widgets/pack_item_widget.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/player/widgets/bottom_actions/pack_view_bottom_bar.dart';
import 'package:medito/views/teacher/teacher_view.dart';
import 'package:medito/widgets/attribution_notice.dart';

import '../../helpers/art_finders.dart';
import '../../helpers/dharma_seed_app.dart';
import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/library_app.dart';
import '../dharma_seed/course_and_teacher_test.dart' show createApp;

class _FakePack extends Pack {
  _FakePack(this.model);
  final PackModel model;

  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(model);
}

/// A YouTube series: no teacher record, its channel as the subtitle.
final _series = PackModel(
  id: 'yt-playlist-series',
  title: 'Meditating with John Vervaeke',
  subtitle: 'John Vervaeke',
  attribution: const SourceAttribution(
    source: 'YouTube',
    creator: 'John Vervaeke',
    url: 'https://www.youtube.com/playlist?list=series',
    licenseName: '',
    licenseUrl: '',
  ),
  items: [
    for (var i = 0; i < 18; i++)
      PackItemsModel(
        type: 'track',
        id: 'yt-video-$i',
        title: 'Day ${i + 1}',
        path: '/tracks/yt-video-$i',
        durationMs: 30 * 60000,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;
  setUpAll(() async {
    holdCuratedArt();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Finder inBar(Finder finder) =>
      find.descendant(of: find.byType(PackViewBottomBar), matching: finder);

  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(CustomScrollView), Offset(0, -dy));
    // The bar's Play follows a frame after the scroll, then fades.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('the course header (#81)', () {
    testWidgets('says who, when, how many and how long, in sessions', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        played: ['ds-talk-501', 'ds-talk-502', 'ds-talk-503'],
      );

      // Twelve talks of 21 to 32 minutes, recorded in 2020: "sessions",
      // whatever Dharma Seed calls them.
      expect(find.text('2020 · 12 sessions · 5 h 18 min'), findsOneWidget);
      expect(find.textContaining('talks'), findsNothing);
      expect(find.text('3 of 12 played'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // The teacher's name opens their page.
      await tester.tap(find.byKey(const ValueKey('course_teacher')));
      await DharmaSeedTestApp.settle(tester);
      expect(find.byType(TeacherView), findsOneWidget);
    });

    testWidgets('a series names its channel, not a teacher page', (
      tester,
    ) async {
      final app = await LibraryTestApp.create(tester);
      await app.pump(
        tester,
        PackView(id: _series.id),
        overrides: [
          packProvider(
            packId: _series.id,
          ).overrideWith(() => _FakePack(_series)),
        ],
      );
      expect(find.text('John Vervaeke'), findsOneWidget);
      expect(find.byKey(const ValueKey('course_teacher')), findsNothing);
      expect(find.text('18 sessions · 9 h'), findsOneWidget);
      // Nothing played yet: no progress to show.
      expect(find.byKey(const ValueKey('course_progress')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('Play across the width, then Library, Pin, Share, more', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      final play = find.byType(PackPlayButton);
      final keys = [
        'course_library',
        'course_pin',
        'course_share',
        'pack_actions',
      ];
      expect(play, findsOneWidget);
      // Play spans the header's content width (20 dp gutters).
      final width = tester.getSize(find.byType(PackView)).width;
      expect(tester.getSize(play).width, closeTo(width - 40, 1));
      // The toggles share one line under it, in this order.
      final row = tester.getCenter(find.byKey(ValueKey(keys.first))).dy;
      expect(row, greaterThan(tester.getBottomLeft(play).dy));
      var left = 0.0;
      for (final key in keys) {
        final control = find.byKey(ValueKey(key));
        expect(control, findsOneWidget, reason: key);
        expect(tester.getCenter(control).dy, closeTo(row, 1), reason: key);
        expect(tester.getTopLeft(control).dx, greaterThan(left), reason: key);
        left = tester.getTopLeft(control).dx;
      }
      // Each still a full-size target at phone width.
      for (final key in keys) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).width,
          greaterThanOrEqualTo(44),
        );
      }
    });

    testWidgets('the header\'s ⋮ leaves out Play, Pin and Share; rows keep '
        'them', (tester) async {
      final app = await createApp(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      Future<Set<String>> sheet() async {
        await DharmaSeedTestApp.settle(tester);
        final titles = {
          for (final tile in tester.widgetList<ListTile>(
            find.descendant(
              of: find.byKey(const ValueKey('item_actions_sheet')),
              matching: find.byType(ListTile),
            ),
          ))
            (tile.title! as Text).data!,
        };
        await tester.tapAt(const Offset(20, 20));
        await DharmaSeedTestApp.settle(tester);
        return titles;
      }

      // In the library, so Pin applies; the header shows it as a button.
      await tester.tap(find.byKey(const ValueKey('course_library')));
      await DharmaSeedTestApp.settle(tester);

      await tester.tap(find.byKey(const ValueKey('pack_actions')));
      final header = await sheet();
      expect(header, contains(l10n.myCourseAddTo));
      expect(header, contains(l10n.myCourseDuplicate));
      for (final repeated in [l10n.play, l10n.pinCourse, l10n.share]) {
        expect(header, isNot(contains(repeated)), reason: repeated);
      }

      // A session row's ⋮ and long-press still offer them.
      final row = find.byKey(const ValueKey('content_actions_ds-talk-501'));
      await tester.ensureVisible(row);
      await DharmaSeedTestApp.settle(tester);
      await tester.tap(row);
      expect(await sheet(), containsAll([l10n.play, l10n.share]));
      await tester.longPress(
        find.descendant(
          of: find.byType(PackItemWidget),
          matching: find.text('Long talk 1'),
        ),
      );
      expect(await sheet(), containsAll([l10n.play, l10n.share]));
    });

    testWidgets('the bottom bar is Back, and Play once the header is gone', (
      tester,
    ) async {
      final app = await createApp(tester);
      await app.pump(
        tester,
        const PackView(id: 'ds-retreat-500'),
        played: ['ds-talk-501'],
      );
      final handle = tester.ensureSemantics();

      // None of the course's actions sit in the bar.
      expect(inBar(find.byTooltip(l10n.goBack)), findsOneWidget);
      for (final key in ['pack_actions', 'course_share', 'course_pin']) {
        expect(inBar(find.byKey(ValueKey(key))), findsNothing);
      }
      expect(inBar(find.byType(PackPlayButton)), findsNothing);

      // Into the sessions: the header's Play is under the title bar, so the
      // bar offers it, naming the session.
      await scrollBy(tester, 900);
      expect(inBar(find.byType(PackPlayButton)), findsOneWidget);
      expect(inBar(find.text(l10n.packContinue)), findsOneWidget);
      expect(inBar(find.text('Long talk 2')), findsOneWidget);

      // Back at the top, the header has it again.
      await scrollBy(tester, -2000);
      expect(inBar(find.byType(PackPlayButton)), findsNothing);
      handle.dispose();
    });

    testWidgets('the tabs stay under the title, and a new tab opens at its '
        'top', (tester) async {
      final app = await createApp(tester);
      // Long enough to scroll well past the tabs: twelve more talks over
      // four more days, as the rows are compact (#82).
      await tester.runAsync(() async {
        await app.db.upsertRetreatRecords({
          500: {
            'name': 'Long Retreat',
            'description': 'Seven days of silence, then four days of talks.',
            'start_date': '2020-05-01',
            'talks': [for (var i = 1; i <= 24; i++) 500 + i],
          },
        });
        await app.db.upsertTalkRecords({
          for (var i = 13; i <= 24; i++)
            500 + i: dsTalkRecord(
              'Long talk $i',
              teacher: 1,
              retreat: 500,
              date: '2020-05-0${1 + (i - 1) ~/ 3} 10:00:00',
            ),
        });
      });
      await app.pump(tester, const PackView(id: 'ds-retreat-500'));

      final tabs = find.text(l10n.courseSessionsTab);
      await scrollBy(tester, 1200);
      final pinnedTop = tester.getTopLeft(tabs).dy;
      // Under the collapsed title bar, not scrolled away.
      expect(pinnedTop, greaterThan(64));
      expect(pinnedTop, lessThan(200));
      await scrollBy(tester, 300);
      expect(tester.getTopLeft(tabs).dy, closeTo(pinnedTop, 0.5));

      // Deep in the sessions, Summary opens at its own start, tabs in place.
      await tester.tap(find.text(l10n.courseSummaryTab));
      await DharmaSeedTestApp.settle(tester);
      expect(tester.getTopLeft(tabs).dy, closeTo(pinnedTop, 0.5));
      final summary = find.textContaining('Seven days of silence');
      expect(summary, findsOneWidget);
      expect(tester.getTopLeft(summary).dy, greaterThan(pinnedTop));
      expect(tester.getTopLeft(summary).dy, lessThan(pinnedTop + 200));
      // The room that keeps them there is only for that moment: back at
      // the top, it goes.
      expect(find.byType(SliverLayoutBuilder), findsOneWidget);
      await scrollBy(tester, -3000);
      expect(find.byType(SliverLayoutBuilder), findsNothing);
    });

    testWidgets('a course at rest has no blank room below its sessions', (
      tester,
    ) async {
      final app = await DharmaSeedTestApp.create(tester);
      await app.pump(tester, const PackView(id: 'ds-retreat-100'));
      expect(find.byType(SliverLayoutBuilder), findsNothing);
      await scrollBy(tester, 3000);
      // Scrolled to the end, the end of the page meets the bottom bar.
      final viewport = tester.getBottomLeft(find.byType(CustomScrollView)).dy;
      final last = tester.getBottomLeft(find.byType(AttributionNotice)).dy;
      expect(viewport - last, lessThan(48));
    });

    // The bottom bar's copy shares its row with Back: a finished course's
    // long "Volver a empezar" at a large text size must fit there too.
    for (final (width, scale) in const [(360.0, 2.0), (320.0, 1.3)]) {
      testWidgets('the bar\'s Play again fits: es, ${width.toInt()} dp, '
          'text x$scale', (tester) async {
        final app = await createApp(tester);
        await app.pump(
          tester,
          Builder(
            builder: (context) => Localizations.override(
              context: context,
              locale: const Locale('es'),
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: const PackView(id: 'ds-retreat-500'),
              ),
            ),
          ),
          played: [for (var i = 1; i <= 12; i++) 'ds-talk-${500 + i}'],
        );
        tester.view.physicalSize = Size(width, 900);
        await tester.pump();
        await scrollBy(tester, 1500);
        expect(tester.takeException(), isNull);

        final es = await AppLocalizations.delegate.load(const Locale('es'));
        final bar = inBar(find.byType(PackPlayButton));
        expect(bar, findsOneWidget);
        final action = find.descendant(
          of: bar,
          matching: find.byKey(const ValueKey('play_action')),
        );
        expect(tester.widget<Text>(action).data, es.coursePlayAgain);
        // Inside the screen, beside Back.
        expect(tester.getTopRight(bar).dx, lessThanOrEqualTo(width));
        expect(
          tester.getTopLeft(bar).dx,
          greaterThan(tester.getTopRight(inBar(find.byType(IconButton))).dx),
        );
      });
    }

    // Words in de and es run long; the action word must never be cut, at
    // the narrowest phones and at a larger text size.
    for (final locale in const ['en', 'de', 'es']) {
      for (final width in const [360.0, 411.0]) {
        for (final scale in const [1.0, 1.3]) {
          testWidgets('Play keeps its action whole: $locale, ${width.toInt()} '
              'dp, text x$scale', (tester) async {
            final app = await createApp(tester);
            await app.pump(
              tester,
              Builder(
                builder: (context) => Localizations.override(
                  context: context,
                  locale: Locale(locale),
                  child: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: const PackView(id: 'ds-retreat-500'),
                  ),
                ),
              ),
              played: ['ds-talk-501', 'ds-talk-502', 'ds-talk-503'],
            );
            tester.view.physicalSize = Size(width, 900);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);

            final words = await AppLocalizations.delegate.load(Locale(locale));
            final action = find.descendant(
              of: find.byType(PackPlayButton),
              matching: find.byKey(const ValueKey('play_action')),
            );
            expect(tester.widget<Text>(action).data, words.packContinue);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: action, matching: find.byType(RichText)),
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            // The four toggles still fit their row.
            for (final key in const ['course_library', 'pack_actions']) {
              expect(
                tester.getTopRight(find.byKey(ValueKey(key))).dx,
                lessThanOrEqualTo(width),
              );
            }
          });
        }
      }
    }
  });
}
