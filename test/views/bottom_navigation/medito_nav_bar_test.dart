import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';

const _four = [
  MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
  MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
  MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
  MeditoNavItem(icon: Symbols.settings_rounded, label: 'Settings'),
];

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'four destinations fit a 360 dp phone with large text, ${brightness.name}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: meditejoTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 640),
                textScaler: TextScaler.linear(1.3),
              ),
              child: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  bottomNavigationBar: MeditoNavBar(
                    items: _four,
                    selectedIndex: selected,
                    onSelected: (i) => setState(() => selected = i),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final item in _four) {
          expect(find.text(item.label), findsOneWidget);
        }
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations, hasLength(4));

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(selected, 3);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          3,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  // The bar's labels as the app sets them, in [locale].
  List<MeditoNavItem> tabs(Locale locale) {
    final l10n = lookupAppLocalizations(locale);
    return [
      MeditoNavItem(icon: Symbols.home_rounded, label: l10n.home),
      MeditoNavItem(icon: Symbols.search_rounded, label: l10n.explore),
      MeditoNavItem(
        icon: Symbols.library_books_rounded,
        label: l10n.navLibrary,
      ),
      MeditoNavItem(icon: Symbols.settings_rounded, label: l10n.navSettings),
    ];
  }

  for (final locale in const [Locale('es'), Locale('de')]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets(
        'every label is one whole line at 360 dp in ${locale.languageCode}, '
        '${scale}x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(360, 640);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final items = tabs(locale);
          for (final selected in [0, 3]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: meditejoTheme(Brightness.light),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(360, 640),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Scaffold(
                    bottomNavigationBar: MeditoNavBar(
                      items: items,
                      selectedIndex: selected,
                      onSelected: (_) {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final item in items) {
              final paragraph = tester.renderObject<RenderParagraph>(
                find.text(item.label),
              );
              expect(paragraph.maxLines, 1, reason: item.label);
              expect(paragraph.didExceedMaxLines, isFalse, reason: item.label);
              // Not clipped either: the whole word fits its slot.
              expect(
                paragraph.getMaxIntrinsicWidth(double.infinity),
                lessThanOrEqualTo(paragraph.size.width + 0.5),
                reason: item.label,
              );
              expect(
                tester.getSize(find.text(item.label)).width,
                lessThanOrEqualTo(360 / 4),
                reason: item.label,
              );
            }
          }
        },
      );
    }
  }
}
