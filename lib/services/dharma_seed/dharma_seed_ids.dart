/// Dharma Seed identity: app IDs, public URLs and the content kind.
///
/// Talk, retreat and teacher numbers overlap on Dharma Seed, so app IDs carry
/// the record kind: `ds-talk-99944`, `ds-retreat-6689`, `ds-teacher-210`.
library;

const dharmaSeedPrefix = 'ds-';
const _talkPrefix = 'ds-talk-';
const _retreatPrefix = 'ds-retreat-';
const _teacherPrefix = 'ds-teacher-';

String dsTalkId(int id) => '$_talkPrefix$id';
String dsRetreatId(int id) => '$_retreatPrefix$id';
String dsTeacherId(int id) => '$_teacherPrefix$id';

int? parseDsTalkId(String id) => _parse(id, _talkPrefix);
int? parseDsRetreatId(String id) => _parse(id, _retreatPrefix);
int? parseDsTeacherId(String id) => _parse(id, _teacherPrefix);

int? _parse(String id, String prefix) =>
    id.startsWith(prefix) ? int.tryParse(id.substring(prefix.length)) : null;

const dharmaSeedSite = 'https://dharmaseed.org';
const dharmaSeedLicenceName = 'CC BY-NC-ND 4.0';
const dharmaSeedLicenceUrl =
    'https://creativecommons.org/licenses/by-nc-nd/4.0/';

/// Talk audio paths are site-relative; streams and downloads use the original
/// file unmodified.
String dsAudioUrl(String audioPath) {
  if (audioPath.isEmpty || audioPath.startsWith('http')) return audioPath;
  return '$dharmaSeedSite${audioPath.startsWith('/') ? '' : '/'}$audioPath';
}

/// The talk's own page, for attribution.
String dsTalkPageUrl(int talkId) => '$dharmaSeedSite/talks/$talkId/';

String dsTeacherPageUrl(int teacherId) => '$dharmaSeedSite/teacher/$teacherId/';

String dsRetreatPageUrl(int retreatId) => '$dharmaSeedSite/retreats/$retreatId/';

/// Teacher artwork, resized by Dharma Seed. Empty when the teacher has none.
String dsTeacherPhotoUrl(int teacherId, String photo, {int maxWidth = 400}) {
  if (photo.isEmpty) return '';
  return 'https://www.dharmaseed.org/api/1/teachers/$teacherId/'
      '${Uri.encodeComponent(photo)}/?maxW=$maxWidth';
}

/// What a recording is, from Dharma Seed's `recording_type`.
///
/// Observed values (2026-10-17): `Talk`, `Meditation`, `Q & A`, `Chanting`,
/// `Other`. Unknown values read as [other].
enum DharmaSeedKind {
  meditation('Guided meditation'),
  chanting('Chanting'),
  talk('Talk'),
  questions('Q & A'),
  other('Recording');

  const DharmaSeedKind(this.label);

  final String label;

  static DharmaSeedKind fromRecordingType(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'meditation' || 'guided meditation' => meditation,
        'chanting' => chanting,
        'talk' => talk,
        'q & a' || 'q&a' => questions,
        _ => other,
      };

  /// Practice is something you do along with the audio (the Explore
  /// "Practice" chip); everything else is listened to ("Talks").
  bool get isPractice => this == meditation || this == chanting;
}
