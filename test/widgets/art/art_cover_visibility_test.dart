import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// Live art ticks only while it can be seen (Burooj, 2026-11-02): a cover
/// scrolled out of its list, on a hidden tab, in an app in the background,
/// or under reduce motion runs no ticker. A running ticker is a transient
/// frame callback, so the tests count those.
void main() {
  setUp(() => CuratedArt.instance.useJson('{"items": {}}'));

  Widget cover(int i) => SizedBox(
    width: 150,
    child: ArtCover(
      subject: ArtSubject.practice('p$i', ground: 'paper', figure: 'breath'),
      live: true,
    ),
  );

  Widget row({double width = 400}) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 150,
      child: ListView(
        key: const ValueKey('row'),
        scrollDirection: Axis.horizontal,
        // Everything is built, so off-screen covers exist and could tick.
        scrollCacheExtent: const ScrollCacheExtent.pixels(5000),
        children: [for (var i = 0; i < 12; i++) cover(i)],
      ),
    ),
  );

  Widget app(Widget body, {bool reduceMotion = false}) => MaterialApp(
    theme: meditejoTheme(Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(body: body),
      ),
    ),
  );

  int ticking() => SchedulerBinding.instance.transientCallbackCount;

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('row')),
          matching: find.byType(Scrollable),
        ),
      )
      .position;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('only the covers in view tick, and they come back', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(row()));
    await settle(tester);
    // 400 wide, 150 each: three covers show (the third in part).
    expect(ticking(), 3);

    // Scroll by exactly six covers: covers 6, 7 and 8 show.
    // Jumped, not dragged: a fling would add a ticker of its own.
    position(tester).jumpTo(900);
    // Covers measure themselves after the new layout.
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(ticking(), 3);

    // And back: the first three tick again.
    position(tester).jumpTo(0);
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(ticking(), 3);
  });

  testWidgets('a list narrower than the screen bounds what shows', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(row(width: 200)));
    await settle(tester);
    // 200 wide: two covers show, though more are on the screen's width.
    expect(ticking(), 2);
  });

  testWidgets('a hidden tab ticks nothing', (tester) async {
    phone(tester);
    final tab = ValueNotifier(0);
    await tester.pumpWidget(
      app(
        ValueListenableBuilder(
          valueListenable: tab,
          builder: (_, i, _) =>
              IndexedStack(index: i, children: [row(), const SizedBox()]),
        ),
      ),
    );
    await settle(tester);
    expect(ticking(), 3);
    tab.value = 1;
    await settle(tester);
    expect(ticking(), 0);
    tab.value = 0;
    await settle(tester);
    expect(ticking(), 3);
  });

  testWidgets('nothing ticks while the app is in the background', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(row()));
    await settle(tester);
    expect(ticking(), 3);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    expect(ticking(), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(ticking(), 3);
  });

  testWidgets('reduce motion draws still frames', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(row(), reduceMotion: true));
    await settle(tester);
    expect(ticking(), 0);
  });

  testWidgets('a cover that slides into view without a scroll starts', (
    tester,
  ) async {
    // As a route sliding in moves its page: no scroll position reports it,
    // so the half-second look catches it.
    phone(tester);
    final left = ValueNotifier(1000.0);
    // One widget instance: moving it re-lays it out without rebuilding it,
    // so only the half-second look can notice.
    final moving = SizedBox(height: 150, child: cover(0));
    await tester.pumpWidget(
      app(
        ValueListenableBuilder(
          valueListenable: left,
          builder: (_, x, _) => Stack(
            children: [Positioned(left: x, top: 0, child: moving)],
          ),
        ),
      ),
    );
    await settle(tester);
    expect(ticking(), 0);

    left.value = 0;
    await tester.pump();
    expect(ticking(), 0);
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(ticking(), 1);
  });

  testWidgets('an unfocused app (split screen) keeps moving', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(row()));
    await settle(tester);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await settle(tester);
    expect(ticking(), 3);
  });
}
