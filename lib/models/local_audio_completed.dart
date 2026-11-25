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

  /// Real time, in milliseconds: the recording length at the speeds it was
  /// heard at (pauses do not count): a 60-minute talk heard at 2x is 30
  /// minutes here and 60 in [durationMs]. Recorded from the release that added per-kind speed
  /// onwards; null on older entries and on timers and manual entries, which
  /// read as [durationMs] (see [realOrDurationMs]). Never back-filled.
  final int? realMs;

  /// `practice` or `talks` ([kindPractice], [kindTalks]); null when unknown.
  final String? kind;

  /// The course the session was played from, and its title as it was then
  /// (so removing the course does not blank the history). Null for a single.
  final String? courseId;
  final String? courseTitle;

  static const kindPractice = 'practice';
  static const kindTalks = 'talks';

  /// Real time if it was recorded, else the recorded length (an older entry,
  /// a timer, a manual entry: their real time is their length). Before
  /// per-kind speed, recordings were 1x unless slowed to 0.6x-0.9x, which the
  /// history cannot tell: those read a little short here.
  int? get realOrDurationMs => realMs ?? durationMs;

  LocalAudioCompleted({
    required this.timestamp,
    required this.id,
    this.durationMs,
    this.realMs,
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
    int? realMs,
    String? kind,
    String? courseId,
    String? courseTitle,
  }) {
    return LocalAudioCompleted(
      timestamp: timestamp ?? this.timestamp,
      id: id ?? this.id,
      durationMs: durationMs ?? this.durationMs,
      realMs: realMs ?? this.realMs,
      kind: kind ?? this.kind,
      courseId: courseId ?? this.courseId,
      courseTitle: courseTitle ?? this.courseTitle,
    );
  }
}
