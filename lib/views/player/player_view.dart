import 'package:medito/providers/cues/cue_runtime_provider.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/services/audio/native_cue_controller.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:medito/widgets/adaptive/adaptive_player_layout.dart';
import 'package:medito/models/player/playback_request.dart';

import 'dart:ui';
import 'dart:io';

import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/utils/stats_updater.dart' show handleStats;
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/pending_end_screen.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/views/end_screen/end_screen_view.dart';
import 'package:medito/views/player/session_completion_gate.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/views/player/widgets/artist_title_widget.dart';
import 'package:medito/widgets/attribution_notice.dart';
import 'package:medito/widgets/generated_artwork.dart';
import 'package:medito/views/player/widgets/bottom_actions/player_action_bar.dart';
import 'package:medito/views/player/widgets/duration_indicator_widget.dart';
import 'package:medito/views/player/widgets/stopwatch_elapsed_widget.dart';
import 'package:medito/views/player/widgets/player_buttons/player_buttons_widget.dart';
import 'package:medito/services/audio/session_bell_preview.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/background_sounds/background_sounds_notifier.dart';
import '../../widgets/errors/medito_error_widget.dart';

class PlayerView extends ConsumerStatefulWidget {
  const PlayerView({super.key, this.skipCustomize = false});

  final bool skipCustomize;

