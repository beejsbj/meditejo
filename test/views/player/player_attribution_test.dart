import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart' as model;
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/review_service_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/review_service.dart';
import 'package:medito/src/audio_pigeon.g.dart' as pigeon;
import 'package:medito/views/home/previews/stats_fixtures.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/generated_artwork.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _credit = SourceAttribution(
  source: 'Dharma Seed',
  creator: 'Rob Burbea',
  url: 'https://dharmaseed.org/talks/2/',
  licenseName: 'CC BY-NC-ND 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-nc-nd/4.0/',
);

PlaybackRequest _request({SourceAttribution? attribution}) => PlaybackRequest(
  trackId: 'ds-talk-2',
  fileId: 'ds-talk-2',
  title: 'Jhana basics',
  description: '',
  coverUrl: '',
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

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => 0,
        );
  });

  Future<void> pumpPlayer(
    WidgetTester tester,
    PlaybackRequest request,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      PreviewShell(
        prefs: prefsDark,
        overrides: [
          playerProvider.overrideWith(() => _FakePlayer(request)),
          audioStateProvider.overrideWith(_IdleAudio.new),
          backgroundSoundsNotifierProvider.overrideWith(
            _SilentBackgroundSounds.new,
          ),
          statsProvider.overrideWith(_Stats.new),
          reviewServiceProvider.overrideWithValue(_Review()),
        ],
        child: const PlayerView(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the player credits the teacher, the source and the licence', (
    tester,
  ) async {
    await pumpPlayer(
      tester,
      _request(attribution: _credit),
      const Size(430, 900),
    );

    expect(find.byType(AttributionNotice), findsOneWidget);
    expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
    expect(find.text('CC BY-NC-ND 4.0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the credit fits a landscape phone too', (tester) async {
    await pumpPlayer(
      tester,
      _request(attribution: _credit),
      const Size(900, 400),
    );

    expect(find.text('Rob Burbea · Dharma Seed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('a track with no licence shows no credit line', (tester) async {
    await pumpPlayer(tester, _request(), const Size(430, 900));
    expect(find.byType(AttributionNotice), findsNothing);
    await close(tester);
  });

  testWidgets('a track with no cover gets its generated art behind it', (
    tester,
  ) async {
    await pumpPlayer(tester, _request(), const Size(430, 900));
    expect(find.byType(GeneratedArtwork), findsOneWidget);
    await close(tester);
  });

  test('a talk reaches the player with its credit unchanged', () {
    final track = DharmaSeedSource.mapTalk(
      DsTalkWithTeacher(
        const DsTalk(
          id: 2,
          title: 'Jhana basics',
          description: '',
          teacherId: 1,
          retreatId: 100,
          audioUrl: '/talks/2/file.mp3',
          durationMs: 3600000,
          recDate: '2014-03-01 20:00:00',
          recordingType: 'Talk',
          updatedAt: '',
        ),
        const DsTeacher(
          id: 1,
          name: 'Rob Burbea',
          bio: '',
          photo: '',
          website: '',
          monastic: false,
          isPublic: true,
          updatedAt: '',
        ),
      ),
    );
    final request = PlaybackRequest.fromTrack(
      track,
      track.voices.single,
      track.voices.single.audioFiles.single,
    );
    expect(request.attribution, track.attribution);
    expect(request.attribution?.licenseName, 'CC BY-NC-ND 4.0');
    expect(request.remoteUrl, startsWith('https://dharmaseed.org/'));
  });
}
