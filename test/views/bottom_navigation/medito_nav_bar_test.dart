import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';

const _five = [
  MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
  MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
  MeditoNavItem(icon: Symbols.graphic_eq_rounded, label: 'Sounds'),
  MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
  MeditoNavItem(icon: Symbols.person_rounded, label: 'You'),
];

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'five destinations fit a 360 dp phone with large text, ${brightness.name}',
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
                    items: _five,
                    selectedIndex: selected,
                    onSelected: (i) => setState(() => selected = i),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final item in _five) {
          expect(find.text(item.label), findsOneWidget);
        }
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations, hasLength(5));

        await tester.tap(find.text('You'));
        await tester.pumpAndSettle();
        expect(selected, 4);
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          4,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
