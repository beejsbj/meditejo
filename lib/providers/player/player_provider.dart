import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/services/audio/native_cue_controller.dart';
import 'package:medito/models/pauses/pause_hold.dart';
import 'package:medito/services/pauses/pause_map_service.dart';
import 'package:medito/services/stats/session_label.dart';
import 'package:medito/providers/library/library_providers.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/models.dart';
import 'package:medito/models/timer/timer_session.dart';

import '../../models/player/repeat_mode.dart' as app_repeat;
import '../../src/audio_pigeon.g.dart' as pigeon;
import '../../utils/utils.dart';
import 'audio_state_provider.dart';
import 'download/audio_downloader_provider.dart';
import 'ios_audio_handler.dart';
import 'repeat_state_provider.dart';
import '../../utils/logger.dart';

final _api = pigeon.MeditoAudioServiceApi();
final _androidServiceApi = pigeon.MeditoAndroidAudioServiceManager();
late IosAudioHandler iosAudioHandler;

final playerProvider = NotifierProvider<PlayerProvider, PlaybackRequest?>(() {
  return PlayerProvider();
});

class PlayerProvider extends Notifier<PlaybackRequest?> {
  int _generation = 0;
  @override
  PlaybackRequest? build() => null;

  /// Starts (or restarts) playback for [request]. The provider's state holds
  /// the same [PlaybackRequest] for the lifetime of the session so the player
  /// UI never has to inspect a nested track graph to know what is playing.
  ///
  /// Throws on failure to start playback (e.g. native audio service didn't
  /// start, ExoPlayer threw, iOS audio session couldn't be configured).
  /// Callers MUST wrap in try/catch and surface the failure to the user —
  /// otherwise we end up navigating to a player screen with no audio (silent
  /// failure that looks like a broken app).
  Future<void> play(PlaybackRequest request) async {
    AppLogger.d(
      'PLAYER',
      'Loading track: ${request.title}, fileId: ${request.fileId}',
    );

    // The audio state outlives sessions; drop the previous track's (possibly
    // completed, full-position) values so nothing reads them as this one's.
    final generation = ++_generation;
    ref.read(audioStateProvider.notifier).resetState();
    await _playTrack(request, generation);
    if (generation != _generation) return;
    // Resuming: the player is already preparing the file, and a seek issued
    // now is applied as soon as it is ready.
    if (request.startPositionMs > 0) {
      await seekToPosition(request.startPositionMs);
    }
    state = request;
  }

  /// Sets the current request WITHOUT starting playback, so the player screen
  /// can be pushed immediately and render its title/cover/duration from this
  /// request while the audio loads. [PlayerView] then calls [play] itself.
  /// Also used to warm-prepare next-up tracks.
  ///
  /// Compares the whole request (not just trackId) so switching voice or
  /// duration on the same track still updates the pending file.
  void prepare(PlaybackRequest request) {
    if (state == request) return;
    state = request;
  }

  CueSettings? _cues;

  /// Where the current recording can be read for pauses: a path on the phone,
  /// or a URL (fetched only on an unmetered connection). Set by [_playTrack].
  String? _analysisSource;

  /// The recording whose pause map a configure is waiting for.
  String? _waitingForMap;

  Future<void> updateCueSettings(CueSettings settings) async {
    _cues = settings;
    final request = state;
    if (request == null) return;
    if (Platform.isAndroid || Platform.isIOS) {
      final holds = await _holdsFor(settings, request);
      // Edits that came while the holds were worked out are newer: theirs win.
      if (!identical(_cues, settings)) return;
      await NativeCueController.configure(
        settings,
        request,
        update: true,
        holds: holds,
      );
    }
  }

  /// Extend's holds for [request]: in its pauses when the setting says so and
  /// the recording has been read. Without a pause map the silence all goes to
  /// the end, and the reading starts in the background; when it lands the
  /// native cues are configured again with the holds that follow from it.
  Future<List<PauseHold>> _holdsFor(
    CueSettings settings,
    PlaybackRequest request,
  ) async {
    final source = _analysisSource;
    if (!Platform.isAndroid ||
        !settings.extendInPauses ||
        settings.extendMinutes <= 0 ||
        request.isTimer ||
        source == null ||
        !PauseMapService.canAnalyse(request.trackId, source)) {
      return const [];
    }
    final service = ref.read(pauseMapServiceProvider);
    final key = PauseMapService.keyFor(request.trackId, request.fileId);
    final map = await service.cached(key, durationMs: request.duration);
    if (map != null) {
      return PauseMapService.holdsFor(map, settings.extendMinutes);
    }
    // One waiter per recording, however many settings edits ask meanwhile.
    if (_waitingForMap == key) return const [];
    _waitingForMap = key;
    unawaited(
      service.analyse(key, source).then((found) async {
        if (_waitingForMap == key) _waitingForMap = null;
        if (found == null) return;
        // The session may have moved on, or the setting been turned off. A
        // restart of the same recording is still the one waiting for it.
        final current = _cues;
        final live = state;
        if (current == null ||
            live == null ||
            live.trackId != request.trackId ||
            !current.extendInPauses) {
          return;
        }
        try {
          await NativeCueController.configure(
            current,
            live,
            update: true,
            holds: PauseMapService.holdsFor(found, current.extendMinutes),
          );
        } catch (e) {
          AppLogger.w('PLAYER', 'Could not apply the pause map: $e');
        }
      }),
    );
    return const [];
  }

