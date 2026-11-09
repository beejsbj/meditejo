import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/home/widgets/update_notice.dart';
import 'package:medito/views/splash_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import '../../helpers/library_app.dart';

// Home's mark is quiet at rest and alive in two moments (#63): a tap sends
// one deep breath through it, and the first time Home is seen on a new day
// the last daily mark seen turns into today's, with today's name shown for
// a few seconds.

final _day1 = DateTime(2026, 10, 25, 9);
final _day2 = DateTime(2026, 10, 26, 9);
const _seenKey = SharedPreferenceConstants.homeMarkSeenDay;

MarkSpec _markOf(DateTime day) =>
    MarkGenerator.build(DailyMark.forDay(day).seed);

String _nameOf(DateTime day) =>
    lookupAppLocalizations(const Locale('en')).homeMarkName(_markOf(day).type);

final _homeMark = find.descendant(
  of: find.byKey(const ValueKey('home_mark'), skipOffstage: false),
  matching: find.byType(MeditejoMark, skipOffstage: false),
);
final _name = find.byKey(const ValueKey('home_mark_name'), skipOffstage: false);

MeditejoMarkState _state(WidgetTester tester) =>
    tester.state<MeditejoMarkState>(_homeMark);

MeditejoMark _widget(WidgetTester tester) =>
    tester.widget<MeditejoMark>(_homeMark);

double _nameOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.ancestor(of: _name, matching: find.byType(Opacity)).first,
    )
    .opacity;

final _overrides = [continueItemsProvider.overrideWith((ref) async => [])];

