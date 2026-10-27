// The player over generated art, for the art PR's screenshots. Off by
// default; written to docs/fork/design/art/<palette>/:
//
//     MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_PALETTE=tide \
//       MEDITEJO_SHOT_DIR=docs/fork/design/art/tide \
//       flutter test test/screenshots/art_player_screenshots_test.dart
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart' as model;
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';
final _out =
    Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design/art/tide';
final _palette = IdentityPalettes.byId(
  Platform.environment['MEDITEJO_SHOT_PALETTE'],
);

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  // The tester runs from bin/cache/artifacts/engine/<host>/ in the SDK.
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
  // The tab bar's and the Sounds screen's Material Symbols.
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

final _boundary = GlobalKey();

const _credit = SourceAttribution(
  source: 'Dharma Seed',
  creator: 'Rob Burbea',
  url: 'https://dharmaseed.org/talks/2/',
  licenseName: 'CC BY-NC-ND 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
);

PlaybackRequest _request({
  SourceAttribution? attribution,
  String coverUrl = '',
}) => PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: coverUrl,
  remoteUrl: 'https://dharmaseed.org/talks/2/file.mp3',
  duration: 3600000,
  hasBackgroundSound: false,
  guideName: 'Rob Burbea',
  artist: const model.TrackArtist(
    name: 'Rob Burbea',
    path: 'https://dharmaseed.org/talks/2/',
  ),
  attribution: attribution,
);

/// A player with nothing playing yet: not completed, at the start.
class _IdleAudio extends AudioStateNotifier {
  @override
  pigeon.PlaybackState build() => pigeon.PlaybackState(
    isPlaying: false,
    isBuffering: false,
    isSeeking: false,
    isCompleted: false,
    position: 0,
    duration: 3600000,
    speed: pigeon.Speed(speed: 1),
    volume: 100,
    track: pigeon.Track(
      id: 'ds-talk-2',
      title: '',
      fileId: '',
      description: '',
      imageUrl: '',
      artist: '',
    ),
  );
}

class _FakePlayer extends PlayerProvider {
  _FakePlayer(this.request);

  final PlaybackRequest request;

  @override
  PlaybackRequest? build() => request;

  @override
  Future<void> play(PlaybackRequest request) => Completer<void>().future;

  @override
  void stop() {}

  @override
  void setSpeed(double speed) {}
}

class _SilentBackgroundSounds extends BackgroundSoundsNotifier {
  @override
  void stopBackgroundSound() {}

  @override
  void playBackgroundSoundFromPref() {}
}

class _Stats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => previewStats;
}

class _Review implements ReviewService {
  @override
  Future<bool> onHappyFeedback({bool suppress = false}) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 0,
        );
    await _loadFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('the player over its art, ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: PreviewShell(
            prefs: brightness == Brightness.dark ? prefsDark : prefsLight,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            overrides: [
              playerProvider.overrideWith(
                () => _FakePlayer(_request(attribution: _credit)),
              ),
              audioStateProvider.overrideWith(_IdleAudio.new),
              backgroundSoundsNotifierProvider.overrideWith(
                _SilentBackgroundSounds.new,
              ),
              statsProvider.overrideWith(_Stats.new),
              reviewServiceProvider.overrideWithValue(_Review()),
            ],
            child: Builder(
              builder: (context) => Theme(
                data: meditejoTheme(brightness, _palette),
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: const PlayerView(skipCustomize: true),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        final render =
            _boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2.625);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/player-${brightness.name}.png')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
