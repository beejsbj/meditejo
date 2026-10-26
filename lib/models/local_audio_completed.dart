import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:medito/models/stats/all_stats_model.dart';

part 'local_audio_completed.g.dart';

/// One practised session in the local history.
///
/// Only [timestamp] and [id] existed at first. [durationMs], [kind],
/// [courseId] and [courseTitle] are recorded from the release that added the
/// stats page onwards; earlier entries read back as null and are never
/// back-filled, so the stats say "no recorded length" rather than guess.
@JsonSerializable()
class LocalAudioCompleted {
  final int timestamp;
  final String id;

  /// How long the session ran, in milliseconds (a timer's own length, a
  /// recording's full length, a manual entry's minutes). Null before it was
  /// recorded.
  final int? durationMs;

  /// `practice` or `talks` ([kindPractice], [kindTalks]); null when unknown.
  final String? kind;

  /// The course the session was played from, and its title as it was then
  /// (so removing the course does not blank the history). Null for a single.
  final String? courseId;
  final String? courseTitle;

  static const kindPractice = 'practice';
  static const kindTalks = 'talks';

  LocalAudioCompleted({
    required this.timestamp,
    required this.id,
    this.durationMs,
    this.kind,
    this.courseId,
    this.courseTitle,
  });

  factory LocalAudioCompleted.fromJson(Map<String, dynamic> json) =>
      _$LocalAudioCompletedFromJson(json);
  Map<String, dynamic> toJson() => _$LocalAudioCompletedToJson(this);

  // Convert from API model to local model
  factory LocalAudioCompleted.fromAudioCompleted(
    AudioCompleted audioCompleted,
  ) {
    return LocalAudioCompleted(
      timestamp: audioCompleted.timestamp,
      id: audioCompleted.id,
    );
  }

  // Convert to API model
  AudioCompleted toAudioCompleted() {
    return AudioCompleted(timestamp: timestamp, id: id);
  }

  LocalAudioCompleted copyWith({
    int? timestamp,
    String? id,
    int? durationMs,
    String? kind,
    String? courseId,
    String? courseTitle,
  }) {
    return LocalAudioCompleted(
      timestamp: timestamp ?? this.timestamp,
      id: id ?? this.id,
      durationMs: durationMs ?? this.durationMs,
      kind: kind ?? this.kind,
      courseId: courseId ?? this.courseId,
      courseTitle: courseTitle ?? this.courseTitle,
    );
  }
}