void main() {
  late DateTime now;

  setUp(() {
    now = _day2;
    identityClock = () => now;
  });
  tearDown(() => identityClock = DateTime.now);

  testWidgets(
    "the first Home of a new day turns yesterday's mark into today's, once",
    (tester) async {
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setString(_seenKey, '2026-10-25');
      await app.pump(tester, const HomeView(), overrides: _overrides);

      // The turn has played (the pump runs on past it).
      expect(_widget(tester).mark.seed, _markOf(_day2).seed);
      expect(_state(tester).isArriving, isFalse);
      expect(app.prefs.getString(_seenKey), '2026-10-26');
      // The name came and went, and was announced once.
      expect(_name, findsNothing);
      expect(tester.takeAnnouncements().map((a) => a.message), [
        "Today's mark: ${_nameOf(_day2)}",
      ]);

      // Opened again the same day: no turn, no name.
      await app.pump(tester, const SizedBox(), overrides: _overrides);
      await app.pump(tester, const HomeView(), overrides: _overrides);
      expect(_widget(tester).from, isNull);
      expect(tester.takeAnnouncements(), isEmpty);
    },
  );

  testWidgets('not while the intro covers Home; it plays once Home shows', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-25');
    await app.pump(
      tester,
      const SplashView(root: HomeView()),
      overrides: _overrides,
    );
    expect(find.byKey(const ValueKey('intro_start')), findsOneWidget);

    // Built under the intro, Home's mark hasn't been seen: it still holds
    // yesterday's, the day isn't counted and no name shows.
    expect(_state(tester).arrivingFrom?.seed, _markOf(_day1).seed);
    expect(_state(tester).arrival, 0);
    expect(_state(tester).seconds, -MarkMoments.morphLead);
    expect(app.prefs.getString(_seenKey), '2026-10-25');
    expect(_name, findsNothing);
    expect(tester.takeAnnouncements(), isEmpty);

    await tester.tap(find.byKey(const ValueKey('intro_start')));
    await tester.pump();
    await tester.pump();
    expect(app.prefs.getString(_seenKey), '2026-10-26');
    expect(_name, findsOneWidget);
    expect(_nameOpacity(tester), 0);

    // Yesterday's un-draws as today's draws in.
    await tester.pump(const Duration(seconds: 1));
    expect(_state(tester).isArriving, isTrue);
    expect(_state(tester).arrival, greaterThan(0.3));
    expect(_state(tester).arrival, lessThan(0.7));

    // Today's name rests while today's mark draws itself in.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_state(tester).isArriving, isFalse);
    expect(_state(tester).seconds, greaterThan(1));
    expect(find.text(_nameOf(_day2)), findsOneWidget);
    expect(_nameOpacity(tester), 1);

    // Then it fades and goes.
    await tester.pump(const Duration(milliseconds: 2800));
    expect(_nameOpacity(tester), greaterThan(0));
    expect(_nameOpacity(tester), lessThan(1));
    await tester.pump(const Duration(seconds: 2));
    expect(_name, findsNothing);
    expect(tester.takeAnnouncements().map((a) => a.message), [
      "Today's mark: ${_nameOf(_day2)}",
    ]);
  });

  testWidgets('the very first Home: no day before, so no turn and no name', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(tester, const HomeView(), overrides: _overrides);
    expect(_widget(tester).from, isNull);
    expect(app.prefs.getString(_seenKey), '2026-10-26');
    expect(_name, findsNothing);
    expect(tester.takeAnnouncements(), isEmpty);
  });

  testWidgets('a pinned mark has no daily turn and no name', (tester) async {
    final app = await LibraryTestApp.create(tester);
    final pin = MarkGenerator.build('g-1kq');
    await app.prefs.setString(_seenKey, '2026-10-25');
    await app.prefs.setString(
      SharedPreferenceConstants.identityPinnedMark,
      pin.encode(),
    );
    await app.pump(tester, const HomeView(), overrides: _overrides);
    expect(_widget(tester).mark.seed, pin.seed);
    expect(_widget(tester).from, isNull);
    expect(_name, findsNothing);
    expect(tester.takeAnnouncements(), isEmpty);
    // Today counts as seen: unpinning later today just draws today's in.
    expect(app.prefs.getString(_seenKey), '2026-10-26');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    await container.read(pinnedMarkProvider.notifier).unpin();
    await tester.pump();
    expect(_widget(tester).mark.seed, _markOf(_day2).seed);
    expect(_widget(tester).from, isNull);
    expect(_state(tester).isArriving, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(_name, findsNothing);
  });

  testWidgets('a pin kept past midnight, unpinned the next day: no turn', (
    tester,
  ) async {
    now = _day1;
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(
      SharedPreferenceConstants.identityPinnedMark,
      MarkGenerator.build('g-1kq').encode(),
    );
    await app.pump(tester, const HomeView(), overrides: _overrides);
    expect(app.prefs.getString(_seenKey), '2026-10-25');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    now = _day2;
    container.read(identityDayProvider.notifier).refresh();
    await tester.pump();
    await container.read(pinnedMarkProvider.notifier).unpin();
    await tester.pump();
    expect(_widget(tester).from, isNull);
    expect(_state(tester).isArriving, isFalse);
  });

  testWidgets('the day turns while Home is open: the mark turns then', (
    tester,
  ) async {
    now = _day1;
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-25');
    await app.pump(tester, const HomeView(), overrides: _overrides);
    expect(_widget(tester).from, isNull);
    expect(_name, findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    now = DateTime(2026, 10, 26, 0, 0, 30);
    container.read(identityDayProvider.notifier).refresh();
    await tester.pump();
    await tester.pump();
    expect(_widget(tester).mark.seed, _markOf(_day2).seed);
    expect(_state(tester).arrivingFrom?.seed, _markOf(_day1).seed);
    expect(_state(tester).isArriving, isTrue);
    expect(app.prefs.getString(_seenKey), '2026-10-26');

    await tester.pump(const Duration(milliseconds: 2500));
    expect(_state(tester).isArriving, isFalse);
    expect(find.text(_nameOf(_day2)), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(_name, findsNothing);
  });

  testWidgets('reduced motion: a quiet crossfade and the name', (tester) async {
    now = _day1;
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-25');
    await app.pump(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: const HomeView(),
        ),
      ),
      overrides: _overrides,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    now = _day2;
    container.read(identityDayProvider.notifier).refresh();
    await tester.pump();
    await tester.pump();
    expect(_state(tester).isStill, isTrue);
    expect(_state(tester).isRunning, isFalse);
    expect(_state(tester).isArriving, isTrue);
    await tester.pump(MarkMoments.crossfade ~/ 2);
    expect(_state(tester).arrival, closeTo(0.5, 0.1));
    await tester.pump(MarkMoments.crossfade);
    expect(_state(tester).isArriving, isFalse);
    expect(find.text(_nameOf(_day2)), findsOneWidget);
    expect(tester.takeAnnouncements().map((a) => a.message), [
      "Today's mark: ${_nameOf(_day2)}",
    ]);
    // A tap has no breath to send.
    await tester.tap(find.byKey(const ValueKey('home_mark')));
    await tester.pump();
    expect(_state(tester).isBreathing, isFalse);
    await tester.pump(const Duration(seconds: 6));
    expect(_name, findsNothing);
  });

  /// Home open on day 1, then the day turns: the turn has just begun.
  Future<LibraryTestApp> turnTheDay(
    WidgetTester tester, {
    double textScale = 1,
  }) async {
    now = _day1;
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-25');
    await app.pump(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: const HomeView(),
        ),
      ),
      overrides: _overrides,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeView)),
    );
    now = _day2;
    container.read(identityDayProvider.notifier).refresh();
    await tester.pump();
    await tester.pump();
    return app;
  }

  testWidgets('the turn and its name hold while Home is covered', (
    tester,
  ) async {
    await turnTheDay(tester);
    await tester.pump(const Duration(milliseconds: 200));
    // Not yet showing, so not yet announced.
    expect(_nameOpacity(tester), 0);
    expect(tester.takeAnnouncements(), isEmpty);

    final navigator = Navigator.of(tester.element(find.byType(HomeView)));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('X'))),
    );
    // Home shows (and its mark moves) until the page has slid over it.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_state(tester).seconds + MarkMoments.morphLead, lessThan(1));
    final held = _state(tester).seconds;
    await tester.pump(const Duration(seconds: 10));
    // Covered: the turn, the name and the announcement wait.
    expect(_state(tester).seconds, held);
    expect(_state(tester).isArriving, isTrue);
    expect(_name, findsOneWidget);
    expect(tester.takeAnnouncements(), isEmpty);

    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_name, findsOneWidget);
    expect(_nameOpacity(tester), 1);
    expect(tester.takeAnnouncements().map((a) => a.message), [
      "Today's mark: ${_nameOf(_day2)}",
    ]);
    await tester.pump(const Duration(seconds: 5));
    expect(_name, findsNothing);
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('the name never covers what follows, text ×$scale', (
      tester,
    ) async {
      await turnTheDay(tester, textScale: scale);
      await tester.pump(const Duration(milliseconds: 2500));
      expect(_nameOpacity(tester), 1);
      final name = tester.getRect(_name);
      final mark = tester.getRect(find.byKey(const ValueKey('home_mark')));
      // Under the mark, inside Home's top block: above the update notice
      // that follows it, and so above the first section.
      expect(name.top, greaterThanOrEqualTo(mark.bottom));
      expect(
        name.bottom,
        lessThanOrEqualTo(
          tester.getTopLeft(find.byType(UpdateNotice, skipOffstage: false)).dy,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
    });
  }

  testWidgets(
    'the name keeps its line, so nothing moves as it comes and goes',
    (tester) async {
      await turnTheDay(tester);
      final with_ = tester
          .getTopLeft(find.byType(UpdateNotice, skipOffstage: false))
          .dy;
      await tester.pump(const Duration(seconds: 7));
      expect(_name, findsNothing);
      expect(
        tester.getTopLeft(find.byType(UpdateNotice, skipOffstage: false)).dy,
        with_,
      );
    },
  );

  testWidgets('a long-press opens the mark sheet, without a breath', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-26');
    await app.pump(tester, const HomeView(), overrides: _overrides);
    await tester.longPress(find.byKey(const ValueKey('home_mark')));
    await tester.pump();
    expect(_state(tester).isBreathing, isFalse);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('home_mark_pin')), findsOneWidget);
    expect(_state(tester).isBreathing, isFalse);
  });

  testWidgets('a tap sends one breath through the mark; taps do not stack', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(_seenKey, '2026-10-26');
    await app.pump(tester, const HomeView(), overrides: _overrides);
    expect(_state(tester).isBreathing, isFalse);

    await tester.tap(find.byKey(const ValueKey('home_mark')));
    await tester.pump();
    expect(_state(tester).isBreathing, isTrue);

    // Tapped again mid-breath: the same breath carries on and ends on time.
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('home_mark')));
    await tester.pump();
    expect(_state(tester).isBreathing, isTrue);
    await tester.pump(const Duration(milliseconds: 3600));
    expect(_state(tester).isBreathing, isFalse);
    // A tap is not a long-press: no sheet.
    expect(find.byKey(const ValueKey('home_mark_pin')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home_mark')));
    await tester.pump();
    expect(_state(tester).isBreathing, isTrue);
    await tester.pump(const Duration(seconds: 6));
  });
}
