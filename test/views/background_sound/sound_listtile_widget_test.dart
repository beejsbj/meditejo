import 'package:flutter/material.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/views/background_sound/widgets/sound_listtile_widget.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

const _rain = BackgroundSoundsModel(
  id: '12',
  title: 'Rain',
  path: 'https://example.com/rain.mp3',
  duration: 60,
);

const _none = BackgroundSoundsModel(
  id: kNoneBackgroundSoundId,
  title: 'None',
  path: '',
  duration: 0,
);

/// Lets a test put the notifier in an arbitrary state and observe the calls the
/// widget makes, without touching the filesystem or an audio player.
class _FakeNotifier extends BackgroundSoundsNotifier {
  _FakeNotifier(this._initialState);

  final BackgroundSoundsState _initialState;
  final retried = <String>[];
  final changed = <String?>[];
  final bells = <bool>[];

  @override
  BackgroundSoundsState build() => _initialState;

  @override
  void retryDownload(BackgroundSoundsModel sound) => retried.add(sound.id);

  @override
  void handleOnChangeSound(
    BackgroundSoundsModel? sound, {
    bool preview = true,
  }) => changed.add(sound?.id);

  @override
  void setSessionBells(bool enabled, {bool preview = true}) {
    bells.add(enabled);
    state = state.copyWith(bellsEnabled: enabled);
  }
}

void main() {
  Future<_FakeNotifier> pump(
    WidgetTester tester,
    BackgroundSoundsState state, {
    BackgroundSoundsModel sound = _rain,
    Locale locale = const Locale('en'),
  }) async {
    final notifier = _FakeNotifier(state);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backgroundSoundsNotifierProvider.overrideWith(() => notifier),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SoundListTileWidget(sound: sound)),
        ),
      ),
    );

    return notifier;
  }

  testWidgets('a failed sound shows the retry message', (tester) async {
    await pump(tester, const BackgroundSoundsState(failedBgSound: _rain));

    expect(find.text("Couldn't download. Tap to try again."), findsOneWidget);
  });

  testWidgets('tapping a failed sound retries instead of re-selecting it', (
    tester,
  ) async {
    final notifier = await pump(
      tester,
      const BackgroundSoundsState(failedBgSound: _rain),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(notifier.retried, ['12']);
    expect(
      notifier.changed,
      isEmpty,
      reason: 're-selecting would reuse the corrupt file and fail again',
    );
  });

  testWidgets('a sound with no failure shows no message and selects on tap', (
    tester,
  ) async {
    final notifier = await pump(tester, const BackgroundSoundsState());

    expect(find.text("Couldn't download. Tap to try again."), findsNothing);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(notifier.changed, ['12']);
    expect(notifier.retried, isEmpty);
  });

  testWidgets('a failure on another sound leaves this row alone', (
    tester,
  ) async {
    final notifier = await pump(
      tester,
      const BackgroundSoundsState(failedBgSound: _none),
    );

    expect(find.text("Couldn't download. Tap to try again."), findsNothing);

    await tester.tap(find.byType(InkWell));
    await tester.pump();

    expect(notifier.changed, ['12']);
  });

  testWidgets('the None row is localised, not shown as the English title', (
    tester,
  ) async {
    await pump(
      tester,
      const BackgroundSoundsState(),
      sound: _none,
      locale: const Locale('es'),
    );

    expect(find.text('Ninguno'), findsOneWidget);
    expect(find.text('None'), findsNothing);
  });

  testWidgets('session bells explain the three cues and select normally', (
    tester,
  ) async {
    final notifier = await pump(
      tester,
      const BackgroundSoundsState(),
      sound: kSessionBellsSound,
    );
    expect(find.text('Session bells'), findsOneWidget);
    expect(
      find.text('A bell at the beginning, middle and end'),
      findsOneWidget,
    );
    await tester.tap(find.byType(InkWell));
    expect(notifier.changed, [kSessionBellsId]);
  });

  testWidgets('session bells are localised in Spanish', (tester) async {
    await pump(
      tester,
      const BackgroundSoundsState(),
      sound: kSessionBellsSound,
      locale: const Locale('es'),
    );
    expect(find.text('Campanas de sesión'), findsOneWidget);
  });

  testWidgets('the Sounds screen offers no legacy bells switch', (
    tester,
  ) async {
    final notifier = _FakeNotifier(const BackgroundSoundsState());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...soundscapeTestOverrides(FakeSoundscapeEngine()),
          backgroundSoundsNotifierProvider.overrideWith(() => notifier),
          backgroundSoundsProvider.overrideWith(
            (ref) async => throw const ServerError(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SoundsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Customize's cue scheduler owns bells; a switch here (reachable from
    // the player) would ring a second set over the cues.
    final end = find.byKey(const ValueKey('sound_credits_footer'));
    await tester.scrollUntilVisible(
      end,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_library')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(end, findsOneWidget);
    expect(find.text('Session bells'), findsNothing);
    expect(find.byType(Switch), findsNWidgets(2), reason: 'practice, talks');
    expect(notifier.bells, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
