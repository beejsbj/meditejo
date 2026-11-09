import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// The Timer's Sound tile is the third way into the one mixer drawer (#66):
/// the same choice the Sounds tab's "Plays under practice" line and the
/// player's Sounds button make.
void main() {
  testWidgets('the Timer\'s Sound tile opens the mixer drawer and keeps '
      'what is chosen for practice', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
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
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const TimerView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('customize_slot_sound'));
    expect(tile, findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    // The mixer, as a drawer over the Timer: a timer is practice.
    expect(find.byType(SoundsView), findsOneWidget);
    expect(find.text('Plays under practice'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preset_starter-hearth')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_presets')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('preset_starter-hearth')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sounds_chooser_done')));
    await tester.pumpAndSettle();

    final practice = container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.practice);
    expect(practice.enabled, isTrue);
    expect(
      practice.selection,
      const SoundscapeSelection.preset('starter-hearth'),
    );
    expect(find.text('Hearth'), findsWidgets, reason: 'the tile says it');
    // The drawer is closed and nothing auditions on.
    expect(find.byType(SoundsView), findsNothing);
    expect(container.read(soundscapeProvider).playing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
