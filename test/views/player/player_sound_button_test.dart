import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_download_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_speed_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/soundscape_fakes.dart';

/// A talk: the recording does not allow Medito's legacy background sound,
/// but the Sounds mixer may still play under it.
const _talk = PlaybackRequest(
  trackId: 'talk',
  fileId: 'talk-file',
  title: 'A talk',
  description: '',
  coverUrl: '',
  remoteUrl: '/local/talk.mp3',
  duration: 60000,
  hasBackgroundSound: false,
);

void main() {
  test('the sound button follows the mixer as well as the legacy layer', () {
    // The mixer follows the session's play/pause on its own.
    expect(
      isPlayerSoundActive(
        sessionPlaying: false,
        legacyAmbient: false,
        mixerPlaying: true,
      ),
      isTrue,
    );
    expect(
      isPlayerSoundActive(
        sessionPlaying: true,
        legacyAmbient: false,
        mixerPlaying: false,
      ),
      isFalse,
    );
    expect(
      isPlayerSoundActive(
        sessionPlaying: true,
        legacyAmbient: true,
        mixerPlaying: false,
      ),
      isTrue,
    );
  });

  testWidgets('a talk keeps the sound button; it opens the mixer drawer for '
      'the session and keeps what is left in it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view
      ..physicalSize = const Size(412, 915)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioStateProvider.overrideWith(AudioStateNotifier.new),
        // The session's scope, resolved before the player opens: a talk.
        cueScopeForRequestProvider(
          _talk,
        ).overrideWith((ref) async => const CueScope(CueKind.talks)),
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
          home: Scaffold(
            bottomNavigationBar: PlayerActionBar(
              request: _talk,
              isBackgroundSoundSelected: true,
              onSpeedChanged: (_) {},
              onClosePressed: () {},
            ),
          ),
        ),
      ),
    );
    final widget = tester.widget<BgSoundWidget>(find.byType(BgSoundWidget));
    expect(widget.isBackgroundSoundSelected, isTrue);
    expect(find.byIcon(Icons.music_off), findsNothing);

    await tester.tap(find.byType(BgSoundWidget));
    // The spinning record never settles: pump the drawer's opening instead.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The mixer as a drawer over the player, for this session's kind: a
    // talk, so "Plays under talks".
    expect(find.byType(SoundsView), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      tester.widget<SoundsView>(find.byType(SoundsView)).chooser?.kind,
      SoundscapeSessionKind.talks,
    );
    expect(find.text('Plays under talks'), findsOneWidget);

    // Choosing a preset auditions it and keeps it for talks.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('preset_starter-night')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const PageStorageKey('sounds_presets')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('preset_starter-night')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('sounds_chooser_done')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SoundsView), findsNothing);

    // Opened again during the talk, which then simply ends: the drawer
    // closes without a word over the end screen.
    final mixer = container.read(soundscapeProvider.notifier);
    await mixer.startSession(SoundscapeSessionKind.talks);
    await tester.tap(find.byType(BgSoundWidget));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SoundsView), findsOneWidget);
    mixer.endSession();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SoundsView), findsNothing);
    expect(
      find.text('The session changed, so the sound was left as it was.'),
      findsNothing,
    );
    expect(find.byType(SoundsView), findsNothing);
    final talks = container
        .read(soundscapeProvider)
        .sessionDefault(SoundscapeSessionKind.talks);
    expect(talks.enabled, isTrue);
    expect(talks.selection, const SoundscapeSelection.preset('starter-night'));
    // Nothing is left playing: no session is running in this test.
    expect(container.read(soundscapeProvider).playing, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  // One bar (owner, 2026-11-10): Close, Sound and Customize hold the same
  // places whatever is playing; Download and Speed only join a recording,
  // in the slots to their right.
  testWidgets('Sound and Customize sit at the same offsets for a timer and a '
      'recording', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view
      ..physicalSize = const Size(411, 890)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<Map<String, Offset>> slots(PlaybackRequest request) async {
      await tester.pumpWidget(
        ProviderScope(
          key: ValueKey(request.trackId),
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            audioStateProvider.overrideWith(AudioStateNotifier.new),
            ...soundscapeTestOverrides(FakeSoundscapeEngine()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              bottomNavigationBar: PlayerActionBar(
                request: request,
                isBackgroundSoundSelected: false,
                onSpeedChanged: (_) {},
                onClosePressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return {
        'close': tester.getCenter(find.byTooltip('Close')),
        'sound': tester.getCenter(find.byType(BgSoundWidget)),
        'customize': tester.getCenter(find.byTooltip('Customize')),
      };
    }

    final timer = await slots(
      timerPlaybackRequest(
        mode: TimerMode.countdown,
        duration: const Duration(minutes: 20),
        filePath: '/tmp/silence.mp3',
        title: 'Timer',
      ),
    );
    // A timer has nothing to download and no speed.
    expect(find.byType(AudioSpeedWidget), findsNothing);
    expect(find.byType(AudioDownloadWidget), findsNothing);

    final recording = await slots(
      _talk.copyWith(remoteUrl: 'https://example.org/talk.mp3'),
    );
    expect(recording, timer);

    // Left to right: Close, Sound, Customize, then the recording's own.
    final download = tester.getCenter(find.byType(AudioDownloadWidget)).dx;
    final speed = tester.getCenter(find.byType(AudioSpeedWidget)).dx;
    expect(timer['close']!.dx, lessThan(timer['sound']!.dx));
    expect(timer['sound']!.dx, lessThan(timer['customize']!.dx));
    expect(timer['customize']!.dx, lessThan(download));
    expect(download, lessThan(speed));
  });
}
