import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/widgets/branding/mark_geometry.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

MeditejoMarkState _mark(WidgetTester tester) => tester.state<MeditejoMarkState>(
  find.byType(MeditejoMark, skipOffstage: false),
);

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

/// Pumps [duration] and says whether the mark moved meanwhile.
Future<bool> _moves(WidgetTester tester, [Duration? duration]) async {
  final before = _mark(tester).phase;
  await tester.pump(duration ?? const Duration(seconds: 2));
  return _mark(tester).phase != before;
}

void main() {
  testWidgets('moves slowly and continuously while it can be seen', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Center(child: MeditejoMark())));
    expect(_mark(tester).isRunning, isTrue);
    expect(await _moves(tester), isTrue);
    // A whole loop is a minute: two seconds is a thirtieth of it.
    expect(_mark(tester).phase, closeTo(2 / 60, 0.01));
  });

  testWidgets('reduced motion shows the still frame', (tester) async {
    await tester.pumpWidget(
      _app(const Center(child: MeditejoMark()), disableAnimations: true),
    );
    expect(_mark(tester).isRunning, isFalse);
    expect(_mark(tester).phase, 0);
    expect(await _moves(tester), isFalse);
    expect(find.byKey(const ValueKey('meditejo_mark')), findsOneWidget);
  });

  testWidgets('turning reduced motion on stops it at its still frame', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const Center(child: MeditejoMark())));
    await tester.pump(const Duration(seconds: 3));
    expect(_mark(tester).phase, greaterThan(0));
    await tester.pumpWidget(
      _app(const Center(child: MeditejoMark()), disableAnimations: true),
    );
    expect(_mark(tester).isRunning, isFalse);
    expect(_mark(tester).phase, 0);
  });

  testWidgets('stops on a hidden tab and resumes when it shows again', (
    tester,
  ) async {
    Widget tabs(int index) => _app(
      IndexedStack(
        index: index,
        children: const [
          Center(child: MeditejoMark()),
          Center(child: Text('Explore')),
        ],
      ),
    );
    await tester.pumpWidget(tabs(0));
    expect(_mark(tester).isRunning, isTrue);

    await tester.pumpWidget(tabs(1));
    expect(_mark(tester).isRunning, isFalse);
    expect(await _moves(tester), isFalse);

    await tester.pumpWidget(tabs(0));
    expect(_mark(tester).isRunning, isTrue);
    expect(await _moves(tester), isTrue);
  });

  testWidgets('stops under a route pushed over it', (tester) async {
    await tester.pumpWidget(_app(const Center(child: MeditejoMark())));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('X'))),
    );
    await tester.pumpAndSettle();
    expect(_mark(tester).isRunning, isFalse);
    expect(await _moves(tester), isFalse);

    navigator.pop();
    // Not pumpAndSettle: the mark moving again never settles.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(_mark(tester).isRunning, isTrue);
  });

  testWidgets('stops while the app is in the background', (tester) async {
    await tester.pumpWidget(_app(const Center(child: MeditejoMark())));
    expect(_mark(tester).isRunning, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(_mark(tester).isRunning, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_mark(tester).isRunning, isTrue);
  });

  testWidgets('animate: false holds it where it is', (tester) async {
    await tester.pumpWidget(_app(const Center(child: MeditejoMark())));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(
      _app(const Center(child: MeditejoMark(animate: false))),
    );
    expect(_mark(tester).isRunning, isFalse);
    expect(await _moves(tester), isFalse);
  });

  group('geometry', () {
    test('the loop is seamless', () {
      final start = MarkFrame();
      final end = MarkFrame();
      MarkGeometry.frameAt(0, start);
      MarkGeometry.frameAt(1, end);
      for (var i = 0; i < start.blob.length; i++) {
        expect(end.blob[i], closeTo(start.blob[i], 1e-9));
      }
      expect(end.coreRadiusNow, closeTo(start.coreRadiusNow, 1e-9));
      expect(end.dotX, closeTo(start.dotX, 1e-9));
      expect(end.dotY, closeTo(start.dotY, 1e-9));
    });

    test('stays inside its square through the loop', () {
      final f = MarkFrame();
      for (var step = 0; step < 600; step++) {
        MarkGeometry.frameAt(step / 600, f);
        for (final v in f.blob) {
          expect(v, inInclusiveRange(0.02, 0.98));
        }
      }
    });
  });

  test('the committed SVG is the geometry at rest', () {
    // Regenerate with: UPDATE_MARK_SVG=1 flutter test
    //   test/widgets/branding/meditejo_mark_test.dart
    final scheme = meditejoColorScheme(Brightness.light);
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final svg = MarkGeometry.svg(
      blob: hex(scheme.primaryContainer),
      ring: hex(scheme.tertiary),
      core: hex(scheme.primary),
    );
    final file = File('assets/branding/meditejo_mark.svg');
    if (Platform.environment['UPDATE_MARK_SVG'] == '1') {
      file
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(svg);
    }
    expect(file.readAsStringSync(), svg);
  });
}