  @override
  ConsumerState<PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends ConsumerState<PlayerView> {
  bool _endScreenOpened = false;
  bool _isClosing = false;
  // Set when play() throws (e.g. offline, native audio failed to start). The
  // caller no longer awaits play() before navigating — we own starting
  // playback here — so this is how a start failure surfaces to the user.
  AppError? _startError;

  /// Whether playback has actually started on this screen. Until it has, the
  /// play button shows a spinner regardless of the shared audio state, which
  /// can still hold the previous session's values or briefly read "loaded but
  /// not playing" between load and play — both made the button flicker
  /// play → spinner → pause on open.
  bool _playbackStarted = false;
  Timer? _playbackStartFallback;
  Timer? _countdownPoll;
  int _countdownMs = 0;
  CueScope? _cueScope;
  ProviderSubscription<CueSettings>? _cueSubscription;
  bool _customized = false;
  bool _playRequested = false;
  bool _autoplayPending = false;
  bool _finishing = false;
  bool _cancelAutoplay = false;

  /// Keeps a previous session's completed state from opening the end screen.
  final _completionGate = SessionCompletionGate();
  // Snapshot of stats taken when the player opens, before the session can
  // affect them. EndScreenView uses this as the "before" value so its
  // AnimatedSwitcher actually animates from old streak -> new streak.
  LocalAllStats? _statsAtSessionStart;
  // Read once: dispose() clears the pending end screen and may not use ref.
  late final SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    PendingEndScreen.playerMounted();
    _prefs = ref.read(sharedPreferencesProvider);
    _statsAtSessionStart = ref.read(statsProvider).value;
    // Bells are remembered per scope (on by default for a timer, off under
    // tracks); set before _initializePlayer restores them.
    ref
        .read(backgroundSoundsNotifierProvider.notifier)
        .setTimerScope(ref.read(playerProvider)?.isTimer ?? false);
    // A listener rather than build(): build only sees the latest value, and a
    // not-completed reading between two completed ones must still arm the gate.
    ref.listenManual(
      audioStateProvider.select((s) => s.isCompleted),
      (_, isCompleted) => _completionGate.completionChanged(isCompleted),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPlayback();
    });
  }

  /// Starts playback for the request the caller prepared. Runs here (rather
  /// than at the call site, awaited before navigation) so the screen opens
  /// instantly and shows a loading state while the audio spins up. A failure
  /// flips [_startError] so build() can show a retryable error instead of a
  /// silent, stuck player.
  Future<void> _startPlayback() async {
    final request = ref.read(playerProvider);
    if (request == null) return;
    _completionGate.reset();
    ref.read(cueRuntimeProvider.notifier).reset();
    try {
      _cueScope = await ref.read(cueScopeForRequestProvider(request).future);
      if (!mounted || _isClosing) return;
      final settings = ref.read(cueSettingsProvider(_cueScope!));
      if (!_customized &&
          !widget.skipCustomize &&
          !request.isTimer &&
          !settings.hideBeforePractice) {
        _customized = true;
        final start = await showCustomizeSheet(
          context,
          request: request,
          beforeStart: true,
        );
        if (!mounted || _isClosing) return;
        if (!start) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return;
        }
      }
    } catch (e, st) {
      AppLogger.e('CUES', 'Could not load customization', e, st);
      if (mounted) setState(() => _startError = const UnknownError());
      return;
    }
    // So the end screen can be rebuilt if the app is killed before this
    // session's completion gets to open it.
    unawaited(PendingEndScreen.start(_prefs, request, _statsAtSessionStart));
    try {
      _playRequested = true;
      await ref.read(playerProvider.notifier).play(request);
      if (!mounted || _isClosing) return;
      _completionGate.trackLoaded(
        isCompleted: ref.read(audioStateProvider).isCompleted,
      );
      // If audio never reports playing (e.g. an interruption right at start),
      // stop waiting and show the play button so the user can start it.
      _playbackStartFallback?.cancel();
      _playbackStartFallback = Timer(const Duration(seconds: 3), () {
        if (mounted && !_playbackStarted) {
          setState(() => _playbackStarted = true);
        }
      });
      _cueSubscription?.close();
      _cueSubscription = ref.listenManual(cueSettingsProvider(_cueScope!), (
        _,
        settings,
      ) {
        unawaited(
          ref
              .read(playerProvider.notifier)
              .updateCueSettings(settings)
              .catchError((Object e) {
                AppLogger.e('CUES', 'Could not update cues: $e');
              }),
        );
        ref
            .read(backgroundSoundsNotifierProvider.notifier)
            .applyCueSettings(settings);
      });
      _countdownPoll?.cancel();
      if (Platform.isAndroid || Platform.isIOS) {
        _countdownPoll = Timer.periodic(const Duration(milliseconds: 200), (
          _,
        ) async {
          try {
            final cueState = await NativeCueController.state();
            if (!mounted) return;
            ref.read(cueRuntimeProvider.notifier).updateFromMap(cueState);
            final remaining =
                (cueState['countdownRemainingMs'] as num?)?.toInt() ?? 0;
            if (mounted && remaining != _countdownMs) {
              setState(() => _countdownMs = remaining);
            }
          } catch (e) {
            AppLogger.e('CUES', 'Countdown state unavailable: $e');
            _countdownPoll?.cancel();
          }
        });
      }
      // The native service must be ready before restoring background audio.
      if (mounted && !_isClosing) unawaited(_initializePlayer());
    } catch (e, st) {
      AppLogger.e('PLAYER', 'Failed to start playback', e, st);
      if (mounted) {
        setState(() => _startError = e is AppError ? e : const UnknownError());
      }
    }
  }

  void _retryPlayback() {
    setState(() {
      _startError = null;
      _playbackStarted = false;
    });
    _startPlayback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheCurrentTrackImage();
  }

  @override
  void dispose() {
    // Gone with this screen either way: the end screen opened, or the
    // session was closed before it finished.
    PendingEndScreen.playerUnmounted();
    unawaited(PendingEndScreen.clear(_prefs));
    _playbackStartFallback?.cancel();
    _countdownPoll?.cancel();
    _cueSubscription?.close();
    _cancelAutoplay = true;
    super.dispose();
  }

  void _precacheCurrentTrackImage() {
    final currentlyPlayingTrack = ref.read(playerProvider);
    if (currentlyPlayingTrack != null) {
      _precacheImage(currentlyPlayingTrack.coverUrl);
    }
  }

  void _precacheImage(String imageUrl) {
    if (imageUrl.isNotEmpty && Uri.tryParse(imageUrl)?.hasScheme == true) {
      try {
        final networkImage = NetworkImage(imageUrl);
        unawaited(
          precacheImage(networkImage, context).catchError((error) {
            AppLogger.d(
              'PlayerView',
              'Failed to precache image: \$imageUrl, error: \$error',
            );
          }),
        );
      } catch (e) {
        AppLogger.d(
          'PlayerView',
          'Failed to create or precache image: \$imageUrl, error: \$e',
        );
      }
    }
  }

  Future<void> _initializePlayer() async {
    final scope = _cueScope;
    if (scope != null) {
      ref
          .read(backgroundSoundsNotifierProvider.notifier)
          .applyCueSettings(ref.read(cueSettingsProvider(scope)));
    }

    // Only enable DND if permission is already granted and toggle is on
    if (Platform.isAndroid) {
      final dndNotifier = ref.read(dndProvider.notifier);
      final hasAccess = await dndNotifier.hasAccess();
      if (hasAccess) {
        await dndNotifier.setDndMode(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild on completion; the gate decides whether it is this session's.
    ref.watch(audioStateProvider.select((s) => s.isCompleted));
    if (_completionGate.isSessionComplete(ref.read(audioStateProvider))) {
      if (!_finishing) unawaited(_finishOrAutoplay());
    }

    final currentlyPlayingTrack = ref.watch(playerProvider);

    ref.listen(playerProvider.select((p) => p?.coverUrl), (_, next) {
      if (next != null) {
        _precacheImage(next);
      }
    });

    if (currentlyPlayingTrack == null) {
      return MeditoErrorWidget(
        error: const UnknownError(),
        onTap: () => Navigator.pop(context),
      );
    }

    if (_startError case final error?) {
      return MeditoErrorWidget(error: error, onTap: _retryPlayback);
    }

    final isPlaying = ref.watch(audioStateProvider.select((s) => s.isPlaying));
    ref.listen(audioStateProvider.select((s) => s.isPlaying), (_, playing) {
      if (playing && !_playbackStarted) {
        _playbackStartFallback?.cancel();
        setState(() => _playbackStarted = true);
      }
    });

    // The transport (play/pause + progress) is genuinely loading until the
    // native player reports it's playing or knows the duration. Everything
    // else on screen is already final, so only the play button shows a spinner.
    // Buffering (initial spin-up OR a mid-session re-buffer on a slow network)
    // counts as loading too — the spinner in place of the play button is the
    // right signal there, so we don't gate it to the start.
    final audioState = ref.watch(audioStateProvider);
    final isAudioLoading =
        !audioState.isCompleted &&
        (!_playbackStarted || audioState.isBuffering);

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _resetState();
          _stopAudio();
        }
      },
      child: Stack(
        children: [
          PlayerScreenLayout(
            currentlyPlayingTrack: currentlyPlayingTrack,
            isPlaying: isPlaying,
            isAudioLoading: isAudioLoading,
            isBackgroundSoundSelected: _isBackgroundSoundSelected(),
            onPlayPausePressed: onPlayPausePressed,
            onSpeedChanged: (speed) =>
                ref.read(playerProvider.notifier).setSpeed(speed),
            onClosePressed: () => _handleClose(),
            onEndSession: _endTimerSession,
          ),
          if (_countdownMs > 0)
            Positioned.fill(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${(_countdownMs / 1000).ceil()}',
                          style: Theme.of(context).textTheme.displayLarge,
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () =>
                              unawaited(NativeCueController.skipCountdown()),
                          child: const Text('Skip countdown'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_autoplayPending)
            Positioned.fill(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Next session'),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          _cancelAutoplay = true;
                          _stopAudio();
                          _openEndScreen();
                        },
                        child: const Text('End session'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _finishOrAutoplay() async {
    _finishing = true;
    final request = ref.read(playerProvider);
    final scope = _cueScope;
    final settings = scope == null
        ? null
        : ref.read(cueSettingsProvider(scope));
    if (request == null ||
        request.isTimer ||
        settings?.autoplay != true ||
        scope?.courseId == null) {
      _openEndScreen();
      return;
    }
    _autoplayPending = true;
    if (mounted) setState(() {});
    try {
      final router = ContentRouter(sources: ref.read(contentSourcesProvider));
      final pack = await router.pack(scope!.courseId!);
      final items = pack.items
          .where((item) => item.type == TypeConstants.track)
          .toList();
      final index = items.indexWhere((item) => item.id == request.trackId);
      if (index < 0 || index + 1 >= items.length) {
        _openEndScreen();
        return;
      }
      if (Platform.isAndroid) {
        await NativeCueController.holdInterlude(settings!.interludeSeconds);
      } else if (Platform.isIOS) {
        await iosAudioHandler.waitForInterlude(settings!.interludeSeconds);
      } else {
        await Future<void>.delayed(
          Duration(seconds: settings!.interludeSeconds),
        );
      }
      if (!mounted || _cancelAutoplay || _isClosing) return;
      final track = await ref.read(
        tracksProvider(trackId: items[index + 1].id).future,
      );
      if (!mounted || _cancelAutoplay || _isClosing) return;
      final voice = track.voices.first;
      final next = PlaybackRequest.fromTrack(
        track,
        voice,
        voice.audioFiles.first,
      );
      ref.read(playerProvider.notifier).prepare(next);
      // Recreate the player lifecycle so gates and snapshots belong to next.
      Navigator.of(
        context,
      ).popUntil((route) => route == ModalRoute.of(context));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const PlayerView(skipCustomize: true),
        ),
      );
    } catch (e, st) {
      AppLogger.e('CUES', 'Autoplay could not start next session', e, st);
      if (mounted && !_cancelAutoplay) _openEndScreen();
    }
  }

  /// End session on a timer: records the time sat so far as a session (a
  /// stopwatch only ever ends this way) and opens the end screen, like a
  /// track finishing. Under a minute it is discarded, like closing a track.
  void _endTimerSession() {
    final request = ref.read(playerProvider);
    if (request == null || !request.isTimer) return;
    if (_endScreenOpened || _isClosing) return;

    final elapsed = Duration(
      seconds: ref.read(audioStateProvider).position ~/ 1000,
    );
    final recorded = elapsed >= kMinRecordedTimerSession;

    if (!recorded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.timerTooShort)),
      );
      _handleClose();
      return;
    }

    // Same path as a native completion, so stats, history, streak, Health,
    // reminders and the home widget all update, offline included.
    unawaited(
      handleStats({
        TypeConstants.trackIdKey: timerSessionId(elapsed),
        TypeConstants.durationIdKey: elapsed.inMilliseconds,
        TypeConstants.fileIdKey: request.fileId,
        TypeConstants.guideIdKey: '',
        TypeConstants.timestampIdKey: DateTime.now().millisecondsSinceEpoch,
      }),
    );

    // A countdown that runs out rings its closing bell before the end; ending
    // early (or finishing a stopwatch) rings it as the end screen opens.
    final bgSounds = ref.read(backgroundSoundsNotifierProvider.notifier);
    final bellsOn = ref.read(backgroundSoundsNotifierProvider).bellsEnabled;
    final volume = bgSounds.scaledVolume(
      ref.read(backgroundSoundsNotifierProvider).volume,
    );
    final bell = ref.read(sessionBellPreviewProvider);
    _openEndScreen(
      // Rung just after the player has stopped: on iOS stop() releases the
      // audio session asynchronously, which would clip a bell started in the
      // same frame. The bell's own player reactivates the session.
      afterStop: bellsOn
          ? () => Future.delayed(
              const Duration(milliseconds: 400),
              () => bell.play(volume),
            )
          : null,
    );
  }

  void onPlayPausePressed() {
    final isPlaying = ref.read(audioStateProvider).isPlaying;

    // Control primary track
    ref.read(playerProvider.notifier).playPause();

    // For iOS, we need to explicitly toggle background sound too
    // Android will handle it in the native implementation
    if (Platform.isIOS) {
      ref
          .read(backgroundSoundsNotifierProvider.notifier)
          .togglePlayPause(isPlaying);
    }
  }

  bool _isBackgroundSoundSelected() {
    final bgSoundNotifier = ref.watch(backgroundSoundsNotifierProvider);
    final isPlaying = ref.watch(audioStateProvider.select((s) => s.isPlaying));

    return isPlaying && bgSoundNotifier.hasAnySound;
  }

  void _handleClose({bool shouldPop = true}) {
    if (_isClosing) {
      return;
    }
    _isClosing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _resetState();
      _stopAudio();

      await ref.read(dndProvider.notifier).setDndMode(false);
      _endScreenOpened = false;

      if (shouldPop && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _isClosing = false;
    });
  }

  void _stopAudio() {
    if (!_playRequested) return;
    _playRequested = false;
    ref.read(playerProvider.notifier).stop();
    ref.read(backgroundSoundsNotifierProvider.notifier).stopBackgroundSound();
  }

  void _resetState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(audioStateProvider.notifier).resetState();
    });
  }

  void _openEndScreen({VoidCallback? afterStop}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_endScreenOpened && mounted) {
        final endedNatively = ref.read(audioStateProvider).isCompleted;
        _resetState();
        // Native teardown owns the end bell tail; stopping here cuts it off.
        if (!endedNatively) _stopAudio();
        afterStop?.call();
        final currentlyPlayingTrack = ref.read(playerProvider);
        if (currentlyPlayingTrack == null) return;

        // handleStats (run from the platform on completion) has already
        // written the new completion to local stats and pushed it through
        // statsProvider via refreshFromLocal — so no refresh() is needed
        // here. We pass the pre-session snapshot so EndScreenView can
        // animate from the old streak to the current one.
        unawaited(ref.read(dndProvider.notifier).setDndMode(false));

        // pushReplacement swaps whatever route is on top. If a sheet (repeat,
        // speed, background sound) is open when the session ends, that would
        // replace the sheet and leave the player underneath, so back from the
        // end screen returned to the player. Close anything above the player
        // first so the end screen always replaces the player itself.
        final navigator = Navigator.of(context);
        final playerRoute = ModalRoute.of(context);
        if (playerRoute != null && playerRoute.isActive) {
          navigator.popUntil((route) => route == playerRoute);
        }

        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (context) => EndScreenView(
              request: currentlyPlayingTrack,
              priorStats: _statsAtSessionStart,
            ),
          ),
        );

        _endScreenOpened = true;
      }
    });
  }
}

