import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/cards/card_tokens.dart';
import 'package:medito/widgets/cards/filter_chip_bar.dart';

Widget _bar(double width, {String selected = 'All'}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: FilterChipBar<String>(
          selected: selected,
          onSelected: (_) {},
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
