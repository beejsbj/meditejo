// Layout shots of presets (#64, #68) and of pinned presets on Home: Home
// with no, two and six pinned presets above pinned courses; the save sheet
// in its three places and on a loaded preset; Customize's presets line and
// the list it opens; the Sounds sheet's Presets shelf. At the S23+'s 411 dp
// light and dark, and a 360 x 640 dp phone at 2x text. Not part of the
// normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/presets_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/presets/save_preset_sheet.dart';
import 'package:medito/views/soundscape/sounds_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/library_app.dart';
import '../helpers/soundscape_fakes.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

const _bowl = 'assets/audio/bell_bowl_medium.wav';
const _gong = 'assets/audio/bell_gong.wav';
const _temple = 'assets/audio/bell_temple.wav';
const _heart = 'assets/audio/pulse_heartbeat.wav';
const _practice = CueScope(CueKind.practice);
const _talks = CueScope(CueKind.talks);

const _rain = SoundMix([
  SoundLayer(soundId: 'rain-terrace', volume: 0.7),
  SoundLayer(soundId: 'stream', volume: 0.4, animate: true),
]);
const _fire = SoundMix([SoundLayer(soundId: 'fire-stove', volume: 0.6)]);

/// The user's presets: a full sit, an open-ended one, a walk with a
/// rhythm, a sound alone, and one with a long name and a long length.
List<Preset> _mine() => [
  Preset.sound(id: 'user-rain', name: 'Evening rain', mix: _rain),
  Preset(
    id: 'user-walk',
    name: 'Walking',
    slots: PresetSlots(
      rhythm: PresetCues.rhythm(
        const CueSettings(pulseSound: _heart, pulseBpm: 54),
      ),
      length: const PresetLength.minutes(45),
    ),
  ),
  Preset(
    id: 'user-open',
    name: 'Open sit',
    slots: PresetSlots(
      bells: PresetCues.bells(
        const CueSettings(startSound: _gong, endSound: _gong),
      ),
      length: const PresetLength.openEnded(),
    ),
  ),
  Preset(
    id: 'user-retreat',
    name: 'Retreat afternoon, long sitting',
    slots: PresetSlots(
      sound: _fire,
      bells: PresetCues.bells(
        const CueSettings(
          startSound: _temple,
          endSound: _temple,
          intervalMinutes: 30,
        ),
      ),
      length: const PresetLength.minutes(90),
    ),
  ),
  Preset(
    id: 'user-morning',
    name: 'Morning sit',
    slots: PresetSlots(
      sound: _rain,
      bells: PresetCues.bells(
        const CueSettings(
          startSound: _bowl,
          endSound: _bowl,
          intervalHalfway: true,
        ),
      ),
      length: const PresetLength.minutes(20),
    ),
  ),
];

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

/// A phone size, a theme and a text size to shoot in.
typedef _Variant = (String name, Size dp, Brightness, double scale);

const _variants = <_Variant>[
  ('411-light', Size(411, 891), Brightness.light, 1),
  ('411-dark', Size(411, 891), Brightness.dark, 1),
  ('360-2x', Size(360, 640), Brightness.light, 2),
];

void _phone(WidgetTester tester, Size dp) {
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
}

late ProviderContainer _container;

/// A bare page under the app's theme, to open sheets over. [presets] and
/// [pinned] are what the user has.
Future<void> _pump(
  WidgetTester tester,
  _Variant v, {
  Widget home = const Scaffold(body: SizedBox.expand()),
  List<Preset>? presets,
  List<String> pinned = const [],
}) async {
  final (_, dp, brightness, scale) = v;
  _phone(tester, dp);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  SoundscapeStore(prefs)
    ..writePresets(presets ?? _mine())
    ..writePinnedPresets(pinned);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...soundscapeTestOverrides(FakeSoundscapeEngine()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meditejoTheme(brightness, IdentityPalettes.byId(null)),
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

BuildContext _page(WidgetTester tester) =>
    tester.element(find.byType(Scaffold).first);

Future<void> _openSave(WidgetTester tester, PresetContext place) async {
  showSavePresetSheet(_page(tester), place).ignore();
  await _settle(tester);
}

/// The Timer's Customize, as Home's Timer tile opens it.
Future<void> _openTimer(WidgetTester tester) async {
  showCustomizeModal<bool>(
    _page(tester),
    (_) => CustomizeSheet(
      scope: _practice,
      isTimer: true,
      onStart: () {},
      clock: () => DateTime(2026, 11, 11, 7, 0),
    ),
  ).ignore();
  await _settle(tester);
}

/// Customize before a 44-minute talk.
Future<void> _openTalk(WidgetTester tester) async {
  showCustomizeModal<bool>(
    _page(tester),
    (_) => CustomizeSheet(
      scope: _talks,
      audioDurationMs: 44 * 60000,
      onStart: () {},
      clock: () => DateTime(2026, 11, 11, 7, 0),
    ),
  ).ignore();
  await _settle(tester);
}

Future<void> _openList(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const ValueKey('customize_presets')));
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('customize_presets')));
  await _settle(tester);
}

