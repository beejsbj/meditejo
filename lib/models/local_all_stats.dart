import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:medito/models/local_audio_completed.dart';

part 'local_all_stats.g.dart';

// Keep persisted field names compatible with existing on-device histories.
// Legacy freeze fields remain readable so old streak history is preserved.

@JsonSerializable()
class LocalAllStats {
  static const int defaultMaxStreakFreezes = 2;

  final int streakCurrent;
  final int streakLongest;
  final int totalTracksCompleted;
  final int totalTimeListened;
  final List<String>? tracksChecked;
  final List<LocalAudioCompleted>? audioCompleted;
  final int updated;
  final int? streakFreezes;
  final int? maxStreakFreezes;
  @JsonKey(defaultValue: [])
  final List<int> freezeUsageDates;
  final double consistencyScore;

  /// Durable acknowledgements saved atomically with counters/history. IDs are
  /// JSON arrays [kind, trackId, originalEndTimestampMs], with kind either
  /// 'completion' or 'repeat'. Use the original timestamp, before midnight
  /// attribution. Retain receipts after session deletion to prevent replay
  /// resurrecting it. Old histories default to an empty list.
  @JsonKey(defaultValue: [])
  final List<String> completionReceipts;

  LocalAllStats({
    required this.streakCurrent,
    required this.streakLongest,
    required this.totalTracksCompleted,
    required this.totalTimeListened,
    required this.tracksChecked,
    required this.audioCompleted,
    required this.updated,
    this.streakFreezes = 0,
    this.maxStreakFreezes = 0,
    required this.freezeUsageDates,
    this.consistencyScore = 0,
    this.completionReceipts = const [],
  });

  factory LocalAllStats.empty() {
    return LocalAllStats(
      streakCurrent: 0,
      streakLongest: 0,
      totalTracksCompleted: 0,
      totalTimeListened: 0,
      tracksChecked: [],
      audioCompleted: [],
      updated: 0,
      streakFreezes: 1,
      maxStreakFreezes: defaultMaxStreakFreezes,
      freezeUsageDates: [],
      consistencyScore: 0,
    );
  }

  factory LocalAllStats.fromJson(Map<String, dynamic> json) =>
      _$LocalAllStatsFromJson(json);

  Map<String, dynamic> toJson() => _$LocalAllStatsToJson(this);

  LocalAllStats copyWith({
    int? streakCurrent,
    int? streakLongest,
    int? totalTracksCompleted,
    int? totalTimeListened,
    List<String>? tracksChecked,
    List<LocalAudioCompleted>? audioCompleted,
    int? updated,
    int? streakFreezes,
    int? maxStreakFreezes,
    List<int>? freezeUsageDates,
    double? consistencyScore,
    List<String>? completionReceipts,
  }) {
    return LocalAllStats(
      streakCurrent: streakCurrent ?? this.streakCurrent,
      streakLongest: streakLongest ?? this.streakLongest,
      totalTracksCompleted: totalTracksCompleted ?? this.totalTracksCompleted,
      totalTimeListened: totalTimeListened ?? this.totalTimeListened,
      tracksChecked: tracksChecked ?? this.tracksChecked,
      audioCompleted: audioCompleted ?? this.audioCompleted,
      updated: updated ?? this.updated,
      streakFreezes: streakFreezes ?? this.streakFreezes,
      maxStreakFreezes: maxStreakFreezes ?? this.maxStreakFreezes,
      freezeUsageDates: freezeUsageDates ?? this.freezeUsageDates,
      consistencyScore: consistencyScore ?? this.consistencyScore,
      completionReceipts: completionReceipts ?? this.completionReceipts,
    );
  }
}