/// The production player surface, separated from playback lifecycle for previews.
/// Existing controls and their callbacks are shared at every window size.
class PlayerScreenLayout extends StatelessWidget {
  const PlayerScreenLayout({
    super.key,
    required this.currentlyPlayingTrack,
    required this.isPlaying,
    required this.isAudioLoading,
    required this.isBackgroundSoundSelected,
    required this.onPlayPausePressed,
    required this.onSpeedChanged,
    required this.onClosePressed,
    this.onEndSession,
  });

  final PlaybackRequest currentlyPlayingTrack;
  final bool isPlaying;
  final bool isAudioLoading;
  final bool isBackgroundSoundSelected;
  final VoidCallback onPlayPausePressed;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onClosePressed;

  /// Ends a timer session early and records it. Unused for tracks.
  final VoidCallback? onEndSession;

  @override
  Widget build(BuildContext context) {
    final title = currentlyPlayingTrack.title;
    final artistName = currentlyPlayingTrack.guideName;
    final artistUrl = currentlyPlayingTrack.artist?.path;
    final imageUrl = currentlyPlayingTrack.coverUrl;
    final attribution = currentlyPlayingTrack.attribution;
    final isTimer = currentlyPlayingTrack.isTimer;
    final isStopwatch =
        isTimer && currentlyPlayingTrack.timerMode == TimerMode.stopwatch;
    // A timer ends with the stop button; tracks keep their repeat control.
    final onStop = isTimer ? onEndSession : null;
    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final expanded =
              constraints.maxWidth >= 700 && constraints.maxHeight >= 440;
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // A session with no picture: its calm generated art,
                    // blurred like a cover.
                    if (imageUrl.isEmpty && !isTimer)
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: GeneratedArtwork(seed: title),
                      ),
                    // No cover (a timer): a dark backdrop so the white
                    // controls read the same as over a blurred cover.
                    if (imageUrl.isEmpty && isTimer)
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              ColorConstants.onyx,
                              ColorConstants.greyIsTheNewBlack,
                            ],
                          ),
                        ),
                      ),
                    if (imageUrl.isNotEmpty)
                      // ImageFiltered (not BackdropFilter) — blurs only the
                      // cover image itself, never the screen behind. Using
                      // BackdropFilter here leaks the underlying route
                      // during pop animations, blurring the previous screen
                      // for a frame.
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: _FadingNetworkImage(imageUrl: imageUrl),
                      ),
                    Container(
                      color: ColorConstants.black.withOpacityValue(0.3),
                    ),
                  ],
                ),
              ),
              RepaintBoundary(
                child: SafeArea(
                  child: Stack(
                    children: [
                      Center(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32.0,
                            ),
                            child: constraints.maxHeight >= 440
                                ? _PortraitPlayerLayout(
                                    expanded: expanded,
                                    title: title,
                                    artistName: artistName,
                                    artistUrl: artistUrl,
                                    attribution: attribution,
                                    totalDurationMs:
                                        currentlyPlayingTrack.duration,
                                    isPlaying: isPlaying,
                                    isLoading: isAudioLoading,
                                    onPlayPause: onPlayPausePressed,
                                    isStopwatch: isStopwatch,
                                    onStop: onStop,
                                  )
                                : ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1040,
                                    ),
                                    child: _LandscapePlayerLayout(
                                      title: title,
                                      artistName: artistName,
                                      artistUrl: artistUrl,
                                      attribution: attribution,
                                      totalDurationMs:
                                          currentlyPlayingTrack.duration,
                                      isPlaying: isPlaying,
                                      isLoading: isAudioLoading,
                                      onPlayPause: onPlayPausePressed,
                                      isStopwatch: isStopwatch,
                                      onStop: onStop,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      bottomNavigationBar: PlayerActionBar(
        request: currentlyPlayingTrack,
        isBackgroundSoundSelected: isBackgroundSoundSelected,
        onSpeedChanged: onSpeedChanged,
        onClosePressed: onClosePressed,
      ),
    );
  }
}

class _PortraitPlayerLayout extends ConsumerWidget {
  const _PortraitPlayerLayout({
    this.expanded = false,
    required this.title,
    required this.artistName,
    required this.artistUrl,
    this.attribution,
    required this.totalDurationMs,
    required this.isPlaying,
    required this.isLoading,
    required this.onPlayPause,
    this.isStopwatch = false,
    this.onStop,
  });

  final bool expanded;
  final String title;
  final String? artistName;
  final String? artistUrl;
  final SourceAttribution? attribution;
  final int totalDurationMs;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPlayPause;
  final bool isStopwatch;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptivePlayerLayout(
      expanded: expanded,
      heading: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ArtistTitleWidget(
            trackTitle: title,
            artistName: artistName ?? '',
            artistUrlPath: artistUrl,
            isPlayerScreen: true,
          ),
          if (attribution != null) _PlayerAttribution(attribution!),
        ],
      ),
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isStopwatch)
            const StopwatchElapsedWidget()
          else
            DurationIndicatorWidget(
              fallbackDurationMs: totalDurationMs,
              onSeekEnd: (value) {
                ref.read(playerProvider.notifier).seekToPosition(value);
              },
            ),
          const SizedBox(height: 24),
          PlayerButtonsWidget(
            isPlaying: isPlaying,
            isLoading: isLoading,
            onPlayPause: onPlayPause,
            onSkip10SecondsBackward: () =>
                ref.read(playerProvider.notifier).skip10SecondsBackward(),
            onSkip10SecondsForward: () =>
                ref.read(playerProvider.notifier).skip10SecondsForward(),
            isPortrait: true,
            showSkipButtons: !isStopwatch,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

class _LandscapePlayerLayout extends ConsumerWidget {
  const _LandscapePlayerLayout({
    required this.title,
    required this.artistName,
    required this.artistUrl,
    this.attribution,
    required this.totalDurationMs,
    required this.isPlaying,
    required this.isLoading,
    required this.onPlayPause,
    this.isStopwatch = false,
    this.onStop,
  });

  final String title;
  final String? artistName;
  final String? artistUrl;
  final SourceAttribution? attribution;
  final int totalDurationMs;
  final bool isPlaying;
  final bool isLoading;
  final VoidCallback onPlayPause;
  final bool isStopwatch;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ArtistTitleWidget(
          trackTitle: title,
          artistName: artistName ?? '',
          artistUrlPath: artistUrl,
          isPlayerScreen: true,
        ),
        if (attribution != null) _PlayerAttribution(attribution!),
        if (isStopwatch)
          const StopwatchElapsedWidget()
        else
          DurationIndicatorWidget(
            fallbackDurationMs: totalDurationMs,
            onSeekEnd: (value) {
              ref.read(playerProvider.notifier).seekToPosition(value);
            },
          ),
        PlayerButtonsWidget(
          isPlaying: isPlaying,
          isLoading: isLoading,
          onPlayPause: onPlayPause,
          onSkip10SecondsBackward: () =>
              ref.read(playerProvider.notifier).skip10SecondsBackward(),
          onSkip10SecondsForward: () =>
              ref.read(playerProvider.notifier).skip10SecondsForward(),
          isPortrait: false,
          showSkipButtons: !isStopwatch,
          onStop: onStop,
        ),
      ],
    );
  }
}