Future<void> _pick(WidgetTester tester, String id) async {
  await _openList(tester);
  await tester.tap(find.byKey(ValueKey('preset_entry_$id')));
  await _settle(tester);
}

// --- Home -----------------------------------------------------------------

class _Course extends Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) => AsyncData(
    PackModel(
      id: packId,
      title: 'Practising the Jhānas: a retreat with Rob Burbea',
      items: [
        for (var i = 0; i < 32; i++)
          PackItemsModel(
            type: 'track',
            id: '$packId-$i',
            title: 'Session ${i + 1}',
            path: '/tracks/$packId-$i',
            isCompleted: i < 9,
          ),
      ],
    ),
  );
}

class _Talk extends Tracks {
  @override
  Future<Track> build({required String trackId}) async => Track(
    id: trackId,
    title: 'Equanimity and the end of preferences',
    subtitle: 'Talk · Ajahn Sucitto · 42 min',
    description: '',
    coverUrl: '',
    isPublished: true,
    hasBackgroundSound: false,
    voices: const [
      TrackVoice(
        audioFiles: [TrackAudioFile(id: 'f', path: 'f.mp3', duration: 1)],
      ),
    ],
  );
}

final _continue = ContinueItem(
  trackId: 'jhana-9',
  path: '/tracks/jhana-9',
  title: 'The fourth jhāna, and letting the mind rest there',
  group: LibraryGroup.practice,
  lastPlayed: DateTime(2026, 11, 10),
  courseId: 'jhana',
  courseTitle: 'Practising the Jhānas',
  completedSessions: 9,
  sessionNumber: 10,
  sessionTotal: 32,
  resume: const ResumePoint(positionMs: 12 * 60000, durationMs: 40 * 60000),
);

const _nav = [
  MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
  MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
  MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
  MeditoNavItem(icon: Symbols.settings_rounded, label: 'Settings'),
];

