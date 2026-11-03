import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// Live art ticks only while it can be seen (Burooj, 2026-11-02): a cover
/// scrolled out of the window, an app in the background, or reduce motion
/// runs no ticker at all. A running ticker is a transient frame callback.
void main() {
  setUp(() => CuratedArt.instance.useJson('{"items": {}}'));

  Widget row({bool reduceMotion = false}) => MaterialApp(
    theme: meditejoTheme(Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(
          body: SizedBox(
            height: 150,
            child: ListView(
              key: const ValueKey('row'),
              scrollDirection: Axis.horizontal,
              // Everything is built, so off-screen covers exist and could tick.
              cacheExtent: 5000,
              children: [
                for (var i = 0; i < 12; i++)
                  SizedBox(
                    width: 150,
                    child: ArtCover(
                      subject: ArtSubject.practice(
                        'p$i',
                        ground: 'paper',
                        figure: 'breath',
                      ),
                      live: true,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  int ticking() => SchedulerBinding.instance.transientCallbackCount;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('only the covers in the window tick', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(row());
    await settle(tester);
    // 400 wide, 150 each: three covers show (the third in part).
    expect(ticking(), 3);

    await tester.drag(find.byKey(const ValueKey('row')), const Offset(-900, 0));
    await settle(tester);
    // Still only what shows, not the twelve that are built.
    expect(ticking(), inInclusiveRange(1, 4));
  });

  testWidgets('nothing ticks while the app is in the background', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(row());
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
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(row(reduceMotion: true));
    await settle(tester);
    expect(ticking(), 0);
  });
}