/// The credit and licence a track's source asks for, under the title: one
/// quiet, centred line whose parts open the talk's page and the licence.
class _PlayerAttribution extends StatelessWidget {
  const _PlayerAttribution(this.attribution);

  final SourceAttribution attribution;

  @override
  Widget build(BuildContext context) {
    return AttributionNotice(
      attribution: attribution,
      compact: true,
      alignment: CrossAxisAlignment.center,
      color: ColorConstants.white.withOpacityValue(0.8),
      padding: const EdgeInsets.only(bottom: 8),
    );
  }
}

class _FadingNetworkImage extends StatefulWidget {
  final String imageUrl;

  const _FadingNetworkImage({required this.imageUrl});

  @override
  State<_FadingNetworkImage> createState() => _FadingNetworkImageState();
}

class _FadingNetworkImageState extends State<_FadingNetworkImage> {
  bool _imageLoaded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? ColorConstants.greyIsTheNewGrey
        : ColorConstants.lightBackground;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Grey background while loading
        Container(color: backgroundColor),

        // Network image with fade-in effect
        AnimatedOpacity(
          opacity: _imageLoaded ? 1.0 : 0.0,
          duration: const Duration(seconds: 2),
          child: Image.network(
            widget.imageUrl,
            fit: BoxFit.cover,
            // Blurred backdrop: decorative.
            excludeFromSemantics: true,
            cacheWidth: MediaQuery.of(context).size.width.toInt(),
            errorBuilder: (context, error, stackTrace) {
              return Container(color: backgroundColor);
            },
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (frame != null && !_imageLoaded) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _imageLoaded = true;
                    });
                  }
                });
              }
              return child;
            },
          ),
        ),
      ],
    );
  }
}
