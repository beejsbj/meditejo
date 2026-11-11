import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';
import 'package:medito/widgets/branding/mark_painter.dart';

import '../../helpers/library_app.dart';

// Home's mark is large and alive in its parts (2026-11-10): up to about the
// top half of the screen, giving way to what is below so the first row of
// tiles stays on screen; idle while it is seen, one breath through its
// parts on a tap.

/// The owner's phone (Galaxy S23+), and the bottom navigation bar's height.
const _phone = Size(411, 890);
const _navBar = 80.0;

ContinueItem _item(String id, String title, String course, int n, int of) =>
    ContinueItem(
      trackId: id,
      path: '/tracks/$id',
      title: title,
      group: LibraryGroup.practice,
      lastPlayed: DateTime(2026, 10, 19),
      courseId: 'course-$id',
      courseTitle: course,
      resume: const ResumePoint(positionMs: 1800000, durationMs: 5340000),
      sessionNumber: n,
      sessionTotal: of,
    );

/// The three cards on the owner's Home when he asked for this.
final _three = [
  _item(
    'a',
    'Chanting / Guided Meditation',
    'Sunday International Sangha: Immersion in the Dhamma',
    8,
    14,
  ),
  _item(
    'b',
    'About Metta Practice',
    'The Loving Kindness (Metta) Retreat',
    1,
    10,
  ),
  _item('c', 'Orienting to This Jhana Retreat', 'Practising the Jhānas', 1, 32),
];

/// How many of a test's Continue cards show.
class _Cards extends Notifier<int> {
  @override
  int build() => 3;

  void show(int count) => state = count;
}

final _cards = NotifierProvider<_Cards, int>(_Cards.new);

final _mark = find.byKey(const ValueKey('home_mark'), skipOffstage: false);
final _timer = find.byKey(const ValueKey('shortcut_timer'));

MeditejoMarkState _state(WidgetTester tester) => tester
    .state<MeditejoMarkState>(find.byType(MeditejoMark, skipOffstage: false));

MarkPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('meditejo_mark'), skipOffstage: false),
            )
            .painter!
        as MarkPainter;

/// Home as the app shows it: above a bottom bar, on a [size] screen.
Future<LibraryTestApp> _pumpHome(
  WidgetTester tester, {
  List<ContinueItem> items = const [],
  Size size = _phone,
  double textScale = 1,
  bool reducedMotion = false,
  Widget Function(Widget home)? wrap,
}) async {
  final app = await LibraryTestApp.create(tester);
  // Past the day's turn: the mark rests.
  final home = Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reducedMotion,
      ),
      child: const Scaffold(
        body: HomeView(),
        bottomNavigationBar: SizedBox(height: _navBar),
      ),
    ),
  );
  await app.pump(
    tester,
    wrap?.call(home) ?? home,
    overrides: [
      continueItemsProvider.overrideWith(
        (ref) async => items.take(ref.watch(_cards)).toList(),
      ),
    ],
  );
  tester.view.physicalSize = size;
  await tester.pump();
  // The mark's block eases to its measured height.
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  return app;
}

