import 'dart:math' as math;
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

  group('the parts move, the mark does not', () {
    // One of each family, and the house mark (a roof line over a pebble).
    final marks = [
      MarkGenerator.build('g-1kq'),
      MarkGenerator.build('m-2026-10-26'),
      MarkGenerator.build('m-7'),
      MarkGenerator.build('a-1q'),
    ];
    final colors = MarkColors.of(IdentityPalettes.byId('tide'));
    const px = 160, margin = 24, side = px + 2 * margin;

    /// [mark] at [t] with [motion], on a clear ground with a margin all
    /// round, as RGBA bytes.
    Future<Uint8List> render(
      WidgetTester tester,
      MarkSpec mark,
      double t,
      MarkMotion motion,
    ) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..translate(margin.toDouble(), margin.toDouble())
        ..scale(px.toDouble());
      if (mark is AtmosMark) {
        canvas.clipPath(
          Path()..addOval(
            Rect.fromCircle(center: const Offset(0.5, 0.5), radius: 0.5),
          ),
        );
      }
      MarkRenderer(
        canvas,
        colors,
        texel: 1 / px,
      ).draw(mark, t, tile: false, motion: motion);
      final image = recorder.endRecording().toImageSync(side, side);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawStraightRgba),
      );
      image.dispose();
      return bytes!.buffer.asUint8List();
    }

    /// How many pixels differ between two renders, in rows [y0, y1).
    int differing(Uint8List a, Uint8List b, [int y0 = 0, int y1 = side]) {
      var n = 0;
      for (var i = y0 * side * 4; i < y1 * side * 4; i += 4) {
        if ((a[i + 3] - b[i + 3]).abs() > 24 ||
            (a[i] - b[i]).abs() > 24 ||
            (a[i + 1] - b[i + 1]).abs() > 24 ||
            (a[i + 2] - b[i + 2]).abs() > 24) {
          n++;
        }
      }
      return n;
    }

    /// Whether anything is drawn outside the tile's square.
    bool spills(Uint8List a) {
      for (var y = 0; y < side; y++) {
        for (var x = 0; x < side; x++) {
          final inside =
              x >= margin &&
              x < side - margin &&
              y >= margin &&
              y < side - margin;
          if (!inside && a[(y * side + x) * 4 + 3] > 8) return true;
        }
      }
      return false;
    }

    const idle = MarkMotion(life: 1);
    const top = MarkMotion(life: 1, deep: 1, follow: 1, run: 0.5);

    testWidgets('without motion it is the page\'s own drawing', (tester) async {
      for (final mark in marks) {
        final plain = await render(tester, mark, 23, MarkMotion.none);
        // Asking for no motion in so many words changes nothing.
        final zero = await render(tester, mark, 23, const MarkMotion());
        expect(differing(plain, zero), 0, reason: mark.seed);
      }
    });

    testWidgets('at rest every mark keeps moving, a little', (tester) async {
      for (final mark in marks) {
        final a = await render(tester, mark, 21, idle);
        final b = await render(tester, mark, 24, idle);
        final still = await render(tester, mark, 21, MarkMotion.none);
        // It moves from one moment to the next, and away from the page's
        // own frame...
        expect(differing(a, b), greaterThan(0), reason: mark.seed);
        expect(differing(a, still), greaterThan(0), reason: mark.seed);
        // ...but only at its edges: most of the picture is as it was.
        expect(
          differing(a, still),
          lessThan(side * side * 0.12),
          reason: mark.seed,
        );
      }
    });

    testWidgets('a deep breath moves its parts and never leaves the tile', (
      tester,
    ) async {
      for (final mark in marks) {
        final rest = await render(tester, mark, 23, idle);
        final deep = await render(tester, mark, 23, top);
        expect(differing(rest, deep), greaterThan(40), reason: mark.seed);
        expect(spills(rest), isFalse, reason: mark.seed);
        expect(spills(deep), isFalse, reason: mark.seed);
      }
    });

    testWidgets('the line and the pebble take a breath apart', (tester) async {
      // The house mark: the roof is in the upper half, the pebble below.
      final mark = marks[1];
      const half = side ~/ 2 + 8;
      final rest = await render(tester, mark, 23, MarkMotion.none);
      // The body alone: the pebble swells and the roof stays as it was.
      final body = await render(tester, mark, 23, const MarkMotion(deep: 1));
      expect(differing(rest, body, 0, half - 16), 0);
      expect(differing(rest, body, half, side), greaterThan(40));
      // The part that follows alone: the roof's wave rises, and the pebble
      // stays.
      final line = await render(tester, mark, 23, const MarkMotion(follow: 1));
      expect(differing(rest, line, 0, half - 16), greaterThan(40));
      expect(differing(rest, line, half, side), 0);
    });

    testWidgets('a wave travels along a line; it is not one bend held', (
      tester,
    ) async {
      final mark = marks[0];
      const m = MarkMotion(life: 1, follow: 1);
      final a = await render(tester, mark, 23, m);
      final b = await render(tester, mark, 25, m);
      // A quarter of the wave's 8 s later the line is somewhere else.
      expect(differing(a, b), greaterThan(40));
      // And a breath that has run its whole wavelength is back in step.
      final c = await render(
        tester,
        mark,
        23,
        const MarkMotion(life: 1, follow: 1, run: 1),
      );
      expect(differing(a, c), lessThan(4));
    });

    testWidgets('the idle motion waits until the mark has drawn itself in', (
      tester,
    ) async {
      final mark = marks[1];
      final drawing = await render(tester, mark, 1.2, idle);
      final plain = await render(tester, mark, 1.2, MarkMotion.none);
      expect(differing(drawing, plain), 0);
    });
  });

  group('MarkMoments', () {
    test('a deep breath swells once and settles back to rest', () {
      expect(MarkMoments.swellAt(0), 0);
      expect(MarkMoments.swellAt(MarkMoments.breathSeconds), 0);
      expect(MarkMoments.swellAt(-1), 0);
      // The body's own breath ends a part's lag before the whole does.
      expect(MarkMoments.swellAt(MarkMoments.partSeconds), 0);
      final top = MarkMoments.partSeconds * 0.4;
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

    test('the parts that follow take the same breath a moment later', () {
      const lag = MarkMoments.partLag;
      expect(lag, greaterThan(0.3));
      for (var s = 0.0; s <= MarkMoments.breathSeconds; s += 0.1) {
        expect(
          MarkMoments.swellAt(s + lag, lag: lag),
          closeTo(MarkMoments.swellAt(s), 1e-9),
        );
      }
      // Still out when the body has settled, and at rest when the breath
      // ends.
      expect(
        MarkMoments.swellAt(MarkMoments.partSeconds, lag: lag),
        greaterThan(0),
      );
      expect(MarkMoments.swellAt(MarkMoments.breathSeconds, lag: lag), 0);
      // The wave runs one whole wavelength over the breath.
      expect(MarkMoments.runAt(0), 0);
      expect(MarkMoments.runAt(MarkMoments.breathSeconds), 1);
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

    testWidgets('the parts that follow trail the body, and settle with it', (
      tester,
    ) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      // Breathing in: the followers are behind.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_state(tester).cycle, closeTo(0.5, 0.05));
      expect(_state(tester).follow, lessThan(_state(tester).cycle - 0.1));
      expect(_state(tester).follow, greaterThan(0));
      // Breathing out: they are still further in.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_state(tester).cycle, closeTo(0.5, 0.05));
      expect(_state(tester).follow, greaterThan(_state(tester).cycle + 0.1));
      // Paused, both come to rest together and the mark stops.
      await tester.pumpWidget(breathing(paused: true));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_state(tester).cycle, 0);
      expect(_state(tester).follow, 0);
      expect(_state(tester).isRunning, isFalse);
    });

    testWidgets('the resting mark (Home) has no continuous breath', (
      tester,
    ) async {
      await tester.pumpWidget(breathing(seconds: null));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(_state(tester).cycle, 0);
    });

    testWidgets('paused, it settles to rest, then holds; resumes from rest', (
      tester,
    ) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      // Past drawing in, and at the top of a breath: 4 s breaths, 10 s on.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 4));
      final top = _state(tester).cycle;
      expect(top, closeTo(1, 0.1));

      await tester.pumpWidget(breathing(paused: true));
      await tester.pump(const Duration(milliseconds: 16));
      // Right after pausing it has not jumped, and has not stopped.
      expect(_state(tester).cycle, closeTo(top, 0.1));
      expect(_state(tester).isRunning, isTrue);
      await tester.pump(const Duration(milliseconds: 600));
      final settling = _state(tester).cycle;
      expect(settling, lessThan(top - 0.2));
      expect(settling, greaterThan(0));
      await tester.pump(const Duration(seconds: 2));
      // At rest, the clock stopped, nothing moves.
      expect(_state(tester).cycle, 0);
      expect(_state(tester).isRunning, isFalse);
      expect(await _moves(tester, const Duration(seconds: 3)), isFalse);
      expect(_state(tester).cycle, 0);

      await tester.pumpWidget(breathing());
      expect(_state(tester).isRunning, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // A fresh breath from rest: it starts near 0, not where it left off.
      expect(_state(tester).cycle, lessThan(0.1));
      await tester.pump(const Duration(seconds: 1));
      expect(_state(tester).cycle, greaterThan(0.3));
    });

    testWidgets('pausing, resuming mid-settle and pausing again never jumps', (
      tester,
    ) async {
      await tester.pumpWidget(breathing());
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 4));
      expect(_state(tester).cycle, closeTo(1, 0.1));

      // The breath is written about every other frame, so a step is judged
      // against the time since the last one: no faster than the settle's
      // steepest (about 1 a second) or a breath's (about 0.8 a second).
      var last = _state(tester).cycle;
      var since = 0.0;
      var worst = 0.0;
      Future<void> frames(int n) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          since += 0.016;
          final now = _state(tester).cycle;
          if (now == last) continue;
          worst = math.max(worst, (now - last).abs() / since);
          last = now;
          since = 0;
        }
      }

      // Pause at the top, resume part-way down the settle, pause again later.
      await tester.pumpWidget(breathing(paused: true));
      await frames(30);
      expect(_state(tester).cycle, lessThan(1));
      await tester.pumpWidget(breathing());
      await frames(20);
      await tester.pumpWidget(breathing(paused: true));
      await frames(150);
      expect(
        worst,
        lessThan(1.3),
        reason: 'no jump: at most the steepest slope',
      );
      expect(_state(tester).cycle, 0);
      expect(_state(tester).isRunning, isFalse);
    });

    testWidgets('paused while drawing in, it finishes drawing in first', (
      tester,
    ) async {
      await tester.pumpWidget(breathing(paused: true));
      await tester.pump();
      expect(_state(tester).isRunning, isTrue);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_state(tester).isRunning, isFalse);
      expect(_state(tester).cycle, 0);
    });

    testWidgets('the breath is written at about 30 a second, not per frame', (
      tester,
    ) async {
      await tester.pumpWidget(breathing(seconds: 10));
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      var updates = 0;
      void count() => updates++;
      _state(tester).cycleListenable.addListener(count);
      // Two seconds of a 120 Hz display.
      for (var i = 0; i < 240; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      _state(tester).cycleListenable.removeListener(count);
      expect(updates, inInclusiveRange(40, 70));
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
