import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/audio/timer_audio_file.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/player/player_view.dart';

/// The timer's cue scope: kind-wide Practice settings.
const timerCueScope = CueScope(CueKind.practice);

/// The timer's length now: its countdown in minutes, or the stopwatch.
Duration timerDuration(WidgetRef ref) =>
    ref.read(timerSettingsProvider).mode == TimerMode.stopwatch
    ? kStopwatchMaxDuration
    : Duration(
        minutes: ref.read(cueSettingsProvider(timerCueScope)).durationMinutes,
      );

var _starting = false;

/// Starts a timer session as the Timer screen is set (mode, length, cues)
/// and opens the player. [soundscape] plays under this session only; the
/// user's saved choices are left as they are. Returns false if the silent
/// timer file could not be prepared (the user is told).
Future<bool> startTimerSession(
  BuildContext context,
  WidgetRef ref, {
  SoundscapeSelection? soundscape,
}) async {
  // One start at a time, whichever screen asked: a double tap on a Home tile
  // must not push two players.
  if (_starting) return false;
  _starting = true;
  try {
    return await _startTimerSession(context, ref, soundscape);
  } finally {
    _starting = false;
  }
}

Future<bool> _startTimerSession(
  BuildContext context,
  WidgetRef ref,
  SoundscapeSelection? soundscape,
) async {
  final l10n = AppLocalizations.of(context)!;
  final mode = ref.read(timerSettingsProvider).mode;
  final duration = timerDuration(ref);
  unawaited(HapticFeedback.mediumImpact());
  try {
    final path = await TimerAudioFile.prepare(duration);
    if (!context.mounted) return false;
    ref
        .read(playerProvider.notifier)
        .prepare(
          timerPlaybackRequest(
            mode: mode,
            duration: duration,
            filePath: path,
            title: mode == TimerMode.stopwatch
                ? l10n.timerModeStopwatch
                : l10n.timerTitle,
            soundscape: soundscape?.encode(),
          ),
        );
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PlayerView()),
      ),
    );
    return true;
  } catch (e, st) {
    AppLogger.e('TIMER', 'Failed to start timer', e, st);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.unableToLoadAudio)));
    }
    return false;
  }
}
