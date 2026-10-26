import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/services/my_courses/my_course_models.dart';

/// A line of detail for something listed beside other courses. What the user
/// makes is a Playlist in the UI (BRIEF decision 18) and leads with that word,
/// so a list of both kinds says which is which; a course keeps its own line.
String? playlistAwareDetail(AppLocalizations l10n, String id, String? detail) {
  if (!isMyCourseId(id)) return detail;
  return [
    l10n.playlistKind,
    if (detail != null && detail.isNotEmpty) detail,
  ].join(' · ');
}
