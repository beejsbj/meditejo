import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/views/categories/practice_tile.dart';
import 'package:medito/widgets/art/art_subject.dart';

import '../../helpers/art_finders.dart';

final _catalogue = CategoryCatalogue.parse(
  File(categoriesAsset).readAsStringSync(),
);

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

PracticeCategory _c(String id) => _catalogue.category(id)!;

void main() {
  setUpAll(holdCuratedArt);

  testWidgets('a card shows the name, where it comes from, and its line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 148,
          height: 262,
          child: PracticeTile(
            category: _c('emptiness'),
            size: PracticeTileSize.card,
          ),
        ),
      ),
    );
    expect(find.text('Śūnyatā'), findsOneWidget);
    // Its language, translated, then its own script.
    expect(find.text('Sanskrit  शून्यता'), findsOneWidget);
    expect(find.text(_c('emptiness').blurb), findsOneWidget);
    expect(
      findArt(
        const ArtSubject.practice(
          'emptiness',
          ground: 'mist',
          figure: 'rings:target',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a shared practice lists its originals; a modern one its founder',
    (tester) async {
      await tester.pumpWidget(
        _app(
          Row(
            children: [
              for (final id in ['chanting', 'headless'])
                SizedBox(
                  width: 170,
                  height: 300,
                  child: PracticeTile(
                    category: _c(id),
                    size: PracticeTileSize.tall,
                  ),
                ),
            ],
          ),
        ),
      );
      expect(find.text('Chanting'), findsOneWidget);
      expect(find.text('Paritta · Kīrtan · Okyō'), findsOneWidget);
      expect(find.text('Headless Way'), findsOneWidget);
      expect(find.text('Douglas Harding'), findsOneWidget);
    },
  );

  testWidgets('the line and the languages follow the app\'s language', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 170,
          height: 300,
          child: PracticeTile(category: _c('zen'), size: PracticeTileSize.tall),
        ),
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();
    // The name is never translated.
    expect(find.text('Zazen'), findsOneWidget);
    expect(find.text('Japanisch  坐禅'), findsOneWidget);
    expect(find.text(_c('zen').blurbs['de']!), findsOneWidget);
  });

  testWidgets('a compact tile is a choice that shows when it is ticked', (
    tester,
  ) async {
    var taps = 0;
    Future<void> pump(bool on) => tester.pumpWidget(
      _app(
        SizedBox(
          width: 170,
          height: 112,
          child: PracticeTile(
            category: _c('metta'),
            size: PracticeTileSize.compact,
            selected: on,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    await pump(false);
    expect(find.byIcon(Icons.check), findsNothing);
    // No line on a compact tile: the sheet is for choosing.
    expect(find.text(_c('metta').blurb), findsNothing);
    await tester.tap(find.byType(PracticeTile));
    expect(taps, 1);
    await pump(true);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(tester.getSemantics(find.byType(PracticeTile)).label, 'Mettā. Pāli');
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.selected == true,
      ),
      findsOneWidget,
    );
  });

  test('groups come in order, and an unknown group goes last', () {
    final groups = groupPractices(_catalogue.categories);
    expect([for (final (g, _) in groups) g], practiceGroups);
    expect(groups.expand((g) => g.$2).length, _catalogue.categories.length);
    final odd = groupPractices([
      const PracticeCategory(id: 'x', name: 'X', group: 'other'),
      _c('metta'),
    ]);
    expect([for (final (g, _) in odd) g], ['heart', 'other']);
  });
}
