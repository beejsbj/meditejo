import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/pack/widgets/pack_complete_badge.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/pack_card_widget.dart';

import '../helpers/art_finders.dart';

void main() {
  setUpAll(holdCuratedArt);

  Future<void> pump(
    WidgetTester tester, {
    required bool completed,
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PackCardWidget(
            id: 'pack-sleep',
            title: 'Sleep',
            subTitle: 'Rest well',
            isCompleted: completed,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  testWidgets('shows the tick only when completed', (tester) async {
    await pump(tester, completed: false);
    expect(find.byType(PackCompleteBadge), findsNothing);

    await pump(tester, completed: true);
    expect(find.byType(PackCompleteBadge), findsOneWidget);
  });

  testWidgets('a tap on the tick still opens the pack', (tester) async {
    var taps = 0;
    await pump(tester, completed: true, onTap: () => taps++);

    await tester.tap(find.byType(PackCompleteBadge));
    expect(taps, 1);
  });

  testWidgets('a pack without a picture gets art made for its id', (
    tester,
  ) async {
    await pump(tester, completed: false);
    expect(findArt(courseArt('pack-sleep')), findsOneWidget);
  });
}
