import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/inputs/range_control.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double value,
  bool logarithmic = false,
  List<double>? moved,
  List<double>? released,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: RangeControl(
        sliderKey: const ValueKey('range'),
        label: 'Pitch',
        low: 'Deep',
        high: 'High',
        min: 100,
        max: 1600,
        value: value,
        logarithmic: logarithmic,
        format: (v) => '${v.round()} Hz',
        onChanged: (v) => moved?.add(v),
        onChangeEnd: (v) => released?.add(v),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the name, the value in its units and both ends', (
    tester,
  ) async {
    await _pump(tester, value: 400);
    expect(find.text('Pitch'), findsOneWidget);
    expect(find.text('400 Hz'), findsOneWidget);
    expect(find.text('Deep'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });

  testWidgets('a linear track is even in the value', (tester) async {
    final moved = <double>[];
    await _pump(tester, value: 850, moved: moved);
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('range')));
    expect(slider.value, closeTo(0.5, 1e-9));
    slider.onChanged!(0.25);
    expect(moved.single, closeTo(100 + 0.25 * 1500, 1e-6));
  });

  testWidgets('a logarithmic track is even in the ratio', (tester) async {
    final moved = <double>[];
    final released = <double>[];
    await _pump(
      tester,
      value: 400,
      logarithmic: true,
      moved: moved,
      released: released,
    );
    final slider = tester.widget<Slider>(find.byKey(const ValueKey('range')));
    // 100 to 1600 is four doublings, so 400 is half way.
    expect(slider.value, closeTo(0.5, 1e-9));
    slider.onChanged!(0.75);
    slider.onChangeEnd!(1);
    expect(moved.single, closeTo(800, 1e-6));
    expect(released.single, closeTo(1600, 1e-6));
  });

  testWidgets('a value outside the range pins to the track', (tester) async {
    await _pump(tester, value: 5000);
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('range'))).value,
      1.0,
    );
  });

  group('vertical', () {
    Future<void> pumpOne(WidgetTester tester, {List<double>? moved}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 72,
                  child: RangeControl(
                    axis: Axis.vertical,
                    sliderKey: const ValueKey('range'),
                    label: 'Pitch',
                    low: 'Deep',
                    high: 'High',
                    min: 100,
                    max: 1600,
                    value: 400,
                    logarithmic: true,
                    format: (v) => '${v.round()} Hz',
                    onChanged: (v) => moved?.add(v),
                  ),
                ),
              ),
            ),
          ),
        );

    testWidgets('shows the value, both ends and the name', (tester) async {
      await pumpOne(tester);
      expect(find.text('400 Hz'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Deep'), findsOneWidget);
      expect(find.text('Pitch'), findsOneWidget);
      // Top to bottom: value, high end, track, low end, name.
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      final track = tester.getRect(find.byKey(const ValueKey('range')));
      expect(top('400 Hz'), lessThan(top('High')));
      expect(top('High'), lessThan(track.top));
      expect(track.bottom, lessThanOrEqualTo(top('Deep')));
      expect(top('Deep'), lessThan(top('Pitch')));
      expect(track.height, greaterThan(track.width));
    });

    testWidgets('dragging up raises the value and down lowers it', (
      tester,
    ) async {
      final moved = <double>[];
      await pumpOne(tester, moved: moved);
      final track = find.byKey(const ValueKey('range'));
      await tester.drag(track, const Offset(0, -40));
      expect(moved.last, greaterThan(400));
      moved.clear();
      await tester.drag(track, const Offset(0, 40));
      expect(moved.last, lessThan(400));
    });
  });

  group('vertical, more', () {
    Widget control({List<double>? moved, TextDirection? dir}) => MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: dir ?? TextDirection.ltr,
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 72,
            child: RangeControl(
              axis: Axis.vertical,
              sliderKey: const ValueKey('range'),
              label: 'Pitch',
              low: 'Deep',
              high: 'High',
              min: 100,
              max: 1600,
              value: 400,
              logarithmic: true,
              format: (v) => '${v.round()} Hz',
              onChanged: (v) => moved?.add(v),
            ),
          ),
        ),
      ),
    );

    testWidgets('up is more in a right-to-left language too', (tester) async {
      final moved = <double>[];
      await tester.pumpWidget(control(moved: moved, dir: TextDirection.rtl));
      await tester.drag(
        find.byKey(const ValueKey('range')),
        const Offset(0, -40),
      );
      expect(moved.last, greaterThan(400));
    });

    testWidgets('a screen reader gets the name and the value on the slider', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(control());
      // The slider's node carries both the name and the value in the control's
      // own units: one thing to adjust, read once.
      final named = find.semantics.byLabel('Pitch');
      final valued = find.semantics.byValue('400 Hz');
      expect(named, findsOneWidget);
      expect(valued, findsOneWidget);
      // Merged: the value node is folded into the one that has the name.
      final value = valued.evaluate().single;
      expect(value.isMergedIntoParent, isTrue);
      expect(value.parent!.id, named.evaluate().single.id);
      expect(find.semantics.byAction(SemanticsAction.increase), findsWidgets);
      expect(find.semantics.byLabel('High'), findsNothing);
      semantics.dispose();
    });
  });

  group('RangeControlBank', () {
    Future<void> pumpBank(
      WidgetTester tester, {
      required double width,
      double textScale = 1,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RangeControlBank(
                children: [
                  for (final name in [
                    'Pitch',
                    'Brightness',
                    'Ring',
                    'Strike',
                    'Shimmer',
                  ])
                    RangeControl(
                      axis: Axis.vertical,
                      sliderKey: ValueKey(name),
                      label: name,
                      low: 'Low',
                      high: 'High',
                      min: 0,
                      max: 1,
                      value: 0.5,
                      format: (v) => '${(v * 100).round()}%',
                      onChanged: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    List<Offset> tops(WidgetTester tester) => [
      for (final name in ['Pitch', 'Brightness', 'Ring', 'Strike', 'Shimmer'])
        tester.getTopLeft(find.byKey(ValueKey(name))),
    ];

    testWidgets('five channels share a row on a 360 dp phone', (tester) async {
      await pumpBank(tester, width: 360);
      expect(tester.takeException(), isNull);
      final t = tops(tester);
      expect(t.map((o) => o.dy).toSet(), hasLength(1));
      expect(t.map((o) => o.dx).toSet(), hasLength(5));
      for (var i = 1; i < 5; i++) {
        expect(t[i].dx, greaterThan(t[i - 1].dx));
      }
    });

    testWidgets('large text makes more rows, not clipped channels', (
      tester,
    ) async {
      await pumpBank(tester, width: 360, textScale: 2);
      expect(tester.takeException(), isNull);
      final t = tops(tester);
      // 128 dp a channel in 328: two to a row, so 2 + 2 + 1.
      expect(t.map((o) => o.dy).toSet(), hasLength(3));
      for (final name in ['Pitch', 'Brightness', 'Ring', 'Strike', 'Shimmer']) {
        final rect = tester.getRect(find.byKey(ValueKey(name)));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
      }
    });
  });

  testWidgets('a bank with no width to fill sits in one row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RangeControlBank(
              children: [
                for (var i = 0; i < 3; i++)
                  RangeControl(
                    axis: Axis.vertical,
                    sliderKey: ValueKey('c$i'),
                    label: 'C$i',
                    low: 'Low',
                    high: 'High',
                    min: 0,
                    max: 1,
                    value: 0.5,
                    format: (v) => '$v',
                    onChanged: (_) {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect({
      for (var i = 0; i < 3; i++)
        tester.getTopLeft(find.byKey(ValueKey('c$i'))).dy,
    }, hasLength(1));
  });
}
