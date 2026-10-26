import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_spec.dart';
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
}
