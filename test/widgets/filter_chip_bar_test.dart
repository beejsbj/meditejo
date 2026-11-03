import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/filter_chip_bar.dart';

Widget _bar(
  double width, {
  String selected = 'All',
  ValueChanged<String?>? onSelected,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  builder: (context, child) =>
      Directionality(textDirection: direction, child: child!),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: FilterChipBar<String>(
          selected: selected,
          onSelected: onSelected ?? (_) {},
          options: [
            for (final name in const [
              'All',
              'Courses',
              'Playlists',
              'Singles',
              'Teachers',
              'Downloads',
            ])
              FilterOption(name, name, key: ValueKey('chip_$name')),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  for (final width in [411.0, 360.0]) {
    group('at ${width.round()} dp', () {
      testWidgets('the last chip can be scrolled fully into view, clear of '
          'the edge', (tester) async {
        await tester.pumpWidget(_bar(width));
        // At rest the row overflows, so the last chip starts off-screen.
        final box = tester.getRect(find.byType(FilterChipBar<String>));
        expect(
          tester.getRect(find.byKey(const ValueKey('chip_Downloads'))).right,
          greaterThan(box.right),
        );
        await tester.drag(find.byType(SingleChildScrollView), Offset(-600, 0));
        await tester.pump();
        final last = tester.getRect(
          find.byKey(const ValueKey('chip_Downloads')),
        );
        expect(last.right, lessThanOrEqualTo(box.right - kCardGutter + 0.5));
        expect(last.left, greaterThanOrEqualTo(box.left));
      });

      testWidgets('fades at rest, so a cut-off chip reads as scrolling', (
        tester,
      ) async {
        await tester.pumpWidget(_bar(width));
        await tester.pump();
        await tester.pump();
        expect(
          find.descendant(
            of: find.byType(FilterChipBar<String>),
            matching: find.byType(ShaderMask),
          ),
          findsOneWidget,
        );
      });
    });
  }

  Finder shader() => find.descendant(
    of: find.byType(FilterChipBar<String>),
    matching: find.byType(ShaderMask),
  );

  testWidgets('a tap on the last visible chip is not swallowed by the fade', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(_bar(411, onSelected: (v) => picked = v));
    await tester.pump();
    await tester.pump();
    expect(shader(), findsOneWidget);
    final box = tester.getRect(find.byType(FilterChipBar<String>));
    // The chip straddling the right edge sits inside the fade; tap its visible
    // part.
    String? edge;
    late Rect edgeRect;
    for (final name in const [
      'All',
      'Courses',
      'Playlists',
      'Singles',
      'Teachers',
      'Downloads',
    ]) {
      final r = tester.getRect(find.byKey(ValueKey('chip_$name')));
      if (r.left < box.right && r.right > box.right) {
        edge = name;
        edgeRect = r;
      }
    }
    expect(edge, isNotNull, reason: 'a chip is cut by the right edge');
    await tester.tapAt(Offset((edgeRect.left + box.right) / 2, box.center.dy));
    await tester.pump();
    expect(picked, edge);
  });

  testWidgets('RTL: row starts at the right and still fades and taps', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _bar(411, direction: TextDirection.rtl, onSelected: (v) => picked = v),
    );
    await tester.pump();
    await tester.pump();
    expect(shader(), findsOneWidget);
    final box = tester.getRect(find.byType(FilterChipBar<String>));
    final all = tester.getRect(find.byKey(const ValueKey('chip_All')));
    expect(all.right, closeTo(box.right - kCardGutter, 0.5));
    final last = tester.getRect(find.byKey(const ValueKey('chip_Downloads')));
    expect(last.left, lessThan(box.left));
    await tester.tap(find.byKey(const ValueKey('chip_Courses')));
    expect(picked, 'Courses');
  });

  testWidgets('a row that fits has no fade', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilterChipBar<int>(
            selected: 1,
            onSelected: (_) {},
            options: const [FilterOption(1, 'One'), FilterOption(2, 'Two')],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Two'), findsOneWidget);
    expect(find.byType(ShaderMask), findsNothing);
  });
}
