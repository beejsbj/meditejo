import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/filter_pill.dart';
import 'package:medito/widgets/network_image_widget.dart';

import '../helpers/art_finders.dart';

const _credit = SourceAttribution(
  source: 'Dharma Seed',
  creator: 'Rob Burbea',
  url: 'https://dharmaseed.org/talks/2/',
  licenseName: 'CC BY-NC-ND 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUpAll(holdCuratedArt);

  group('AttributionNotice', () {
    testWidgets('full: credit link, licence link and the unmodified note', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const AttributionNotice(attribution: _credit)),
      );

      expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
      expect(find.text('Licence: CC BY-NC-ND 4.0'), findsOneWidget);
      expect(find.text('Streamed as recorded, unmodified.'), findsOneWidget);
      // Both lines are links for a screen reader, and say where they go.
      expect(
        find.bySemanticsLabel(
          RegExp('Rob Burbea · Dharma Seed\\. View on Dharma Seed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('compact: one line, no note', (tester) async {
      await tester.pumpWidget(
        _app(const AttributionNotice(attribution: _credit, compact: true)),
      );
      expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
      expect(find.text('CC BY-NC-ND 4.0'), findsOneWidget);
      expect(find.text('Streamed as recorded, unmodified.'), findsNothing);
    });

    testWidgets('without a creator, the source stands alone', (tester) async {
      await tester.pumpWidget(
        _app(
          const AttributionNotice(
            attribution: SourceAttribution(
              source: 'Dharma Seed',
              url: 'https://dharmaseed.org/',
              licenseName: 'CC BY-NC-ND 4.0',
              licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
            ),
          ),
        ),
      );
      expect(find.text('Dharma Seed'), findsOneWidget);
    });
  });

  group('generated covers', () {
    testWidgets('stands in when an image has no usable address', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 100,
            height: 100,
            child: NetworkImageWidget(
              url: '',
              art: courseArt('lib-course-sit'),
            ),
          ),
        ),
      );
      expect(findArt(courseArt('lib-course-sit')), findsOneWidget);
    });
  });

  group('FilterPill', () {
    testWidgets('announces whether it is selected and reacts to a tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          FilterPill(label: 'Practice', selected: true, onTap: () => taps++),
        ),
      );
      final semantics = tester.getSemantics(find.byType(FilterPill));
      expect(semantics.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(semantics.label, 'Practice');
      await tester.tap(find.text('Practice'));
      expect(taps, 1);
    });
  });
}
