import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/background_sound/background_sound_view.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
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

  testWidgets('a talk keeps the sound button and it opens the Sounds sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
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
    // The spinning record never settles: pump the sheet's opening instead.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(BackgroundSoundView), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
