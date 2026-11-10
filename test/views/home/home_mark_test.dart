import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/identity/mark_generator.dart';
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

  testWidgets("Home shows today's mark, and a long-press does nothing", (
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
    final semantics = tester.getSemantics(
      find.byKey(const ValueKey('home_mark')),
    );
    expect(semantics.label, 'Home mark');
    expect(semantics.value, "Today's mark");
    expect(
      semantics.getSemanticsData().hasAction(SemanticsAction.longPress),
      isFalse,
    );

    await tester.longPress(find.byKey(const ValueKey('home_mark')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(BottomSheet), findsNothing);
    expect(homeMark().mark.seed, 'm-2026-10-26');
    expect(
      app.prefs.getString(SharedPreferenceConstants.identityPinnedMark),
      isNull,
    );
  });

  testWidgets('a mark pinned by an earlier build is ignored, then dropped', (
    tester,
  ) async {
    final app = await LibraryTestApp.create(tester);
    await app.prefs.setString(
      SharedPreferenceConstants.identityPinnedMark,
      MarkGenerator.build('g-1kq').encode(),
    );
    await app.pump(
      tester,
      const HomeView(),
      overrides: [continueItemsProvider.overrideWith((ref) async => [])],
    );
    await tester.pump(const Duration(seconds: 1));
    final mark = tester.widget<MeditejoMark>(
      find.descendant(
        of: find.byKey(const ValueKey('home_mark')),
        matching: find.byType(MeditejoMark),
      ),
    );
    expect(mark.mark.seed, 'm-2026-10-26');

    // What main.dart does at launch.
    await forgetPinnedMark(app.prefs);
    expect(
      app.prefs.getString(SharedPreferenceConstants.identityPinnedMark),
      isNull,
    );
  });
}
