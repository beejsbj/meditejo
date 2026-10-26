import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import '../../helpers/library_app.dart';

void main() {
  setUp(() {
    identityClock = () => DateTime(2026, 10, 26, 9);
  });
  tearDown(() {
    identityClock = DateTime.now;
  });

  testWidgets("Home shows today's mark; a long-press pins and unpins it", (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );
    await tester.pump(const Duration(seconds: 1));

    MeditejoMark homeMark() => tester.widget<MeditejoMark>(
      find.descendant(
        of: find.byKey(const ValueKey('home_mark')),
        matching: find.byType(MeditejoMark),
      ),
    );
    expect(homeMark().mark.seed, 'm-2026-10-26');
    expect(find.byKey(const ValueKey('home_mark_pinned')), findsNothing);

    await tester.longPress(find.byKey(const ValueKey('home_mark')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text("Today's mark"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home_mark_pin')));
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('home_mark_state'))).data,
      'Pinned',
    );
    final saved = app.prefs.getString(
      SharedPreferenceConstants.identityPinnedMark,
    );
    expect(MarkSpec.decode(saved!).seed, 'm-2026-10-26');

    // Close the sheet: Home now shows the pin.
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('home_mark_pinned')), findsOneWidget);
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('home_mark')),
    );
    expect(semantics.label, 'Pinned');

    await tester.longPress(find.byKey(const ValueKey('home_mark')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const ValueKey('home_mark_unpin')));
    await tester.pump();
    expect(find.text("Today's mark"), findsOneWidget);
    expect(
      app.prefs.getString(SharedPreferenceConstants.identityPinnedMark),
      isNull,
    );
  });
}
