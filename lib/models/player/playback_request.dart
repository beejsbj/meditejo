import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/track/track.dart';

part 'playback_request.freezed.dart';
part 'playback_request.g.dart';

/// Everything the player needs to start (and keep showing) a track: a single
/// resolved voice + length variant, plus enough metadata to render the player
/// UI, lock screen, and notification without reaching back into the full
/// [Track] graph.
@freezed
abstract class PlaybackRequest with _$PlaybackRequest {
  const factory PlaybackRequest({
    required String trackId,
    required String fileId,
    required String title,
    required String description,
    required String coverUrl,
    required String remoteUrl,
    required int duration,
    required bool hasBackgroundSound,
    String? guideName,
    TrackArtist? artist,
    SourceAttribution? attribution,

    /// Where to start, when the user is resuming a session they left. Zero
    /// starts from the beginning.
    @Default(0) int startPositionMs,

    /// The background sound for this session only, in
    /// [SoundscapeSelection]'s grammar (`preset:<id>`, `sound:<id>`, …), for
    /// a start that names its own (Home's preset tiles). Null follows the
    /// session's Customize choice and the kind's default as usual.
    String? soundscape,
  }) = _PlaybackRequest;

  factory PlaybackRequest.fromJson(Map<String, Object?> json) =>
      _$PlaybackRequestFromJson(json);

  factory PlaybackRequest.fromTrack(
    Track track,
    TrackVoice voice,
    TrackAudioFile file,
  ) => PlaybackRequest(
    trackId: track.id,
    fileId: file.id,
    title: track.title,
    description: track.description,
    coverUrl: track.coverUrl,
    remoteUrl: file.path,
    duration: file.duration,
    hasBackgroundSound: track.hasBackgroundSound,
    guideName: voice.guideName,
    artist: track.artist,
    attribution: track.attribution,
  );
}

extension PlaybackRequestSoundscape on PlaybackRequest {
  /// [PlaybackRequest.soundscape] as a selection; null when the request
  /// names none (or names one this version can't read).
  SoundscapeSelection? get soundscapeSelection {
    final value = soundscape;
    return value == null ? null : SoundscapeSelection.tryParse(value);
  }
}
