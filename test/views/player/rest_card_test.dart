import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/player/widgets/rest_card.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int seconds,
  VoidCallback? onSkip,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: RestCard(secondsLeft: seconds, onSkip: onSkip ?? () {}),
    ),
  ),
);

void main() {
  testWidgets('says it is resting and how long is left', (tester) async {
    await _pump(tester, seconds: 105);
    expect(find.text('Resting in silence'), findsOneWidget);
    expect(find.text('1:45 left'), findsOneWidget);
    await _pump(tester, seconds: 9);
    expect(find.text('0:09 left'), findsOneWidget);
  });

  testWidgets('Skip this pause asks to carry on', (tester) async {
    var skipped = 0;
    await _pump(tester, seconds: 60, onSkip: () => skipped++);
    await tester.tap(find.text('Skip this pause'));
    expect(skipped, 1);
  });
}