  Future<void> _playTrack(PlaybackRequest request, int generation) async {
    final scope = await ref.read(cueScopeForRequestProvider(request).future);
    if (generation != _generation) return;
    // The stats page counts this session as the same kind, in the same
    // course, as the cues treat it.
    SessionLabelRegistry.remember(
      request.trackId,
      kind: scope.kind.name,
      courseId: scope.courseId,
    );
    _cues = ref.read(cueSettingsProvider(scope));
    AppLogger.d(
      'PLAYER',
      '_playTrack called for track: ${request.trackId}, file: ${request.fileId}',
    );

    // A timer's silent file is generated locally and is never a download.
    final downloadPath = request.isTimer
        ? null
        : await ref
              .read(audioDownloaderProvider.notifier)
              .getTrackPath(_constructFileName(request));

    if (downloadPath == null && request.trackId.startsWith('yt-video-')) {
      final fresh = await ref
          .read(youtubeSourceProvider)
          .resolveTrack(request.trackId);
      request = request.copyWith(
        remoteUrl: fresh.voices.single.audioFiles.single.path,
      );
    }
    if (generation != _generation) return;
    final url = downloadPath ?? request.remoteUrl;
    AppLogger.d('PLAYER', 'Will use path: $url');
    _analysisSource = url;

    // Both engines outlive the player screen and keep their last repeat mode
    // and speed across tracks, while each player screen starts at repeat off /
    // 1.0x. Reset them so a leftover "repeat forever" can't loop a session
    // (and block the end screen) and a slowed-down speed doesn't carry over.
    // A timer has no repeat control; its length is the session.
    final repeatMode = request.isTimer
        ? app_repeat.RepeatMode.none
        : ref.read(repeatStateProvider);

    final trackData = pigeon.Track(
      id: request.trackId,
      title: request.title,
      fileId: request.fileId,
      artist: request.guideName ?? '',
      artistUrl: request.artist?.path,
      description: request.description,
      imageUrl: request.coverUrl,
    );

    if (Platform.isAndroid) {
      AppLogger.d(
        'PLAYER',
        'On Android - starting service and checking readiness',
      );
      // NOTE: errors here intentionally propagate to play() and onwards to the
      // caller. Previously this was a swallow ('catch (e) { log; }') which
      // resolved play() successfully despite playback never starting, leading
      // to a silent-fail player screen. See P0-4 in the audit.
      await _androidServiceApi.startService();
      AppLogger.d(
        'PLAYER',
        'Service start requested, now waiting briefly before checking readiness',
      );
      await Future.delayed(const Duration(milliseconds: 500));

      final isReady = await _waitForServiceReadiness();

      if (isReady) {
        AppLogger.d('PLAYER', 'Service is ready, proceeding with playback');
      } else {
        AppLogger.w(
          'PLAYER',
          'Service failed to become ready, attempting playback anyway',
        );
        await Future.delayed(const Duration(seconds: 1));
      }
      if (generation != _generation) return;
      setRepeatMode(repeatMode);
      setSpeed(1.0);
      final holds = await _holdsFor(_cues!, request);
      if (generation != _generation) return;
      await NativeCueController.configure(_cues!, request, holds: holds);
      if (generation != _generation) return;
      await _playAudioWithRetry(url, trackData, generation);
    } else {
      AppLogger.d('PLAYER', 'On iOS - setting up audio');
      // NOTE: errors here intentionally propagate (see comment above for the
      // Android path). _playAudioWithRetry on Android already rethrows after
      // its retry budget — iOS has no such retry layer, so a single failure
      // here propagates immediately. That's intentional: callers need to know.
      setRepeatMode(repeatMode);
      setSpeed(1.0);
      if (generation != _generation) return;
      await iosAudioHandler.setUrl(downloadPath, request, trackData);
      if (generation != _generation) return;
      AppLogger.d('PLAYER', 'iOS setUrl succeeded');
      await iosAudioHandler.configureCues(_cues!, request);
      if (generation != _generation) return;
      await iosAudioHandler.play();
      AppLogger.d('PLAYER', 'iOS play() called');
    }
  }

