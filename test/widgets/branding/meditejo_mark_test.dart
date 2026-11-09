import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/branding/mark_painter.dart';
import 'package:medito/widgets/branding/mark_textures.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

final _mark = MarkGenerator.build('g-1kq');

MeditejoMarkState _state(WidgetTester tester) => tester
    .state<MeditejoMarkState>(find.byType(MeditejoMark, skipOffstage: false));

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  theme: meditejoTheme(Brightness.light),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  ),
);

Widget _markOf(MarkSpec mark, {bool animate = true}) => Center(
  child: MeditejoMark(mark: mark, animate: animate),
);

/// Pumps [duration] and says whether the mark moved meanwhile.
Future<bool> _moves(WidgetTester tester, [Duration? duration]) async {
  final before = _state(tester).seconds;
  await tester.pump(duration ?? const Duration(seconds: 2));
  return _state(tester).seconds != before;
}

void main() {
  testWidgets('draws in, then keeps breathing while it can be seen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    expect(_state(tester).isRunning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(_state(tester).seconds, closeTo(2, 0.05));
    // Long after drawing in, it still moves: the breath has no end.
    await tester.pump(const Duration(seconds: 30));
    expect(await _moves(tester), isTrue);
  });

  testWidgets('reduced motion shows the settled frame', (tester) async {
    await tester.pumpWidget(_app(_markOf(_mark), disableAnimations: true));
    expect(_state(tester).isRunning, isFalse);
    expect(_state(tester).isStill, isTrue);
    expect(await _moves(tester), isFalse);
    expect(find.byKey(const ValueKey('meditejo_mark')), findsOneWidget);
  });

  testWidgets('turning reduced motion on stops it at its settled frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(_state(tester).isStill, isFalse);
    await tester.pumpWidget(_app(_markOf(_mark), disableAnimations: true));
    expect(_state(tester).isRunning, isFalse);
    expect(_state(tester).isStill, isTrue);
  });

  testWidgets('still: true never moves', (tester) async {
    await tester.pumpWidget(
      _app(Center(child: MeditejoMark(mark: _mark, still: true))),
    );
    expect(_state(tester).isRunning, isFalse);
    expect(_state(tester).isStill, isTrue);
    expect(await _moves(tester), isFalse);
  });

  testWidgets('stops on a hidden tab and resumes where it was', (tester) async {
    Widget tabs(int index) => _app(
      IndexedStack(
        index: index,
        children: [
          _markOf(_mark),
          const Center(child: Text('Explore')),
        ],
      ),
    );
    await tester.pumpWidget(tabs(0));
    expect(_state(tester).isRunning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.pumpWidget(tabs(1));
    expect(_state(tester).isRunning, isFalse);
    final held = _state(tester).seconds;
    expect(await _moves(tester), isFalse);

    await tester.pumpWidget(tabs(0));
    expect(_state(tester).isRunning, isTrue);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_state(tester).seconds, closeTo(held + 1, 0.05));
  });

  testWidgets('stops under a route pushed over it', (tester) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('X'))),
    );
    await tester.pumpAndSettle();
    expect(_state(tester).isRunning, isFalse);
    expect(await _moves(tester), isFalse);

    navigator.pop();
    // Not pumpAndSettle: the mark moving again never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_state(tester).isRunning, isTrue);
  });

  testWidgets('stops while the app is in the background', (tester) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    expect(_state(tester).isRunning, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_state(tester).isRunning, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_state(tester).isRunning, isTrue);
  });

  testWidgets('animate: false holds it where it is', (tester) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(_app(_markOf(_mark, animate: false)));
    expect(_state(tester).isRunning, isFalse);
    expect(await _moves(tester), isFalse);
  });

  testWidgets('a new mark draws itself in from the start', (tester) async {
    await tester.pumpWidget(_app(_markOf(_mark)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(_state(tester).seconds, greaterThan(5));
    await tester.pumpWidget(_app(_markOf(MarkGenerator.build('m-1lq'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_state(tester).seconds, closeTo(0.5, 0.05));
  });

  testWidgets('every family paints, moving and still', (tester) async {
    for (final seed in ['g-1cq', 'm-1nq', 'a-1q']) {
      await tester.pumpWidget(_app(_markOf(MarkGenerator.build(seed))));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(
        _app(_markOf(MarkGenerator.build(seed)), disableAnimations: true),
      );
      expect(tester.takeException(), isNull);
    }
  });

  group('a deep breath', () {
    testWidgets('a tap sends one breath through it; taps do not stack', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_markOf(_mark)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(_state(tester).breathe(), isTrue);
      expect(_state(tester).isBreathing, isTrue);
      await tester.pump(const Duration(seconds: 2));
      // Mid-breath: another tap is ignored, not stacked or restarted.
      expect(_state(tester).breathe(), isFalse);
      await tester.pump(const Duration(milliseconds: 3600));
      expect(_state(tester).isBreathing, isFalse);
      // It rests again, and can breathe again.
      expect(_state(tester).breathe(), isTrue);
      await tester.pump(const Duration(seconds: 6));
      expect(_state(tester).isBreathing, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion has no breath', (tester) async {
      await tester.pumpWidget(_app(_markOf(_mark), disableAnimations: true));
      expect(_state(tester).breathe(), isFalse);
      expect(_state(tester).isBreathing, isFalse);
    });

    testWidgets('no breath while it cannot be seen', (tester) async {
      await tester.pumpWidget(_app(_markOf(_mark, animate: false)));
      expect(_state(tester).breathe(), isFalse);
    });
  });

  group('arriving from another mark', () {
    final yesterday = MarkGenerator.build('a-1q');

    Widget tabs(int index, {VoidCallback? onSeen, MarkSpec? from}) => _app(
      IndexedStack(
        index: index,
        children: [
          Center(
            child: MeditejoMark(
              mark: _mark,
              from: from ?? yesterday,
              onSeen: onSeen,
            ),
          ),
          const Center(child: Text('Explore')),
        ],
      ),
    );

    testWidgets('waits until it is seen, then turns once', (tester) async {
      var seen = 0;
      await tester.pumpWidget(tabs(1, onSeen: () => seen++));
      await tester.pump(const Duration(seconds: 3));
      // Unseen: the old mark holds, the turn hasn't begun.
      expect(seen, 0);
      expect(_state(tester).isArriving, isTrue);
      expect(_state(tester).arrival, 0);
      expect(_state(tester).seconds, -MarkMoments.morphLead);

      await tester.pumpWidget(tabs(0, onSeen: () => seen++));
      await tester.pump();
      expect(seen, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).isArriving, isTrue);
      expect(
        _state(tester).arrival,
        closeTo(1 / MarkMoments.undrawSeconds, 0.02),
      );
      // No breath mid-turn.
      expect(_state(tester).breathe(), isFalse);
      await tester.pump(const Duration(milliseconds: 1300));
      expect(_state(tester).isArriving, isFalse);
      // Today's mark has been drawing itself in since the lead.
      expect(
        _state(tester).seconds,
        closeTo(2.3 - MarkMoments.morphLead, 0.05),
      );

      // Hidden and shown again: no second turn, no second call.
      await tester.pumpWidget(tabs(1, onSeen: () => seen++));
      await tester.pumpWidget(tabs(0, onSeen: () => seen++));
      await tester.pump(const Duration(seconds: 1));
      expect(seen, 1);
      expect(_state(tester).isArriving, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('with reduced motion the two settled frames crossfade', (
      tester,
    ) async {
      var seen = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: MeditejoMark(
              mark: _mark,
              from: yesterday,
              onSeen: () => seen++,
            ),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pump();
      expect(seen, 1);
      expect(_state(tester).isStill, isTrue);
      expect(_state(tester).isRunning, isFalse);
      expect(_state(tester).isArriving, isTrue);
      final held = _state(tester).seconds;
      await tester.pump(MarkMoments.crossfade ~/ 2);
      expect(_state(tester).arrival, closeTo(0.5, 0.05));
      // A fade only: nothing moves.
      expect(_state(tester).seconds, held);
      await tester.pump(MarkMoments.crossfade);
      expect(_state(tester).isArriving, isFalse);
    });

    testWidgets('every pair of families turns without error', (tester) async {
      for (final from in ['g-1cq', 'm-1nq', 'a-1q']) {
        for (final to in ['g-1kq', 'm-1lq', 'a-3q']) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(
            _app(
              Center(
                child: MeditejoMark(
                  mark: MarkGenerator.build(to),
                  from: MarkGenerator.build(from),
                ),
              ),
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
          expect(tester.takeException(), isNull);
          expect(_state(tester).isArriving, isFalse);
        }
      }
    });
  });

  testWidgets("a scene's print finish grows with its deep breath", (
    tester,
  ) async {
    // At the top of a breath a scene is larger than its tile. The finish
    // (paper and speckle) must reach the grown edge, not stop at the tile's
    // square and leave bare caps. Rendered with and without the textures:
    // outside the tile's square they differ only where the finish reaches.
    const px = 200, m = 24;
    // Speckle is made on demand, so the finish shows without waiting for
    // paper (whose loading an earlier test may have started).
    final scene = MarkGenerator.build('a-1q');
    final colors = MarkColors.of(IdentityPalettes.byId('tide'));
    Future<Uint8List> render({required bool finish}) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..translate(m.toDouble(), m.toDouble())
        ..scale(px.toDouble());
      MarkRenderer(
        canvas,
        colors,
        textures: finish ? MarkTextures.instance : null,
        texel: 1 / px,
      ).draw(scene, 60, swell: 1);
      final image = recorder.endRecording().toImageSync(px + 2 * m, px + 2 * m);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      );
      return bytes!.buffer.asUint8List();
    }

    final a = await render(finish: true);
    final b = await render(finish: false);
    const w = px + 2 * m;
    double band(int y0, int y1) {
      var sum = 0, n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = w ~/ 2 - 20; x < w ~/ 2 + 20; x++) {
          final i = (y * w + x) * 4;
          for (var k = 0; k < 3; k++) {
            sum += (a[i + k] - b[i + k]).abs();
          }
          n += 3;
        }
      }
      return sum / n;
    }

    // Just above the tile's top edge (inside the grown circle), and just
    // inside it.
    final outside = band(m - 6, m - 2);
    final inside = band(m + 2, m + 6);
    expect(inside, greaterThan(0));
    // Bare caps would differ not at all.
    expect(outside, greaterThan(inside * 0.25));
  });

  group('MarkMoments', () {
    test('a deep breath swells once and settles back to rest', () {
      expect(MarkMoments.swellAt(0), 0);
      expect(MarkMoments.swellAt(MarkMoments.breathSeconds), 0);
      expect(MarkMoments.swellAt(-1), 0);
      final top = MarkMoments.breathSeconds * 0.4;
      expect(MarkMoments.swellAt(top), closeTo(1, 1e-9));
      // Rises, then falls: one breath, no bounce.
      var last = 0.0;
      for (var s = 0.1; s < top; s += 0.1) {
        final v = MarkMoments.swellAt(s);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
      last = 1;
      for (var s = top + 0.1; s < MarkMoments.breathSeconds; s += 0.1) {
        final v = MarkMoments.swellAt(s);
        expect(v, lessThanOrEqualTo(last));
        last = v;
      }
    });

    test("yesterday's mark un-draws back to its first moment", () {
      final m = MarkGenerator.build('g-1kq');
      expect(MarkMoments.undrawTimeAt(m, 0), MarkMoments.drawnBy(m));
      expect(MarkMoments.undrawTimeAt(m, MarkMoments.undrawSeconds), 0);
      expect(MarkMoments.undrawOpacityAt(0), 1);
      expect(MarkMoments.undrawOpacityAt(MarkMoments.undrawSeconds), 0);
    });

    test("today's name fades in, rests, and fades away", () {
      expect(MarkMoments.nameOpacityAt(0), 0);
      expect(MarkMoments.nameOpacityAt(3), 1);
      expect(MarkMoments.nameOpacityAt(MarkMoments.nameSeconds), 0);
    });
  });

  group('a continuous breath (the player)', () {
    Widget breathing({
      double? seconds = 4,
      bool paused = false,
      bool disableAnimations = false,
    }) => _app(
      Center(
        child: MeditejoMark(
          mark: _mark,
          breathSeconds: seconds,
          paused: paused,
        ),
      ),
      disableAnimations: disableAnimations,
    );

    testWidgets('swells and settles once per breath, over and over', (
      tester,
    ) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      expect(_state(tester).cycle, closeTo(0, 0.01));
      await tester.pump(const Duration(seconds: 2));
      // Half a 4 s breath: the top of the in-breath.
      expect(_state(tester).cycle, closeTo(1, 0.05));
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).cycle, closeTo(0, 0.05));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 4));
      }
      expect(_state(tester).cycle, closeTo(0, 0.05));
    });

    testWidgets('the resting mark (Home) has no continuous breath', (
      tester,
    ) async {
      await tester.pumpWidget(breathing(seconds: null));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).cycle, 0);
    });

    testWidgets('paused, it finishes drawing in, then holds; resumes there', (
      tester,
    ) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(breathing(paused: true));
      // Still drawing itself in: the clock runs on until it has.
      expect(_state(tester).isRunning, isTrue);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_state(tester).isRunning, isFalse);
      final held = _state(tester).cycle;
      expect(await _moves(tester, const Duration(seconds: 3)), isFalse);
      expect(_state(tester).cycle, held);

      await tester.pumpWidget(breathing());
      expect(_state(tester).isRunning, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // It carries on from where it stopped, not from the start.
      expect((_state(tester).cycle - held).abs(), lessThan(0.5));
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).cycle, isNot(closeTo(held, 0.01)));
    });

    testWidgets('a new rate carries on from the same point', (tester) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final before = _state(tester).cycle;
      await tester.pumpWidget(breathing(seconds: 2));
      await tester.pump(const Duration(milliseconds: 16));
      expect((_state(tester).cycle - before).abs(), lessThan(0.2));
    });

    testWidgets('reduced motion is a still mark', (tester) async {
      await tester.pumpWidget(breathing(disableAnimations: true));
      expect(_state(tester).isRunning, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).cycle, 0);
    });

    testWidgets('holds under a route pushed over it', (tester) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('X')),
        ),
      );
      await tester.pumpAndSettle();
      expect(_state(tester).isRunning, isFalse);
    });
  });
}
