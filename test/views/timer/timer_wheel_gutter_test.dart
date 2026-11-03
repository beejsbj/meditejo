import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/timer/start_timer.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// #91 on the Timer page, whose screen is the Customize sheet: its length
/// wheel stands between scroll gutters, and a turn of it can be undone.
void main() {
  testWidgets('the length wheel: a drag beside it changes nothing, a turn '
      'of it offers Undo', (tester) async {
    tester.view.physicalSize = const Size(411, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TimerView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    int minutes() =>
        container.read(cueSettingsProvider(timerCueScope)).durationMinutes;
    final start = minutes();

    final tile = find.byKey(const ValueKey('customize_slot_length'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    final wheel = find.byKey(const ValueKey('wheel_Duration'));
    await tester.ensureVisible(wheel);
    await tester.pumpAndSettle();
    final rect = tester.getRect(wheel);
    final section = tester.getRect(
      find.byKey(const ValueKey('customize_section_length')),
    );
    expect(rect.left - section.left, greaterThanOrEqualTo(16 + 28));
    expect(section.right - rect.right, greaterThanOrEqualTo(16 + 28));

    // Both gutters: the page scrolls (or stays), the length does not move.
    for (final x in [
      (section.left + rect.left) / 2,
      (rect.right + section.right) / 2,
    ]) {
      await tester.ensureVisible(wheel);
      await tester.pumpAndSettle();
      await tester.dragFrom(
        Offset(x, tester.getCenter(wheel).dy),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(minutes(), start);
      expect(find.byKey(const ValueKey('customize_undo')), findsNothing);
    }

    await tester.ensureVisible(wheel);
    await tester.pumpAndSettle();
    await tester.drag(wheel, const Offset(0, -80));
    await tester.pumpAndSettle();
    final turned = minutes();
    expect(turned, greaterThan(start));
    final picker = tester.widget<WheelPicker<dynamic>>(wheel);
    final shown = picker.options.firstWhere((o) => o.value == turned).label;
    expect(find.text('Duration: $shown'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('customize_undo_button')));
    await tester.pumpAndSettle();
    expect(minutes(), start);

    // Drops the page so its 30 second refresh timer is cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