  Future<bool> _waitForServiceReadiness() async {
    const maxAttempts = 10;
    const initialDelayMs = 500;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        AppLogger.d(
          'PLAYER',
          'Checking if service is ready (attempt ${attempt + 1})',
        );
        final isReady = await _androidServiceApi.isServiceReady();
        AppLogger.d(
          'PLAYER',
          'Service readiness check returned: $isReady (attempt ${attempt + 1})',
        );

        if (isReady) {
          AppLogger.d('PLAYER', 'Service is ready');
          return true;
        } else {
          AppLogger.d('PLAYER', 'Service not ready yet, waiting...');
          final delayMs = initialDelayMs * (1 << attempt);
          await Future.delayed(Duration(milliseconds: delayMs));
        }
      } catch (e) {
        AppLogger.e(
          'PLAYER',
          'Error during service readiness check (attempt ${attempt + 1})',
          e,
        );
        final delayMs = initialDelayMs * (1 << attempt);
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    AppLogger.e('PLAYER', 'Service readiness check timed out');
    return false;
  }

  Future<void> _playAudioWithRetry(
    String url,
    pigeon.Track trackData,
    int generation,
  ) async {
    const maxAttempts = 3;
    const initialDelayMs = 300;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (generation != _generation) return;
      try {
        AppLogger.d(
          'PLAYER',
          'Calling playAudio with url: $url (attempt ${attempt + 1})',
        );

        await _api.playAudio(pigeon.AudioData(url: url, track: trackData));

        AppLogger.d('PLAYER', 'playAudio call succeeded');
        return;
      } catch (e) {
        AppLogger.e(
          'PLAYER',
          'Error playing audio (attempt ${attempt + 1}): $e',
        );

        if (attempt < maxAttempts - 1) {
          final delayMs = initialDelayMs * (1 << attempt);
          AppLogger.d('PLAYER', 'Retrying playAudio in ${delayMs}ms...');
          await Future.delayed(Duration(milliseconds: delayMs));
        } else {
          rethrow;
        }
      }
    }
  }

  String _constructFileName(PlaybackRequest request) =>
      audioFileName(request.trackId, request.fileId, request.remoteUrl);

  Future<void> seekToPosition(int position) async {
    if (Platform.isAndroid) {
      await _api.seekToPosition(position);
    } else {
      await iosAudioHandler.seek(Duration(milliseconds: position));
    }
  }

  void stop() {
    _generation++;
    if (Platform.isAndroid || Platform.isIOS) {
      NativeCueController.stop();
    }
    if (Platform.isAndroid) {
      _api.stopAudio();
    } else {
      iosAudioHandler.stop();
    }
  }

  void setSpeed(double speed) {
    if (Platform.isAndroid) {
      _api.setSpeed(speed);
    } else {
      iosAudioHandler.setSpeed(speed);
    }
  }

  void setRepeatMode(app_repeat.RepeatMode mode) {
    final pigeonMode = switch (mode) {
      app_repeat.RepeatMode.none => pigeon.RepeatMode.none,
      app_repeat.RepeatMode.once => pigeon.RepeatMode.once,
      app_repeat.RepeatMode.infinite => pigeon.RepeatMode.infinite,
    };
    if (Platform.isAndroid) {
      _api.setRepeatMode(pigeonMode);
    } else {
      iosAudioHandler.setCustomRepeatMode(pigeonMode);
    }
  }

  void skip10SecondsForward() {
    if (Platform.isAndroid) {
      _api.skip10SecondsForward();
    } else {
      iosAudioHandler.seek(
        iosAudioHandler.position + const Duration(seconds: 15),
      );
    }
  }

  void skip10SecondsBackward() {
    if (Platform.isAndroid) {
      _api.skip10SecondsBackward();
    } else {
      iosAudioHandler.seek(
        iosAudioHandler.position - const Duration(seconds: 15),
      );
    }
  }

  void playPause() {
    if (Platform.isAndroid) {
      _api.playPauseAudio();
    } else {
      if (iosAudioHandler.playing) {
        iosAudioHandler.pause();
      } else {
        iosAudioHandler.play();
      }
    }
  }
}

const audioPercentageListened = 0.9;
const androidNotificationIcon = 'logo';
const notificationId = 1595122;
const androidNotificationChannelId = 'medito_reminder_channel';
