import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/views/pack/pack_view.dart';
import 'package:medito/views/pack/widgets/pack_path_button.dart';
import 'package:medito/views/player/widgets/bottom_actions/pack_view_bottom_bar.dart';
import 'package:medito/views/teacher/teacher_view.dart';

import '../../helpers/art_finders.dart';
import '../../helpers/dharma_seed_app.dart';
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
      expect(find.text('0 of 18 played'), findsOneWidget);
    });

    testWidgets('one row: Play, Library, Pin, Share and more', (tester) async {
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
      final row = tester.getCenter(play).dy;
      var left = tester.getTopRight(play).dx;
      for (final key in keys) {
        final control = find.byKey(ValueKey(key));
        expect(control, findsOneWidget, reason: key);
        // On the Play's line, in this order, after it.
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
      expect(
        inBar(find.text('${l10n.packContinue}: Long talk 2')),
        findsOneWidget,
      );

      // Back at the top, the header has it again.
      await scrollBy(tester, -2000);
      expect(inBar(find.byType(PackPlayButton)), findsNothing);
      handle.dispose();
    });

    testWidgets('the tabs stay under the title, and a new tab opens at its '
        'top', (tester) async {
      final app = await createApp(tester);
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
    });
  });
}
