import 'package:flutter/foundation.dart';

/// What a library entry is.
enum LibraryKind {
  /// An ordered multi-session pack with progress.
  course,

  /// One recording.
  single,

  /// A Dharma Seed teacher the user follows; listed apart from the rest.
  teacher;

  static LibraryKind parse(String? value) =>
      values.firstWhere((k) => k.name == value, orElse: () => single);
}

/// Practice is something done along with the audio; Talks is listened to.
/// Practice leads everywhere, and is the default when nothing says otherwise.
enum LibraryGroup {
  practice,
  talks;

  static LibraryGroup? tryParse(String? value) {
    for (final group in values) {
      if (group.name == value) return group;
    }
    return null;
  }
}

/// One thing in the user's library, as the screens read it.
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.sourceId,
    required this.kind,
    required this.detectedGroup,
    required this.title,
    required this.addedAt,
    this.groupOverride,
    this.titleOverride,
    this.subtitle = '',
    this.coverUrl = '',
    this.itemCount = 1,
    this.durationMs = 0,
    this.lastPlayedAt,
  });

  final String sourceId;
  final LibraryKind kind;
  final LibraryGroup detectedGroup;
  final LibraryGroup? groupOverride;
  final String title;
  final String? titleOverride;
  final String subtitle;
  final String coverUrl;
  final int itemCount;
  final int durationMs;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;

  /// The user's choice if they made one, otherwise what the app detected.
  LibraryGroup get group => groupOverride ?? detectedGroup;

  String get displayTitle {
    final override = titleOverride?.trim();
    return override == null || override.isEmpty ? title : override;
  }

  /// When the user last touched this: played it, or else added it. Library
  /// lists put the most recent first.
  DateTime get lastActivity {
    final played = lastPlayedAt;
    return played != null && played.isAfter(addedAt) ? played : addedAt;
  }

  bool get isCourse => kind == LibraryKind.course;
}

/// What is needed to put something in the library; the store adds the time.
@immutable
class LibraryDraft {
  const LibraryDraft({
    required this.sourceId,
    required this.kind,
    required this.title,
    this.group = LibraryGroup.practice,
    this.subtitle = '',
    this.coverUrl = '',
    this.itemCount = 1,
    this.durationMs = 0,
    this.addedAt,
  });

  final String sourceId;
  final LibraryKind kind;
  final String title;
  final LibraryGroup group;
  final String subtitle;
  final String coverUrl;
  final int itemCount;
  final int durationMs;

  /// Only set when migrating an older save, to keep its original time.
  final DateTime? addedAt;
}

/// Where the user stopped in a session.
@immutable
class ResumePoint {
  const ResumePoint({
    required this.positionMs,
    required this.durationMs,
    this.fileId = '',
  });

  final int positionMs;
  final int durationMs;

  /// The audio file this place is in; empty when it was not recorded.
  final String fileId;

  /// Whether this place is in [file] (or was recorded without one).
  bool appliesTo(String file) => fileId.isEmpty || fileId == file;

  Duration get position => Duration(milliseconds: positionMs);
}
