import 'package:flutter/foundation.dart';
import 'package:medito/services/library/library_models.dart';

/// One thing Home offers to carry on with: a session, with the course it
/// belongs to when it has one.
@immutable
class ContinueItem {
  const ContinueItem({
    required this.trackId,
    required this.path,
    required this.title,
    required this.group,
    required this.lastPlayed,
    this.courseId,
    this.courseTitle = '',
    this.coverUrl = '',
    this.resume,
    this.sessionNumber,
    this.sessionTotal,
    this.completedSessions = 0,
    this.subtitle = '',
  });

  final String trackId;
  final String path;
  final String title;
  final LibraryGroup group;

  /// When the user last played it (or its course).
  final DateTime lastPlayed;
  final String? courseId;
  final String courseTitle;
  final String coverUrl;

  /// Where the user stopped; null for the next session of a course.
  final ResumePoint? resume;

  /// "Session 4 of 18", when the session belongs to a course.
  final int? sessionNumber;
  final int? sessionTotal;

  /// Actual completions, independent of the offered session's ordinal.
  final int completedSessions;

  /// The session's own detail line (teacher, duration), if its source has one.
  final String subtitle;
}

/// How many Continue items Home shows.
const continueLimit = 3;

/// Practice first, then the most recently played; one item per course (the
/// best-ranked one), at most [limit] (null for all of them).
List<ContinueItem> rankContinue(
  Iterable<ContinueItem> items, {
  int? limit = continueLimit,
}) {
  final sorted = items.toList()
    ..sort((a, b) {
      final byGroup = a.group.index.compareTo(b.group.index);
      if (byGroup != 0) return byGroup;
      final byTime = b.lastPlayed.compareTo(a.lastPlayed);
      return byTime != 0 ? byTime : a.trackId.compareTo(b.trackId);
    });
  final seenCourses = <String>{};
  final ranked = [
    for (final item in sorted)
      if (item.courseId == null || seenCourses.add(item.courseId!)) item,
  ];
  return limit == null ? ranked : ranked.take(limit).toList();
}
