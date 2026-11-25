// Layout shots for #75's per-kind playback speed: the player's speed sheet
// during a talk (talks at 1.5×, practice at 1×), the same sheet turned to
// Practice, and the Settings row. At the S23+'s 411 dp light and dark, and a
// 360 dp phone in German with 1.3× text. Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/speed_75_screenshots_test.dart
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
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/audio_speed_widget.dart';
import 'package:medito/views/settings/widgets/practice_default_tiles.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/soundscape_fakes.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

/// Talks are listened to at 1.5×; practice stays at 1×.
const _prefs = <String, Object>{'speed.v1.talks': 1.5};

const _talk = PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://dharmaseed.org/talks/2/file.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
  guideName: 'Rob Burbea',
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
        cueScopeForRequestProvider.overrideWith(
          (ref, request) async => const CueScope(CueKind.talks),
        ),
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

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

const _player = Scaffold(
  backgroundColor: Color(0xFF1B1D1F),
  bottomNavigationBar: PlayerActionBar(
    request: _talk,
    isBackgroundSoundSelected: false,
    onSpeedChanged: _noSpeed,
    onClosePressed: _noClose,
  ),
);

void main() {
  setUpAll(_loadFonts);

  for (final v in _variants) {
    final name = v.$1;

    testWidgets('speed 75 sheet during a talk, $name', (tester) async {
      await _pump(tester, v, _player);
      await tester.tap(find.byType(AudioSpeedWidget));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'speed-talk-$name');
    }, skip: !_enabled);

    testWidgets('speed 75 sheet turned to practice, $name', (tester) async {
      await _pump(tester, v, _player);
      await tester.tap(find.byType(AudioSpeedWidget));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('speed_kind_practice')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'speed-practice-$name');
    }, skip: !_enabled);

    testWidgets('speed 75 settings row, $name', (tester) async {
      await _pump(
        tester,
        v,
        const Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                CueDefaultsTile(kind: CueKind.practice),
                CueDefaultsTile(kind: CueKind.talks),
                PlaybackSpeedTile(hasUnderline: false),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'settings-$name');
    }, skip: !_enabled);
  }
}

void _noSpeed(double _) {}
void _noClose() {}