Future<void> _pumpHome(
  WidgetTester tester,
  _Variant v, {
  required List<String> pinned,
}) async {
  final (_, dp, brightness, scale) = v;
  final app = await LibraryTestApp.create(tester);
  SoundscapeStore(app.prefs)
    ..writePresets(_mine())
    ..writePinnedPresets(pinned);
  await app.prefs.setStringList('pinned_course_ids', ['jhana', 'talk-1']);
  await app.prefs.setStringList('pinned_session_ids', ['talk-1']);
  await app.pump(
    tester,
    Theme(
      data: meditejoTheme(brightness, IdentityPalettes.byId(null)),
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: const HomeView(),
            bottomNavigationBar: MeditoNavBar(
              items: _nav,
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    ),
    overrides: [
      continueItemsProvider.overrideWith((ref) async => [_continue]),
      packProvider(packId: 'jhana').overrideWith(_Course.new),
      tracksProvider(trackId: 'talk-1').overrideWith(_Talk.new),
      ...soundscapeTestOverrides(FakeSoundscapeEngine()),
    ],
  );
  _phone(tester, dp);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  for (final v in _variants) {
    final name = v.$1;

    // Nothing, two, and six presets pinned (four show; See all has the
    // rest), each above a pinned course and a pinned talk.
    for (final (count, pinned) in [
      (0, <String>[]),
      (2, ['user-morning', 'starter-rain-forest']),
      (
        6,
        [
          'user-morning',
          'user-open',
          'user-retreat',
          'user-walk',
          'user-rain',
          'starter-night',
        ],
      ),
    ]) {
      testWidgets('Home with $count pinned presets, $name', (tester) async {
        await _pumpHome(tester, v, pinned: pinned);
        await _shoot(tester, 'presets-home-$count-$name');
        // The whole page.
        tester.view.physicalSize = Size(v.$2.width, 1500) * 2.625;
        await _settle(tester);
        await _shoot(tester, 'presets-home-$count-full-$name');
      }, skip: !_enabled);
    }

    testWidgets('Pinned list with presets, $name', (tester) async {
      await _pumpHome(
        tester,
        v,
        pinned: [for (final p in _mine()) p.id, 'starter-night'],
      );
      final seeAll = find.byKey(const ValueKey('pinned_see_all'));
      await tester.ensureVisible(seeAll);
      await tester.pump();
      await tester.tap(seeAll);
      await _settle(tester);
      await _shoot(tester, 'presets-pinned-list-$name');
    }, skip: !_enabled);

    testWidgets('Save sheet from the Timer, $name', (tester) async {
      await _pump(tester, v, presets: const []);
      await _container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            const CueSettings(
              durationMinutes: 25,
              startSound: _bowl,
              endSound: _bowl,
              intervalHalfway: true,
            ),
          );
      _container
          .read(soundscapeProvider.notifier)
          .setSessionChoice(
            SoundscapeSessionKind.practice,
            const SoundscapeSelection.preset('starter-rain-forest'),
          );
      await _openSave(tester, const PresetContext.timer());
      await tester.enterText(
        find.byKey(const ValueKey('preset_name')),
        'Morning sit',
      );
      await _settle(tester);
      await _shoot(tester, 'presets-save-timer-$name');
    }, skip: !_enabled);

    testWidgets('Save sheet under a recording, $name', (tester) async {
      await _pump(tester, v, presets: const []);
      await _container
          .read(cueSettingsProvider(_talks).notifier)
          .update(const CueSettings(startSound: '', endSound: _gong));
      await _openSave(tester, const PresetContext.session(_talks));
      await tester.enterText(
        find.byKey(const ValueKey('preset_name')),
        'Talks',
      );
      await _settle(tester);
      await _shoot(tester, 'presets-save-recording-$name');
    }, skip: !_enabled);

    testWidgets('Save sheet from Sounds, $name', (tester) async {
      await _pump(tester, v, home: const SoundsView(), presets: const []);
      final mixer = _container.read(soundscapeProvider.notifier);
      mixer.toggleSound('river');
      mixer.toggleSound('wind-trees');
      await _settle(tester);
      await _shoot(tester, 'presets-sounds-unsaved-$name');
      await _openSave(tester, const PresetContext.sounds());
      await _shoot(tester, 'presets-save-sounds-$name');
      mixer.stop();
      await _settle(tester);
    }, skip: !_enabled);

    // Morning sit, loaded in the Sounds sheet and changed: Update writes
    // its sound and keeps the rest.
    testWidgets('Save sheet on a loaded preset, $name', (tester) async {
      await _pump(tester, v, home: const SoundsView());
      final mixer = _container.read(soundscapeProvider.notifier);
      await applyPreset(_container, const PresetContext.sounds(), _mine().last);
      await _settle(tester);
      mixer.toggleSound('forest-birds');
      await _settle(tester);
      await _shoot(tester, 'presets-sounds-edited-$name');
      await _openSave(tester, const PresetContext.sounds());
      await _shoot(tester, 'presets-save-update-$name');
      mixer.stop();
      await _settle(tester);
    }, skip: !_enabled);

    testWidgets('Sounds sheet presets shelf, $name', (tester) async {
      await _pump(tester, v, home: const SoundsView());
      // The user's own are after the five that ship.
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('preset_user-morning')),
        find.byKey(const PageStorageKey('sounds_presets')),
        const Offset(-200, 0),
      );
      await tester.drag(
        find.byKey(const PageStorageKey('sounds_presets')),
        const Offset(-120, 0),
      );
      await _settle(tester);
      await _shoot(tester, 'presets-sounds-shelf-$name');
      await tester.tap(find.byKey(const ValueKey('preset_menu_user-morning')));
      await _settle(tester);
      await _shoot(tester, 'presets-sounds-actions-$name');
    }, skip: !_enabled);

    testWidgets('Customize presets on the Timer, $name', (tester) async {
      await _pump(tester, v);
      await _openTimer(tester);
      await _shoot(tester, 'presets-customize-none-$name');
      await _openList(tester);
      await _shoot(tester, 'presets-picker-timer-$name');
      await tester.tap(find.byKey(const ValueKey('preset_entry_user-morning')));
      await _settle(tester);
      await _shoot(tester, 'presets-customize-loaded-$name');
      await _container
          .read(cueSettingsProvider(_practice).notifier)
          .update(
            _container
                .read(cueSettingsProvider(_practice))
                .copyWith(durationMinutes: 30),
          );
      await _settle(tester);
      await _shoot(tester, 'presets-customize-edited-$name');
      await _openList(tester);
      await _shoot(tester, 'presets-picker-timer-loaded-$name');
    }, skip: !_enabled);

    testWidgets('Customize presets under a recording, $name', (tester) async {
      await _pump(tester, v);
      await _openTalk(tester);
      await _pick(tester, 'user-morning');
      await _shoot(tester, 'presets-customize-recording-$name');
      await _openList(tester);
      await _shoot(tester, 'presets-picker-recording-$name');
    }, skip: !_enabled);
  }

  test('the presets that ship are what the shots assume', () {
    expect(kStarterPresets.map((p) => p.id), contains('starter-night'));
  });
}