void main() {
  // The app's own font: the test font is far wider, and would wrap every
  // card into a height no phone shows.
  setUpAll(() async {
    final sans = FontLoader('Google Sans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      sans.addFont(
        File(
          'assets/fonts/google-sans/GoogleSans-$weight.ttf',
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await sans.load();
  });

  group('the mark has the top of Home', () {
    testWidgets('about half the screen on the S23+ when little is below', (
      tester,
    ) async {
      await _pumpHome(tester);
      final mark = tester.getRect(_mark);
      // A square, nearly as wide as the screen less its gutters.
      expect(mark.width, mark.height);
      expect(mark.width, greaterThan(340));
      expect(mark.width, lessThanOrEqualTo(_phone.width - 40));
      expect(mark.center.dx, moreOrLessEquals(_phone.width / 2));
      // With the air above it and its name's line below, it has 40 to 50%
      // of the screen's height; what follows starts under that.
      final below = tester.getTopLeft(
        find.byKey(const ValueKey('continue_empty')),
      );
      expect(mark.height / _phone.height, inInclusiveRange(0.40, 0.50));
      expect(below.dy / _phone.height, inInclusiveRange(0.44, 0.52));
      expect(tester.getRect(_timer).bottom, lessThan(_phone.height - _navBar));
      // The buttons stay at the top right, over its corner.
      final you = tester.getRect(find.byKey(const ValueKey('home_customize')));
      expect(you.top, lessThan(60));
      expect(you.right, greaterThan(_phone.width - 120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with one Continue card it is still large', (tester) async {
      await _pumpHome(tester, items: [_three.first]);
      expect(tester.getSize(_mark).width, greaterThan(340));
      final tiles = tester.getRect(_timer);
      expect(tiles.bottom, lessThanOrEqualTo(_phone.height - _navBar));
    });

    testWidgets('three Continue cards take room from it, and the first row '
        'of tiles stays on screen', (tester) async {
      await _pumpHome(tester, items: _three);
      final mark = tester.getSize(_mark);
      // Smaller than with nothing below, larger than it used to be (168).
      expect(mark.width, lessThan(300));
      expect(mark.width, greaterThan(220));
      for (final key in ['shortcut_timer', 'shortcut_sounds']) {
        final tile = tester.getRect(find.byKey(ValueKey(key)));
        expect(
          tile.bottom,
          lessThanOrEqualTo(_phone.height - _navBar),
          reason: key,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a small phone at 2× text it keeps a floor and Home '
        'scrolls', (tester) async {
      await _pumpHome(
        tester,
        items: _three,
        size: const Size(360, 640),
        textScale: 2,
      );
      final mark = tester.getSize(_mark);
      expect(mark.width, greaterThan(120));
      expect(mark.width, lessThan(200));
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('when a card goes the mark eases larger; it does not jump', (
      tester,
    ) async {
      await _pumpHome(tester, items: _three);
      final before = tester.getSize(_mark).width;
      // Two of the three are gone (removed from Continue, say).
      ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      ).read(_cards.notifier).show(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final during = tester.getSize(_mark).width;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      final after = tester.getSize(_mark).width;
      expect(find.byKey(const ValueKey('continue_c')), findsNothing);
      expect(after, greaterThan(before + 60));
      expect(during, greaterThan(before));
      expect(during, lessThan(after - 20));
      expect(tester.takeException(), isNull);
    });
  });

  group('the mark is alive only while it is seen', () {
    testWidgets('at rest its parts keep moving', (tester) async {
      await _pumpHome(tester);
      await tester.pump(const Duration(seconds: 6));
      expect(_state(tester).isRunning, isTrue);
      final motion = _painter(tester).motionAt(_state(tester).seconds);
      expect(motion.life, 1);
      expect(motion.deep, 0);
      final t = _state(tester).seconds;
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).seconds, greaterThan(t + 1.9));
    });

    testWidgets('reduced motion: a still mark, and a tap only dips its '
        'opacity', (tester) async {
      await _pumpHome(tester, reducedMotion: true);
      expect(_state(tester).isRunning, isFalse);
      expect(_state(tester).isStill, isTrue);
      expect(_painter(tester).motionAt(60).life, 0);
      final t = _state(tester).seconds;
      await tester.pump(const Duration(seconds: 3));
      expect(_state(tester).seconds, t);

      double opacity() => tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('meditejo_mark')),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(opacity(), 1);
      await tester.tap(_mark);
      await tester.pump();
      expect(_state(tester).isBreathing, isFalse);
      expect(_state(tester).isRunning, isFalse);
      expect(_state(tester).isPulsing, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacity(), lessThan(0.8));
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacity(), 1);
      expect(_state(tester).isPulsing, isFalse);
    });

    testWidgets('it stops when Home is offstage, and carries on after', (
      tester,
    ) async {
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      await _pumpHome(
        tester,
        wrap: (home) => ValueListenableBuilder<bool>(
          valueListenable: shown,
          // As the tabs do: the hidden one is kept, offstage.
          builder: (context, visible, _) => IndexedStack(
            index: visible ? 0 : 1,
            children: [home, const SizedBox.expand()],
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(_state(tester).isRunning, isTrue);

      shown.value = false;
      await tester.pump();
      expect(_state(tester).isRunning, isFalse);
      final held = _state(tester).seconds;
      await tester.pump(const Duration(seconds: 5));
      expect(_state(tester).seconds, held);

      shown.value = true;
      await tester.pump();
      expect(_state(tester).isRunning, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).seconds, closeTo(held + 1, 0.1));
    });

    testWidgets('it stops while the app is in the background', (tester) async {
      await _pumpHome(tester);
      expect(_state(tester).isRunning, isTrue);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(_state(tester).isRunning, isFalse);
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(_state(tester).isRunning, isTrue);
    });
  });

  testWidgets('a tap runs one breath through the parts, then it rests', (
    tester,
  ) async {
    await _pumpHome(tester);
    await tester.pump(const Duration(seconds: 6));
    MarkMotion now() => _painter(tester).motionAt(_state(tester).seconds);
    expect(now().deep, 0);
    expect(now().follow, 0);

    await tester.tap(_mark);
    await tester.pump();
    expect(_state(tester).isBreathing, isTrue);
    // The body leads; the parts that follow are behind it on the way in...
    await tester.pump(const Duration(milliseconds: 1200));
    final early = now();
    expect(early.deep, greaterThan(0.3));
    expect(early.follow, lessThan(early.deep - 0.2));
    // ...and still out when the body is settling.
    await tester.pump(const Duration(milliseconds: 2400));
    final late_ = now();
    expect(late_.follow, greaterThan(late_.deep + 0.1));
    expect(late_.run, inExclusiveRange(0, 1));
    // The size of the mark's box never changes: nothing is zoomed.
    final size = tester.getSize(_mark);
    await tester.pump(const Duration(milliseconds: 2000));
    expect(_state(tester).isBreathing, isFalse);
    expect(tester.getSize(_mark), size);
    final rest = now();
    expect(rest.deep, 0);
    expect(rest.follow, 0);
    expect(rest.run, 0);
    // At rest again: idle, and still moving.
    expect(rest.life, 1);
    expect(_state(tester).isRunning, isTrue);
  });
}
