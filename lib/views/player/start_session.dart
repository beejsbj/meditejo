import 'dart:async';

import 'package:medito/exceptions/app_error.dart';
import 'package:medito/utils/youtube_error_message.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/providers/meditation/track_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/resume_request.dart';
import 'package:medito/utils/track_variant_selector.dart';
import 'package:medito/views/player/player_view.dart';

/// Gets the user into [trackId] as fast as possible: straight into the player
/// when the track has nothing to choose or their preferred guide and duration
/// are known (resuming where they left off), otherwise via the track screen so
/// they can pick. Shared by Up Next and the pack screen's
/// Your Path button so both start sessions the same way.
Future<void> startSession(
  BuildContext context,
  WidgetRef ref, {
  required String trackId,
  required String path,
}) async {
  final guideName = ref.read(guideNamePreferenceProvider);
  final preferredDuration = ref.read(durationPreferenceProvider);

  try {
    if (trackId.startsWith('yt-video-')) {
      ref.invalidate(tracksProvider(trackId: trackId));
    }
    final track = await ref.read(tracksProvider(trackId: trackId).future);
    // A recording with one voice and one file has nothing to choose, so it
    // plays at once; only a track with real choices and no remembered
    // preference opens its page first.
    final onlyChoice =
        track.voices.length == 1 && track.voices.first.audioFiles.length == 1;
    if (!onlyChoice && (guideName == null || preferredDuration == null)) {
      if (!context.mounted) return;
      handleNavigation(TypeConstants.track, [trackId, path], context, ref: ref);
      return;
    }
    final selection = onlyChoice
        ? (voice: track.voices.first, file: track.voices.first.audioFiles.first)
        : TrackVariantSelector.resolve(
            track,
            guideName: guideName,
            durationMs: preferredDuration,
          );
    final request = await withResumePosition(
      ref,
      PlaybackRequest.fromTrack(track, selection.voice, selection.file),
    );
    if (!context.mounted) return;
    // Prepare + open the player immediately; PlayerView starts playback and
    // shows its own loading state. Callers' spinners cover only the fetch.
    ref.read(playerProvider.notifier).prepare(request);
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PlayerView()),
      ),
    );
  } catch (e, st) {
    // The track fetch failed (offline / bad response) so we never reached
    // the player — surface it rather than leaving a dead tap.
    AppLogger.e('START_SESSION', 'Failed to start session $trackId', e, st);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          e is YoutubeUnavailableError
              ? youtubeErrorMessage(AppLocalizations.of(context)!, e)
              : AppLocalizations.of(context)!.unableToLoadAudio,
        ),
      ),
    );
  }
}
