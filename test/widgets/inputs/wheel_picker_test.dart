import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';

final _minutes = [
  const WheelOption(0, 'Off'),
  for (var m = 1; m <= 60; m++)
    WheelOption(
      m,
      '$m min',
      semanticsLabel: m == 1 ? '1 minute' : '$m minutes',
    ),
];

int? _parse(String text) {
  final v = int.tryParse(text);
  return v != null && v >= 0 && v <= 60 ? v : null;
}

class _Harness {
  final reported = <int>[];
  int value = 5;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  int value = 5,
  bool typing = true,
  double textScale = 1,
}) async {
  final h = _Harness()..value = value;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: StatefulBuilder(
                builder: (context, setState) => WheelPicker<int>(
                  label: 'Interval',
                  options: _minutes,
                  value: h.value,
                  parseEntry: typing ? _parse : null,
                  entryHint: '0 to 60 minutes',
                  onChanged: (v) => setState(() {
                    h.reported.add(v);
                    h.value = v;
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return h;
}

WheelPickerState<int> _state(WidgetTester tester) =>
    tester.state<WheelPickerState<int>>(find.byType(WheelPicker<int>));

void main() {
  group('WheelSettleGroup', () {
    Future<(_Harness, WheelSettleGroup)> pumpInScope(
      WidgetTester tester,
    ) async {
      final h = _Harness();
      final group = WheelSettleGroup();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WheelSettleScope(
              group: group,
              child: StatefulBuilder(
                builder: (context, setState) => WheelPicker<int>(
                  label: 'Interval',
                  options: _minutes,
                  value: h.value,
                  onChanged: (v) => setState(() {
                    h.reported.add(v);
                    h.value = v;
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      return (h, group);
    }

    testWidgets('a still wheel is settled at once', (tester) async {
      final (h, group) = await pumpInScope(tester);
      expect(group.moving, isFalse);
      var done = false;
      unawaited(group.settled().then((_) => done = true));
      await tester.pump();
      expect(done, isTrue);
      expect(h.reported, isEmpty);
    });

    testWidgets('a flung wheel settles after it has reported where it landed', (
      tester,
    ) async {
      final (h, group) = await pumpInScope(tester);
      await tester.fling(
        find.byType(ListWheelScrollView),
        const Offset(0, -300),
        1200,
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(group.moving, isTrue);
      expect(h.reported, isEmpty, reason: 'it reports once, at rest');
      var done = false;
      unawaited(group.settled().then((_) => done = true));
      await tester.pump();
      expect(done, isFalse);
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(h.reported, [_state(tester).selectedIndex]);
      expect(group.moving, isFalse);
    });

    testWidgets('a wheel taken off the screen stops being waited for', (
      tester,
    ) async {
      final (_, group) = await pumpInScope(tester);
      await tester.fling(
        find.byType(ListWheelScrollView),
        const Offset(0, -300),
        1200,
      );
      await tester.pump(const Duration(milliseconds: 60));
      var done = false;
      unawaited(group.settled().then((_) => done = true));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(done, isTrue);
      expect(group.moving, isFalse);
    });
  });

  testWidgets('a drag snaps to a value and reports it once, at rest', (
    tester,
  ) async {
    final h = await _pump(tester);
    expect(_state(tester).selectedIndex, 5);
    // Two and a bit rows up: the wheel settles on a whole row.
    await tester.drag(find.byType(ListWheelScrollView), const Offset(0, -92));
    await tester.pumpAndSettle();
    expect(_state(tester).selectedIndex, 7);
    expect(h.reported, [7], reason: 'one write for the whole gesture');
    expect(find.text('7 min'), findsOneWidget);
  });

  testWidgets('each tick under the finger is a light haptic', (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          calls.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);
    // A finger moves in small steps: one tick per row it crosses.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListWheelScrollView)),
    );
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls.toSet(), {'HapticFeedbackType.selectionClick'});
    expect(calls.length, _state(tester).selectedIndex - 5);
    expect(calls.length, greaterThanOrEqualTo(2));

    // A move the app makes (a tap on a neighbour) does not buzz per row.
    calls.clear();
    await tester.tap(find.text('${_state(tester).selectedIndex + 1} min'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('tapping a neighbour moves to it', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('6 min'));
    await tester.pumpAndSettle();
    expect(h.reported, [6]);
    expect(_state(tester).selectedIndex, 6);
  });

  testWidgets('one adjustable control for a screen reader', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await _pump(tester);
    final node = tester.getSemantics(find.byType(WheelPicker<int>));
    expect(
      node,
      matchesSemantics(
        label: 'Interval',
        value: '5 minutes',
        increasedValue: '6 minutes',
        decreasedValue: '4 minutes',
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        customActions: [const CustomSemanticsAction(label: 'Type a value')],
      ),
    );
    // The loose rows are not read one by one.
    expect(find.bySemanticsLabel('6 min'), findsNothing);

    tester.semantics.performAction(
      find.semantics.byLabel('Interval'),
      SemanticsAction.increase,
    );
    await tester.pumpAndSettle();
    expect(h.reported, [6]);
    tester.semantics.performAction(
      find.semantics.byLabel('Interval'),
      SemanticsAction.decrease,
    );
    await tester.pumpAndSettle();
    tester.semantics.performAction(
      find.semantics.byLabel('Interval'),
      SemanticsAction.decrease,
    );
    await tester.pumpAndSettle();
    expect(h.reported.last, 4);
    semantics.dispose();
  });

  testWidgets('the ends offer no step past them', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, value: 0, typing: false);
    expect(
      tester.getSemantics(find.byType(WheelPicker<int>)),
      matchesSemantics(
        label: 'Interval',
        value: 'Off',
        increasedValue: '1 minute',
        hasIncreaseAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('tapping the chosen value types an exact one', (tester) async {
    final h = await _pump(tester);
    await tester.tap(find.text('5 min'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('0 to 60 minutes'), findsOneWidget);
    final field = find.byKey(const ValueKey('wheel_picker_entry'));
    expect(tester.widget<TextField>(field).controller!.text, '5');

    // Out of range: says why and stays open.
    await tester.enterText(field, '75');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(h.reported, isEmpty);

    await tester.enterText(field, '42');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(h.reported, [42]);
    expect(_state(tester).selectedIndex, 42);
    expect(find.text('42 min'), findsOneWidget);
  });

  testWidgets('a long press types too; cancelling changes nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    await tester.longPress(find.text('4 min'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.reported, isEmpty);
    expect(_state(tester).selectedIndex, 5);
  });

  testWidgets('without a parser there is no typing', (tester) async {
    await _pump(tester, typing: false);
    await tester.tap(find.text('5 min'));
    await tester.longPress(find.text('5 min'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('follows a value changed elsewhere', (tester) async {
    final h = await _pump(tester);
    final setState = tester.state<State>(find.byType(StatefulBuilder));
    // ignore: invalid_use_of_protected_member
    setState.setState(() => h.value = 30);
    await tester.pumpAndSettle();
    expect(_state(tester).selectedIndex, 30);
    expect(h.reported, isEmpty, reason: 'following is not a user change');
  });

  testWidgets('rows grow with 2× text and still fit', (tester) async {
    await _pump(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(ListWheelScrollView));
    expect(size.height, 40 * 2 * 5);
    expect(find.text('5 min'), findsOneWidget);
  });
}
