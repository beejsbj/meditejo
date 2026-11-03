import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/views/library/library_view.dart';

import '../../helpers/dharma_seed_app.dart';
import '../../helpers/library_app.dart';

/// Library at [width] dp with [scale]× text, in [locale].
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  double scale = 1,
  Locale locale = const Locale('en'),
}) async {
  final app = await LibraryTestApp.create(tester);
  await app.pump(
    tester,
    Builder(
      builder: (context) => Localizations.override(
        context: context,
        locale: locale,
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: const LibraryView(),
        ),
      ),
    ),
  );
  tester.view.physicalSize = Size(width, 800);
  await DharmaSeedTestApp.settle(tester);
}

/// The header's title is drawn whole: nothing cut off or faded.
void _titleWhole(WidgetTester tester, String title) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
  expect(
    paragraph.getMaxIntrinsicWidth(double.infinity),
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason: '"$title" is cut off',
  );
}

final _add = find.byKey(const ValueKey('library_add'));

/// The "+": a round 48 dp target with a tooltip and a spoken label, just
/// left of the You button, and nothing else in the header (#62).
void _plusThenYou(WidgetTester tester) {
  expect(_add, findsOneWidget);
  expect(find.descendant(of: _add, matching: find.text('Add')), findsNothing);
  final size = tester.getSize(_add);
  expect(size.width, greaterThanOrEqualTo(48));
  expect(size.height, greaterThanOrEqualTo(48));
  expect(find.byTooltip('Add to your library'), findsOneWidget);
  expect(
    tester.getSemantics(_add),
    isSemantics(
      tooltip: 'Add to your library',
      isButton: true,
      hasTapAction: true,
    ),
  );
  final you = find.byKey(const ValueKey('you_button'));
  expect(you, findsOneWidget);
  expect(tester.getCenter(_add).dx, lessThan(tester.getCenter(you).dx));
  // New playlist moved into the sheet.
  expect(find.byKey(const ValueKey('library_new_course')), findsNothing);
  expect(
    find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.playlist_add_rounded),
    ),
    findsNothing,
  );
}

void main() {
  // The app's own font: the test font draws every letter a full em wide,
  // which would make any title look cut off.
  setUpAll(() async {
    final sans = FontLoader('Google Sans');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      sans.addFont(
        rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'),
      );
    }
    await sans.load();
  });

  testWidgets('at 411 dp the header is the title, then "+" and You', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, width: 411);
    _titleWhole(tester, 'Your library');
    _plusThenYou(tester);
    handle.dispose();
  });

  testWidgets('at 360 dp with 1.3x text, "+" and You fit, the title is whole', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, width: 360, scale: 1.3);
    _titleWhole(tester, 'Your library');
    _plusThenYou(tester);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  for (final width in [411.0, 360.0]) {
    testWidgets('in German at ${width.round()} dp the title is whole', (
      tester,
    ) async {
      await _pump(tester, width: width, locale: const Locale('de'));
      _titleWhole(tester, 'Deine Bibliothek');
    });
  }

  testWidgets('in German at 360 dp with 1.3x text, the title is whole', (
    tester,
  ) async {
    await _pump(tester, width: 360, scale: 1.3, locale: const Locale('de'));
    _titleWhole(tester, 'Deine Bibliothek');
    expect(_add, findsOneWidget);
    expect(find.byKey(const ValueKey('you_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
