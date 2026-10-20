import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/services/audio/native_cue_controller.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../../services/audio/ios_session_bells.dart';
import 'package:medito/models/models.dart' show PlaybackRequest;
import 'package:medito/providers/background_sounds/background_sounds_notifier.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../constants/types/type_constants.dart';
import '../../src/audio_pigeon.g.dart';
import '../../utils/stats_updater.dart';
import '../../utils/logger.dart';

class IosAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player;
  late final sessionBells = IosSessionBells(_player);
  // Distinguish a repeat boundary from terminal completion; never wait for bells.
  final _sessionCompleted = BehaviorSubject<bool>.seeded(false);
  bool _isInitialized = false;
  RepeatMode _currentRepeatMode = RepeatMode.none;
  bool _hasReplayedOnce = false;
  bool _nativeCues = false;
  int _cueGeneration = 0;
  bool _nativeNeedsBegin = false;
  bool _nativeCountdown = false;
  bool _nativeExtending = false;
  bool _nativeHoldPaused = false;
  // A hold paused by an interruption, to resume when it ends.
  bool _interruptedHold = false;
  bool _nativeCompletionEarned = false;
  bool _thresholdRecorded = false;
  bool _isTimer = false;
  Timer? _nativeTailRelease;

  /// Full play-throughs of the current track, counting repeats. The first is
  /// recorded as the session; each later one only adds its listening time.
  int _completedPlaythroughs = 0;

  /// While the player is paused the audio session is kept active so a quick
  /// resume stays seamless and the lock-screen controls remain. If the pause
  /// lasts longer than this the user has likely walked away, so the session is
  /// released to stop iOS keeping the app alive in the background.
  static const _pauseGracePeriod = Duration(minutes: 3);
  Timer? _pauseDeactivationTimer;

  IosAudioHandler({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;

    try {
      final session = await AudioSession.instance;

      // Configure interruption handling
      session.interruptionEventStream.listen(handleInterruption);
      session.becomingNoisyEventStream.listen((_) => handleBecomingNoisy());

      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.none,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        ),
      );

      _setupPlaybackState();
      _setupEventListeners();

      _isInitialized = true;
    } catch (e) {
      AppLogger.e('IOS', 'Failed to initialize audio session: $e');
      rethrow;
    }
  }

  /// A call or another app takes the audio. The countdown and the extension
  /// have no voice to pause, so they are held like a pause and resumed only
  /// when the interruption ends and iOS says to resume.
  @visibleForTesting
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _player.setVolume(_player.volume * 0.5);
          break;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (nativeHold) {
            _interruptedHold = !_nativeHoldPaused;
            unawaited(pause());
          } else {
            _player.pause();
          }
          break;
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          _player.setVolume(_player.volume * 2.0);
          break;
        case AudioInterruptionType.pause:
          if (_interruptedHold) {
            _interruptedHold = false;
            if (nativeHold) unawaited(play());
          } else if (_player.playing) {
            _player.play();
          }
          break;
        case AudioInterruptionType.unknown:
          _interruptedHold = false;
          break;
      }
    }
  }

  /// Headphones unplugged: pause, holding the countdown or extension too, so
  /// the end bell never rings out of the speaker.
  @visibleForTesting
  void handleBecomingNoisy() {
    if (nativeHold) {
      _interruptedHold = false;
      unawaited(pause());
    } else {
      _player.pause();
    }
  }

  void _setupPlaybackState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          MediaControl.play,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setSpeed,
          MediaAction.pause,
          MediaAction.play,
        },
        playing: false,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        speed: 1.0,
      ),
    );
  }

  void _setupEventListeners() {
    _player.positionStream.listen((_) => unawaited(_reportNativeTransport()));
    _player.playerStateStream.listen(
      (_) => unawaited(_reportNativeTransport()),
    );

    iosStateStream.listen((event) {
      mediaItem.add(
        MediaItem(
          id: event.track.toString(),
          title: event.track.title,
          artist: event.track.artist,
          duration: event.duration,
          // A timer session has no cover; an empty URI is not "no art".
          artUri: event.track.imageUrl.isEmpty
              ? null
              : Uri.parse(event.track.imageUrl),
          playable: true,
          displayTitle: event.track.title,
          displaySubtitle: event.track.artist,
        ),
      );

      playbackState.add(
        playbackState.value.copyWith(
          updatePosition: event.position,
          bufferedPosition: event.bufferedPosition,
          speed: event.speed,
          playing: event.playerState.playing,
        ),
      );
    });

    _player.processingStateStream.listen((state) async {
      if (state != ProcessingState.completed) _sessionCompleted.add(false);
      if (state == ProcessingState.completed) {
        // Handle repeat once mode
        if (_currentRepeatMode == RepeatMode.once && !_hasReplayedOnce) {
          _hasReplayedOnce = true;
          unawaited(_recordPlaythrough());
          await _player.seek(Duration.zero);
          await _player.play();
          return;
        }

        if (_nativeCues) {
          await _reportNativeTransport();
          _nativeExtending = true;
          _nativeHoldPaused = false;
          _sessionCompleted.add(false);
          await NativeCueController.channel.invokeMethod<void>('voiceEnded');
          unawaited(_followExtension());
          return;
        }
        _sessionCompleted.add(true);

        // Playback has finished and is not repeating. Release the audio
        // session first so iOS does not keep the app alive in the background,
        // which otherwise drains battery for as long as the session stays
        // active after the meditation ends. Recording the completion runs
        // afterwards because local storage and platform updates can be slow and must
        // not delay session release.
        _cancelPauseDeactivationTimer();
        // The ambient background player loops and keeps rendering audio after
        // the narration ends; pause it first so the shared session is idle and
        // iOS will actually let us deactivate it (a busy session is rejected).
        await iosBackgroundPlayer.pause();
        await sessionBells.disable();
        await _deactivateSession();

        await _recordPlaythrough();
      }
    });

    // Repeat forever (LoopMode.one) never reaches `completed`; each loop back
    // to the start surfaces as an auto-advance discontinuity instead.
    // just_audio also reports autoAdvance when a new source is loaded, so only
    // count it when the same, already-playing item wrapped around.
    _player.positionDiscontinuityStream.listen((discontinuity) {
      final prev = discontinuity.previousEvent;
      final curr = discontinuity.event;
      const active = {ProcessingState.ready, ProcessingState.buffering};
      final isLoop =
          discontinuity.reason == PositionDiscontinuityReason.autoAdvance &&
          _currentRepeatMode == RepeatMode.infinite &&
          active.contains(prev.processingState) &&
          active.contains(curr.processingState) &&
          prev.duration != null &&
          prev.duration == curr.duration;
      if (isLoop) unawaited(_recordPlaythrough());
      if (_nativeCues &&
          discontinuity.reason == PositionDiscontinuityReason.seek) {
        // A seek during the extension brings the voice back; Swift leaves
        // its hold on this report, so the hold is over here too.
        if (_nativeExtending) {
          _nativeExtending = false;
          _nativeHoldPaused = false;
        }
        unawaited(_reportNativeTransport(seek: true));
      }
    });

    _player.playbackEventStream.listen((event) {
      final playing = _player.playing;

      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.rewind,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.fastForward,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.setSpeed,
            MediaAction.pause,
            MediaAction.play,
          },
          playing: playing,
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        ),
      );
    });
  }

  Duration get position => _player.position;

  bool get playing => (_nativeCountdown || _nativeExtending)
      ? !_nativeHoldPaused
      : _player.playerState.playing;

  bool get isComplete =>
      _player.playerState.processingState == ProcessingState.completed;

  /// Whether cues run in Swift; tests stand in for the iOS platform.
  @visibleForTesting
  bool get usesNativeCues => Platform.isIOS;

  /// The terminal state the player screen reads, separate from stats.
  @visibleForTesting
  bool get sessionCompleted => _sessionCompleted.value;

  /// Whether this session counts in the stats.
  @visibleForTesting
  bool get completionEarned => _nativeCompletionEarned;

  /// Whether the Swift countdown or extension owns play and pause.
  @visibleForTesting
  bool get nativeHold => _nativeCountdown || _nativeExtending;

  final _trackStateSubject = BehaviorSubject<Track>();

  Track get trackState => _trackStateSubject.value;

  Stream<Track> get _trackStateStream => _trackStateSubject.stream;

  Stream<Duration> get positionStream => _player.positionStream;

  Duration? get duration => _player.duration;

  Stream<IosStateData> get iosStateStream =>
      Rx.combineLatest7<
        double,
        PlayerState,
        Track,
        Duration,
        Duration,
        Duration?,
        bool,
        IosStateData
      >(
        _player.speedStream,
        _player.playerStateStream,
        _trackStateStream,
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        _sessionCompleted.stream,
        (speed, state, track, position, bufferedPosition, duration, completed) {
          return IosStateData(
            speed,
            (_nativeCountdown || _nativeExtending)
                ? PlayerState(!_nativeHoldPaused, ProcessingState.ready)
                : state.processingState == ProcessingState.completed &&
                      !completed
                ? PlayerState(false, ProcessingState.ready)
                : state,
            track,
            position,
            bufferedPosition,
            duration ?? Duration.zero,
          );
        },
      );

  Future<void> _recordPlaythrough() {
    _completedPlaythroughs++;
    if (_completedPlaythroughs == 1) {
      if (_nativeCues && (!_nativeCompletionEarned || _thresholdRecorded)) {
        return Future<void>.value();
      }
      return _storeTrackCompletion();
    }
    return _storeRepeatPlaythrough();
  }

  Future<void> _storeRepeatPlaythrough() async {
    try {
      if (duration == null) return;
      await handleRepeatPlaythrough({
        TypeConstants.trackIdKey: trackState.id,
        TypeConstants.durationIdKey: duration!.inMilliseconds,
        TypeConstants.fileIdKey: trackState.fileId,
        TypeConstants.guideIdKey: trackState.artist ?? '',
        TypeConstants.timestampIdKey: DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      AppLogger.e('IOS', 'Error recording repeat play-through: $e');
    }
  }

  Future<void> _storeTrackCompletion() async {
    try {
      if (duration == null) return;

      final payload = await _createTrackCompletionPayload();

      // Try to update stats immediately
      if (await _tryUpdateStats(payload)) {
        return;
      }

      // Failed to update stats directly, store for later processing
      await _storeForLaterProcessing(payload);
    } catch (e) {
      AppLogger.e(
        'IOS',
        'Error processing track completion in AudioHandler: $e',
      );
    }
  }

  /// Creates a payload map with all track completion data
  Future<Map<String, dynamic>> _createTrackCompletionPayload() async {
    return {
      TypeConstants.trackIdKey: trackState.id,
      TypeConstants.durationIdKey: duration?.inMilliseconds ?? 0,
      TypeConstants.fileIdKey: trackState.fileId,
      TypeConstants.guideIdKey: trackState.artist ?? '',
      TypeConstants.timestampIdKey: DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// Try to update stats directly and return success status
  Future<bool> _tryUpdateStats(Map<String, dynamic> payload) async {
    try {
      AppLogger.d('IOS', 'Track completed: ${trackState.id}');
      final success = await handleStats(payload);

      if (success) {
        AppLogger.d('IOS', 'Successfully updated stats from audio handler');
        return true;
      }
    } catch (e) {
      AppLogger.e(
        'IOS',
        'Error updating stats directly from audio handler: $e',
      );
    }
    return false;
  }

  /// Store track completion data for later processing
  Future<void> _storeForLaterProcessing(Map<String, dynamic> payload) async {
    AppLogger.d(
      'IOS',
      'Storing track completion for later processing: ${trackState.id}',
    );
    final prefs = await SharedPreferences.getInstance();
    await storeTrackCompletion(prefs, payload);
  }

  @override
  Future<void> seek(Duration position) {
    return _player.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) {
    return _player.setSpeed(speed);
  }

  Future<void> setCustomRepeatMode(RepeatMode mode) async {
    _currentRepeatMode = mode;
    _hasReplayedOnce = false;

    switch (mode) {
      case RepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.once:
        await _player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.infinite:
        await _player.setLoopMode(LoopMode.one);
        break;
    }
  }

  @override
  Future<void> play() async {
    _cancelPauseDeactivationTimer();
    if (_nativeCues && (_nativeCountdown || _nativeExtending)) {
      _nativeHoldPaused = false;
      await NativeCueController.channel.invokeMethod<void>('setHeld', {
        'held': false,
      });
      _sessionCompleted.add(false);
      if (iosAmbientActive) unawaited(iosBackgroundPlayer.play());
      return;
    }

    final session = await AudioSession.instance;
    await session.setActive(true);

    if (_nativeCues && _nativeNeedsBegin) {
      _nativeNeedsBegin = false;
      final countdown =
          await NativeCueController.channel.invokeMethod<int>('begin') ?? 0;
      if (countdown > 0) {
        _nativeCountdown = true;
        return;
      }
    }
    unawaited(_player.play());
    // Bells follow _player on their own; resume the ambient sound if any.
    if (iosAmbientActive) unawaited(iosBackgroundPlayer.play());
  }

  @override
  Future<void> pause() async {
    if (_nativeCues && (_nativeCountdown || _nativeExtending)) {
      _nativeHoldPaused = true;
      await NativeCueController.channel.invokeMethod<void>('setHeld', {
        'held': true,
      });
      _sessionCompleted.add(false);
    }
    unawaited(_player.pause());
    unawaited(iosBackgroundPlayer.pause());

    // Keep the session active for a quick resume, but release it if the pause
    // is prolonged so iOS stops keeping the app alive in the background.
    _schedulePauseDeactivation();
  }

  @override
  Future<void> stop() async {
    _cancelPauseDeactivationTimer();
    _nativeTailRelease?.cancel();
    if (_nativeCues) await NativeCueController.stop();
    _nativeCues = false;
    _cueGeneration++;
    _nativeCountdown = false;
    _nativeExtending = false;
    await sessionBells.disable();
    // Await the players so their audio I/O has actually stopped before we
    // deactivate; iOS rejects deactivation while the shared session is busy.
    await _player.stop();
    await iosBackgroundPlayer.pause();
    unawaited(super.stop());
    await _deactivateSession();
  }

  /// Schedules release of the audio session after [_pauseGracePeriod] if the
  /// player is still paused, so an abandoned pause does not keep the app in
  /// background-audio state indefinitely.
  void _schedulePauseDeactivation() {
    _pauseDeactivationTimer?.cancel();
    _pauseDeactivationTimer = Timer(_pauseGracePeriod, () {
      if ((!_player.playing ||
          _player.processingState == ProcessingState.completed)) {
        unawaited(_deactivateSession());
      }
    });
  }

  void _cancelPauseDeactivationTimer() {
    _pauseDeactivationTimer?.cancel();
    _pauseDeactivationTimer = null;
  }

  /// Deactivates the iOS audio session so the OS stops treating the app as an
  /// active background-audio app. Without this, the session activated in
  /// [play] stays active after playback stops/completes and keeps the app
  /// running in the background, draining the battery. The
  /// `notifyOthersOnDeactivation` option lets other apps (e.g. music) resume
  /// once we release the session.
  Future<void> _deactivateSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(
        false,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
      );
    } catch (e) {
      AppLogger.e('IOS', 'Failed to deactivate audio session: $e');
    }
  }

  /// iOS owns the cue clock in Swift. Dart forwards transport changes, not
  /// individual beat deadlines, and keeps terminal state separate from 90%.
  Future<void> configureCues(
    CueSettings settings,
    PlaybackRequest request,
  ) async {
    _cueGeneration++;
    _nativeCues = usesNativeCues;
    if (!_nativeCues) return;
    _nativeTailRelease?.cancel();
    _nativeNeedsBegin = true;
    _nativeCountdown = false;
    _nativeExtending = false;
    _nativeHoldPaused = false;
    _nativeCompletionEarned = false;
    _thresholdRecorded = false;
    _isTimer = request.trackId.startsWith('timer-');
    NativeCueController.channel.setMethodCallHandler((call) async {
      if (!_nativeCues) return;
      if (call.method == 'countdownFinished') {
        _nativeCountdown = false;
        unawaited(_player.play());
        if (iosAmbientActive) unawaited(iosBackgroundPlayer.play());
      } else if (call.method == 'sessionEnded') {
        final args = Map<Object?, Object?>.from(call.arguments as Map);
        await _finishNativeSession(
          tailMs: (args['tailMs'] as num?)?.toInt() ?? 0,
          interlude: args['interlude'] == true,
        );
      }
    });
    await NativeCueController.configure(settings, request);
    await NativeCueController.channel.invokeMethod<void>('resetListening', {
      'trackId': request.trackId,
      'fileId': request.fileId,
    });
  }

  Future<void> _reportNativeTransport({bool seek = false}) async {
    if (!_nativeCues || _nativeNeedsBegin) return;
    final generation = _cueGeneration;
    try {
      final audible =
          _player.playing && _player.processingState == ProcessingState.ready;
      final args = <String, Object?>{
        'positionMs': _player.position.inMilliseconds,
        'durationMs': _player.duration?.inMilliseconds ?? 0,
        'playing': audible,
        'speed': _player.speed,
        'endless': _currentRepeatMode == RepeatMode.infinite,
        'itemsAfterCurrent':
            _currentRepeatMode == RepeatMode.once && !_hasReplayedOnce ? 1 : 0,
        'seek': seek,
      };
      await NativeCueController.channel.invokeMethod<void>('transport', args);
      if (generation != _cueGeneration || !_nativeCues) return;
      final earned =
          await NativeCueController.channel.invokeMethod<bool>(
            'sampleListening',
            args,
          ) ??
          false;
      if (generation != _cueGeneration || !_nativeCues) return;
      if (earned && !_thresholdRecorded && !_isTimer) {
        _nativeCompletionEarned = true;
        _thresholdRecorded = true;
        await _storeTrackCompletion();
      }
    } catch (e) {
      AppLogger.e('CUES', 'Could not report iOS transport: $e');
    }
  }

  final _extensionRemaining = StreamController<int>.broadcast();

  /// Milliseconds left in the silent extension while it runs, from the Swift
  /// clock: the voice's position stops at its end, so the ambient fade
  /// follows this instead.
  Stream<int> get extensionRemainingStream => _extensionRemaining.stream;

  /// Whether the silent extension is under way.
  bool get extending => _nativeExtending;

  /// Reads the extension clock rarely while far from the end and every
  /// 200 ms in its last ten seconds; stops with the extension.
  Future<void> _followExtension() async {
    final generation = _cueGeneration;
    while (_nativeExtending && generation == _cueGeneration) {
      final int remaining;
      try {
        final state = await NativeCueController.state();
        remaining = (state['extensionRemainingMs'] as num?)?.toInt() ?? 0;
      } catch (e) {
        AppLogger.e('CUES', 'Extension clock unavailable: $e');
        return;
      }
      if (!_nativeExtending || generation != _cueGeneration) return;
      _extensionRemaining.add(remaining);
      final waitMs = _nativeHoldPaused
          ? 1000
          : remaining > 15000
          ? 5000
          : remaining > 10200
          ? remaining - 10000
          : 200;
      await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
  }

  Future<void> waitForInterlude(int seconds) async {
    _nativeTailRelease?.cancel();
    await NativeCueController.holdInterlude(seconds);
  }

  /// No autoplay after all: Swift drops the interlude it began at the end,
  /// and the session is released once the end bell has rung out.
  Future<void> endInterlude() async {
    if (!_nativeCues) return;
    try {
      await NativeCueController.endInterlude();
    } catch (e) {
      AppLogger.e('CUES', 'Could not end the interlude: $e');
    }
    _releaseAfterTail(_nativeTailMs);
  }

  int _nativeTailMs = 0;

  Future<void> _finishNativeSession({
    required int tailMs,
    bool interlude = false,
  }) async {
    _nativeExtending = false;
    _nativeCountdown = false;
    // A timer counts at its end; a recording only once 90% was really heard
    // (sampled above). A finished extension after a seek to the end does not.
    _nativeCompletionEarned = _nativeCompletionEarned || _isTimer;
    _cancelPauseDeactivationTimer();
    await iosBackgroundPlayer.pause();
    await _recordPlaythrough();
    // The true end is terminal whether or not it earned the stats above.
    _sessionCompleted.add(true);
    _nativeTailMs = tailMs;
    // With autoplay Swift holds the session through the interlude; the next
    // session or endInterlude releases it.
    if (!interlude) _releaseAfterTail(tailMs);
  }

  /// The Swift bell and silent keep-alive must finish before deactivation.
  void _releaseAfterTail(int tailMs) {
    _nativeTailRelease?.cancel();
    _nativeTailRelease = Timer(Duration(milliseconds: tailMs + 350), () {
      if (_nativeCues &&
          !_nativeExtending &&
          (!_player.playing ||
              _player.processingState == ProcessingState.completed)) {
        unawaited(_deactivateSession());
      }
    });
  }

  Future<void> setUrl(
    String? downloadPath,
    PlaybackRequest request,
    Track trackData,
  ) async {
    await ensureInitialized();

    _nativeCues = false;
    _cueGeneration++;
    _nativeTailRelease?.cancel();
    _hasReplayedOnce = false;
    _completedPlaythroughs = 0;
    _sessionCompleted.add(false);
    sessionBells.reset();

    // A file in the library is an absolute path, which is not a URI.
    final localPath =
        downloadPath ??
        (request.remoteUrl.startsWith('/') ? request.remoteUrl : null);
    if (localPath == null) {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(request.remoteUrl)),
      );
    } else {
      await _player.setFilePath(localPath);
    }

    await setCustomRepeatMode(_currentRepeatMode);

    _trackStateSubject.add(trackData);
  }
}

class IosStateData {
  final double speed;
  final PlayerState playerState;
  final Track track;
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  IosStateData(
    this.speed,
    this.playerState,
    this.track,
    this.position,
    this.bufferedPosition,
    this.duration,
  );
}
