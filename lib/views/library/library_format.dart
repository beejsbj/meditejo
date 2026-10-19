/// "45 min", "1 h", "3 h 20 min". Units are the international abbreviations,
/// so the same text reads right in every language the app ships in.
String formatLongDuration(int milliseconds) {
  final minutes = (milliseconds / Duration.millisecondsPerMinute).round();
  if (milliseconds <= 0) return '';
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h' : '$hours h $rest min';
}

/// `m:ss` or `h:mm:ss`, for a position in a session.
String formatClock(int milliseconds) {
  final total = Duration(milliseconds: milliseconds).inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  final ss = seconds.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$ss'
      : '$minutes:$ss';
}
