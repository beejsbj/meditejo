// Layout shots of the Sounds sheet (a sheet since 2026-11-10; #66's drawer
// before): from Home's tile on your own mix (idle, playing, its foot, turned
// to what plays under practice), from the player in a session, from
// Customize and the Timer, a sound's editor with the equaliser open, Clear's
// toast above the dock, and the four-tab bar with Home's Sounds tile. At the
// S23+'s 411 dp light and dark (with its system bars' insets), and a
// 360 x 640 dp phone at 2x text. Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/sounds_sheet_screenshots_test.dart
import 'dart:async';
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
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/bg_sound_widget.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/home/widgets/shortcuts/shortcuts_section.dart';
import 'package:medito/views/home/widgets/shortcuts/sounds_shortcut_tile.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:medito/views/soundscape/synth_editors.dart';
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

/// A phone size, a theme, a text size and a language to shoot in.
typedef _Variant = (
  String name,
  Size dp,
  Brightness,
  double scale,
  Locale locale,
);

const _variants = <_Variant>[
  ('411-light', Size(411, 891), Brightness.light, 1, Locale('en')),
  ('411-dark', Size(411, 891), Brightness.dark, 1, Locale('en')),
  ('360-2x', Size(360, 640), Brightness.light, 2, Locale('en')),
  ('360-de', Size(360, 780), Brightness.light, 1.3, Locale('de')),
];

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, _Variant v, Widget home) async {
  final (_, dp, brightness, scale, locale) = v;
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = dp * 2.625;
  // The status bar and the gesture bar of the S23+.
  tester.view.padding = const FakeViewPadding(
    top: 32 * 2.625,
    bottom: 24 * 2.625,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: 32 * 2.625,
    bottom: 24 * 2.625,
  );
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
  _container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
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
  expect(tester.takeException(), isNull);
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

/// Opens the Sounds sheet from the Customize sheet's Sound button.
Future<void> _tapSound(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('customize_sound'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button);
  await _settle(tester);
}

/// The four tabs under a page that holds Home's Sounds tile, as Home does
/// (two tiles across).
class _HomeStandIn extends StatelessWidget {
  const _HomeStandIn();

  static const _nav = [
    MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
    MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
    MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
    MeditoNavItem(icon: Symbols.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      bottomNavigationBar: MeditoNavBar(
        items: _nav,
        selectedIndex: 0,
        onSelected: (_) {},
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 12) / 2;
              final height = 56 + MediaQuery.textScalerOf(context).scale(44);
              Widget cell(Widget tile) => SizedBox(
                width: width,
                height: height < 116 ? 116 : height,
                child: tile,
              );
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  cell(
                    ShortcutTile(
                      color: scheme.secondaryContainer,
                      onColor: scheme.onSecondaryContainer,
                      icon: (color) =>
                          Icon(Symbols.timer_rounded, color: color),
                      label: 'Timer',
                      caption: '20 min',
                      onTap: () {},
                    ),
                  ),
                  cell(
                    const SoundsShortcutTile(key: ValueKey('shortcut_sounds')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

const _player = Scaffold(
  backgroundColor: Color(0xFF1B1D1F),
  bottomNavigationBar: PlayerActionBar(
    request: _timer,
    isBackgroundSoundSelected: false,
    onSpeedChanged: _noSpeed,
    onClosePressed: _noClose,
  ),
);

Finder get _library => find
    .descendant(
      of: find.byKey(const PageStorageKey('sounds_library')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _openFromTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('shortcut_sounds')));
  await _settle(tester);
}

Future<void> _tapPreset(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('preset_$id')));
  await _settle(tester);
}

void main() {
  setUpAll(_loadFonts);

  for (final v in _variants) {
    final name = v.$1;

    testWidgets('sounds sheet tabs and tile, $name', (tester) async {
      await _pump(tester, v, const _HomeStandIn());
      await _shoot(tester, 'tabs-tile-idle-$name');
      // A mix started in the sheet, which is then closed: the tile says so.
      await _openFromTile(tester);
      await _tapPreset(tester, 'starter-rain-forest');
      await tester.tap(find.byKey(const ValueKey('sounds_chooser_done')));
      await _settle(tester);
      expect(_container.read(soundscapeProvider).playing, isTrue);
      await _shoot(tester, 'tabs-tile-playing-$name');
    }, skip: !_enabled);

    testWidgets('sounds sheet from Home, $name', (tester) async {
      await _pump(tester, v, const _HomeStandIn());
      await _openFromTile(tester);
      await _shoot(tester, 'home-idle-$name');

      await _tapPreset(tester, 'starter-rain-forest');
      await _shoot(tester, 'home-playing-$name');

      await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
      await _settle(tester);
      await _shoot(tester, 'home-mix-open-$name');
      await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
      await _settle(tester);

      // Its foot: what plays under practice and talks, and the credits.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sound_credits_footer')),
        300,
        scrollable: _library,
      );
      await tester.drag(_library, const Offset(0, -400));
      await _settle(tester);
      await _shoot(tester, 'home-foot-$name');

      // Turned to what plays under practice (Night, here): the same sheet.
      await tester.tap(find.byKey(const ValueKey('under_practice')));
      await _settle(tester);
      await _shoot(tester, 'home-practice-$name');
    }, skip: !_enabled);

    testWidgets('sounds sheet in a session, $name', (tester) async {
      await _pump(tester, v, _player);
      await _container
          .read(soundscapeProvider.notifier)
          .startSession(SoundscapeSessionKind.practice);
      await _settle(tester);
      await tester.tap(find.byType(BgSoundWidget));
      await _settle(tester);
      await _shoot(tester, 'session-$name');
      // Clear from the folded dock, as in the owner's report.
      await tester.tap(find.byKey(const ValueKey('sounds_clear')));
      await _settle(tester);
      _expectToastAboveDock(tester);
      await _shoot(tester, 'session-cleared-$name');
    }, skip: !_enabled);

    // Clear's toast sits above the docked bar.
    testWidgets('sounds sheet clear toast, $name', (tester) async {
      await _pump(tester, v, const _HomeStandIn());
      await _openFromTile(tester);
      await _tapPreset(tester, 'starter-rain-forest');
      await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('sounds_clear')));
      await _settle(tester);
      await _shoot(tester, 'clear-toast-open-$name');
      // Folded again, as in the report: the bar is what it covered.
      await tester.tap(find.byKey(const ValueKey('sounds_mix_toggle')));
      await _settle(tester);
      _expectToastAboveDock(tester);
      await _shoot(tester, 'clear-toast-$name');
    }, skip: !_enabled);

    testWidgets('sounds sheet noise editor, $name', (tester) async {
      await _pump(tester, v, const _HomeStandIn());
      await _openFromTile(tester);
      final mixer = _container.read(soundscapeProvider.notifier)
        ..clearMix()
        ..toggleSound(kSynthNoiseId);
      mixer.setLayerParams(
        kSynthNoiseId,
        const NoiseParams(
          bands: [0.35, 0.5, 0.7, 0.9, 1, 1, 0.8, 0.55, 0.4, 0.3],
        ).toJson(),
      );
      await _settle(tester);
      unawaited(
        showSynthEditor(tester.element(find.byType(SoundsView)), kSynthNoiseId),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('noise_bands_fold')));
      await _settle(tester);
      await _shoot(tester, 'editor-eq-$name');
      await tester.ensureVisible(
        find.byKey(const ValueKey('noise_bands_reset')),
      );
      await tester.tap(find.byKey(const ValueKey('noise_bands_reset')));
      await _settle(tester);
      await _shoot(tester, 'editor-eq-flat-$name');
    }, skip: !_enabled);

    testWidgets('sounds sheet customize, $name', (tester) async {
      await _pump(
        tester,
        v,
        const Scaffold(
          body: SafeArea(
            child: CustomizeSheet(scope: CueScope(CueKind.practice)),
          ),
        ),
      );
      await _tapSound(tester);
      await _shoot(tester, 'customize-$name');
    }, skip: !_enabled);

    testWidgets('sounds sheet timer, $name', (tester) async {
      await _pump(
        tester,
        v,
        Scaffold(
          body: SafeArea(
            child: CustomizeSheet(
              scope: const CueScope(CueKind.practice),
              isTimer: true,
              onStart: () {},
            ),
          ),
        ),
      );
      await _tapSound(tester);
      await _shoot(tester, 'timer-$name');
    }, skip: !_enabled);
  }
}

void _expectToastAboveDock(WidgetTester tester) => expect(
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

void _noSpeed(double _) {}
void _noClose() {}
