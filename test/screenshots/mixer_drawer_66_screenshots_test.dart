// Layout shots for #66: each way into choosing sounds (the Sounds tab's
// "under sessions" lines, the player's Sounds button, Customize › Sound and
// the Timer's Sound tile), at the S23+'s 411 dp light and dark, and a 360 dp
// phone in German with 1.3x text. Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/mixer_drawer_66_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/soundscape_fakes.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

/// Practice plays the Night preset under it; talks play nothing.
const _prefs = <String, Object>{
  'soundscape_session_defaults':
      '{"practice":{"enabled":true,"selection":"preset:starter-night",'
      '"volume":0.5},"talks":{"enabled":false,"selection":"mix",'
      '"volume":0.35}}',
  'soundscape_session_defaults_version': 2,
};

/// A 20-minute timer, playing.
const _timer = PlaybackRequest(
  trackId: 'timer-1200',
  fileId: 'timer-countdown-1200',
  title: 'Timer',
  description: '',
  coverUrl: '',
  remoteUrl: '/local/timer.wav',
  duration: 20 * 60000,
  hasBackgroundSound: true,
);

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
  final symbols =
      FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      );
  await symbols.load();
}

/// A phone size, a theme and a language to shoot in.
typedef _Variant = (String name, double dp, Brightness, double scale, Locale);

const _variants = <_Variant>[
  ('411-light', 411, Brightness.light, 1, Locale('en')),
  ('411-dark', 411, Brightness.dark, 1, Locale('en')),
  ('360-de', 360, Brightness.light, 1.3, Locale('de')),
];

Future<void> _pump(WidgetTester tester, _Variant v, Widget home) async {
  final (_, dp, brightness, scale, locale) = v;
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = Size(dp * 2.625, (dp == 411 ? 891 : 780) * 2.625);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(_prefs);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        audioStateProvider.overrideWith(AudioStateNotifier.new),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meditejoTheme(brightness, IdentityPalettes.byId(null)),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await _settle(tester);
}

/// Lets generated art and route transitions finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Everything on screen, including a sheet above the page.
Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var render = tester.element(find.byType(Navigator).first).renderObject!;
    while (!render.isRepaintBoundary) {
      render = render.parent!;
    }
    final layer = render.debugLayer! as OffsetLayer;
    final image = await layer.toImage(render.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _tapSlot(WidgetTester tester, String slot) async {
  final tile = find.byKey(ValueKey('customize_slot_$slot'));
  await tester.ensureVisible(tile);
  await tester.pump();
  await tester.tap(tile);
  await _settle(tester);
}

void main() {
  setUpAll(_loadFonts);

  for (final v in _variants) {
    final name = v.$1;

    testWidgets('mixer 66 sounds tab, $name', (tester) async {
      await _pump(tester, v, const SoundsView());
      final under = find.byKey(const ValueKey('under_practice'));
      await tester.scrollUntilVisible(
        under,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('sounds_library')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.byKey(const PageStorageKey('sounds_library')),
        const Offset(0, -300),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'sounds-tab-$name');
    }, skip: !_enabled);

    testWidgets('mixer 66 player, $name', (tester) async {
      await _pump(
        tester,
        v,
        const Scaffold(
          backgroundColor: Color(0xFF1B1D1F),
          bottomNavigationBar: PlayerActionBar(
            request: _timer,
            isBackgroundSoundSelected: false,
            onSpeedChanged: _noSpeed,
            onClosePressed: _noClose,
          ),
        ),
      );
      await tester.tap(find.byType(BgSoundWidget));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'player-$name');
    }, skip: !_enabled);

    // Clear's toast sits above the docked bar, on the tab and in the drawer.
    for (final drawer in [false, true]) {
      testWidgets('mixer 66 clear toast ${drawer ? 'drawer' : 'tab'}, $name', (
        tester,
      ) async {
        if (drawer) {
          await _pump(
            tester,
            v,
            const Scaffold(
              backgroundColor: Color(0xFF1B1D1F),
              bottomNavigationBar: PlayerActionBar(
                request: _timer,
                isBackgroundSoundSelected: false,
                onSpeedChanged: _noSpeed,
                onClosePressed: _noClose,
              ),
            ),
          );
          await tester.tap(find.byType(BgSoundWidget));
          await _settle(tester);
        } else {
          await _pump(tester, v, const SoundsView());
        }
        final mixer = ProviderScope.containerOf(
          tester.element(find.byType(SoundsView)),
        ).read(soundscapeProvider.notifier);
        if (ProviderScope.containerOf(
          tester.element(find.byType(SoundsView)),
        ).read(soundscapeProvider).mix.isEmpty) {
          mixer.toggleSound(kSynthNoiseId);
        }
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
        await _settle(tester);
        await tester.tap(find.byKey(const ValueKey('sounds_clear')));
        await _settle(tester);
        // Folded again, as in the report: the bar is what it covered.
        await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(
          // The toast's own surface: the SnackBar's box includes its margin.
          tester
              .getRect(
                find
                    .descendant(
                      of: find.byType(SnackBar),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('sounds_dock'))).top,
          ),
        );
        await _shoot(tester, 'clear-toast-${drawer ? 'drawer' : 'tab'}-$name');
      }, skip: !_enabled);
    }

    testWidgets('mixer 66 customize, $name', (tester) async {
      await _pump(
        tester,
        v,
        const Scaffold(
          body: SafeArea(
            child: CustomizeSheet(scope: CueScope(CueKind.practice)),
          ),
        ),
      );
      await _tapSlot(tester, 'sound');
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'customize-$name');
    }, skip: !_enabled);

    testWidgets('mixer 66 timer, $name', (tester) async {
      await _pump(tester, v, const TimerView());
      await _tapSlot(tester, 'sound');
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'timer-$name');
    }, skip: !_enabled);
  }
}

void _noSpeed(double _) {}
void _noClose() {}
