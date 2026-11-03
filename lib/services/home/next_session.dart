import 'package:medito/models/pack/pack_model.dart';

/// The session a course offers next, and whether offering it is a resume.
class NextSession {
  const NextSession({
    required this.item,
    required this.completedCount,
    this.leftPartwayAt,
  });

  final PackItemsModel item;

  /// How many of the course's sessions are finished.
  final int completedCount;

  /// When the user last left [item] partway; null when it is untouched.
  final DateTime? leftPartwayAt;

  bool get isPartway => leftPartwayAt != null;

  /// Whether the label reads "Resume" rather than "Start": the user has
  /// finished something in this course or left this session partway.
  bool get isResume => isPartway || completedCount > 0;
}

/// The one rule for "which session next" in a course, shared by the course
/// page's play button and header and by Home's Continue.
///
/// A session left partway wins (the most recently left one when there are
/// several); otherwise it is the first session not yet finished. Null when
/// every playable session is finished (or there are none).
///
/// [partial] maps a session id to when the user last left it partway.
/// [completedIds] overrides each item's own `isCompleted` flag, for callers
/// that hold the finished set separately (Home reads it from stats).
/// Finished sessions are never offered, even with a stale partial mark.
NextSession? nextSessionFor(
  PackModel pack, {
  Map<String, DateTime> partial = const {},
  Set<String>? completedIds,
}) {
  bool isDone(PackItemsModel item) =>
      completedIds?.contains(item.id) ?? item.isCompleted == true;

  final tracks = pack.playableTracks;
  final completedCount = tracks.where(isDone).length;

  PackItemsModel? partway;
  for (final item in tracks) {
    if (isDone(item)) continue;
    final left = partial[item.id];
    if (left == null) continue;
    // Strictly newer wins; a tie keeps the earlier session in course order.
    if (partway == null || left.isAfter(partial[partway.id]!)) partway = item;
  }
  final item = partway ?? tracks.where((i) => !isDone(i)).firstOrNull;
  if (item == null) return null;
  return NextSession(
    item: item,
    completedCount: completedCount,
    leftPartwayAt: partial[item.id],
  );
}
