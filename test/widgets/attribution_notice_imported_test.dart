import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/widgets/attribution_notice.dart';

Future<void> pump(
  WidgetTester tester,
  SourceAttribution a, {
  bool compact = false,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: AttributionNotice(attribution: a, compact: compact),
    ),
  ),
);

void main() {
  testWidgets('imported material with no licence is still credited', (
    tester,
  ) async {
    await pump(
      tester,
      const SourceAttribution(
        source: 'example.org',
        creator: 'Example Sangha',
        url: 'https://example.org/',
        licenseName: '',
        licenseUrl: '',
      ),
    );
    expect(find.text('Example Sangha · example.org'), findsOneWidget);
    expect(find.textContaining('Licence'), findsNothing);
    expect(
      find.byType(InkWell),
      findsOneWidget,
      reason: 'only the credit is a link',
    );
  });

  testWidgets('a file from this device has nothing to link to', (tester) async {
    await pump(
      tester,
      const SourceAttribution(
        source: 'This device',
        url: '',
        licenseName: '',
        licenseUrl: '',
      ),
      compact: true,
    );
    expect(find.text('This device'), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a lone episode shows the feed\'s licence, linked', (
    tester,
  ) async {
    // What LibSource builds for a single episode added from a feed.
    await pump(
      tester,
      const SourceAttribution(
        source: 'example.org',
        creator: 'Example Sangha',
        url: 'https://example.org/evening',
        licenseName: 'CC BY-NC 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-nc/4.0/',
      ),
    );
    expect(find.text('Example Sangha · example.org'), findsOneWidget);
    expect(find.textContaining('CC BY-NC 4.0'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
  });

  testWidgets('a licensed source still shows its licence', (tester) async {
    await pump(
      tester,
      const SourceAttribution(
        source: 'Dharma Seed',
        creator: 'Rob Burbea',
        url: 'https://dharmaseed.org/talks/1/',
        licenseName: 'CC BY-NC-ND 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
      ),
    );
    expect(find.text('Licence: CC BY-NC-ND 4.0'), findsOneWidget);
    expect(find.text('Streamed as recorded, unmodified.'), findsOneWidget);
  });
}
