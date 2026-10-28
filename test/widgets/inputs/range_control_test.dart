import 'package:flutter/material.dart';
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
}
