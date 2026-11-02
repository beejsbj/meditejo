/// dhammatalks.org identity: app IDs, public URLs and the licence.
///
/// Thanissaro Bhikkhu's talks are CC BY-NC 4.0: free to stream with credit,
/// never to sell. IDs carry the record kind and, for a talk, where it was
/// filed: `dt-talk-e-260131-a-slug` (evening), `dt-talk-m-…` (short morning
/// talk), `dt-talk-c-basics-01-…` (a file only a collection lists),
/// `dt-course-basics`, `dt-year-e-2025`, `dt-teacher-thanissaro`.
library;

const dhammatalksPrefix = 'dt-';
const _talkPrefix = 'dt-talk-';
const _coursePrefix = 'dt-course-';
const _yearPrefix = 'dt-year-';

/// The one teacher; the site is his.
const dtTeacherId = 'dt-teacher-thanissaro';
const dtTeacherName = 'Thanissaro Bhikkhu';

const dhammatalksSite = 'https://www.dhammatalks.org';
const dhammatalksLicenceName = 'CC BY-NC 4.0';
const dhammatalksLicenceUrl = 'https://creativecommons.org/licenses/by-nc/4.0/';

/// The two live RSS feeds, read when Explore opens.
const dtEveningFeedUrl = '$dhammatalksSite/rss/evening.xml';
const dtMorningFeedUrl = '$dhammatalksSite/rss/morning.xml';

/// Where a talk is filed on the site.
enum DtChannel {
  evening('e', 'evening', 'Evening talk'),
  morning('m', 'morning', 'Morning talk');

  const DtChannel(this.code, this.path, this.label);

  /// The letter in IDs and in the snapshot.
  final String code;

  /// The folder under `/audio/`.
  final String path;
  final String label;

  static DtChannel? fromCode(String code) {
    for (final channel in values) {
      if (channel.code == code) return channel;
    }
    return null;
  }
}

/// The code of a talk only a collection lists (it has no archive page).
const dtCollectionCode = 'c';

String dtTalkId(String code, String key) => '$_talkPrefix$code-$key';
String dtCourseId(String id) => '$_coursePrefix$id';
String dtYearId(DtChannel channel, int year) =>
    '$_yearPrefix${channel.code}-$year';

bool isDtTalkId(String id) => id.startsWith(_talkPrefix);
bool isDtCourseId(String id) => id.startsWith(_coursePrefix);
bool isDtYearId(String id) => id.startsWith(_yearPrefix);

String? parseDtCourseId(String id) =>
    isDtCourseId(id) && id.length > _coursePrefix.length
    ? id.substring(_coursePrefix.length)
    : null;

/// `(code, key)` of a talk ID, or null.
({String code, String key})? parseDtTalkId(String id) {
  if (!isDtTalkId(id)) return null;
  final rest = id.substring(_talkPrefix.length);
  final dash = rest.indexOf('-');
  if (dash != 1 || rest.length <= 2) return null;
  return (code: rest.substring(0, 1), key: rest.substring(2));
}

final _yearId = RegExp(r'^dt-year-([em])-(\d{4})$');

({DtChannel channel, int year})? parseDtYearId(String id) {
  final m = _yearId.firstMatch(id);
  if (m == null) return null;
  return (
    channel: DtChannel.fromCode(m.group(1)!)!,
    year: int.parse(m.group(2)!),
  );
}

/// Audio paths in the snapshot are site-relative; streams and downloads use
/// the original file unmodified.
String dtAudioUrl(String audioPath) {
  if (audioPath.isEmpty || audioPath.startsWith('http')) return audioPath;
  return '$dhammatalksSite${audioPath.startsWith('/') ? '' : '/'}$audioPath';
}

/// A talk's own page, for attribution. Empty for a file only a collection
/// lists, whose page is the collection's.
String dtTalkPageUrl(DtChannel channel, String key) {
  if (!RegExp(r'^\d{2}').hasMatch(key)) return '';
  return '$dhammatalksSite/audio/${channel.path}/20${key.substring(0, 2)}/$key.html';
}

/// The date a talk key names: `260131-…` is 2026-01-31, `0308n3-…` is
/// 2003-08, and anything else has none (empty).
String dtDateOfKey(String key) {
  final full = RegExp(r'^(\d{2})(\d{2})(\d{2})(?=$|[-_(])').firstMatch(key);
  if (full != null) {
    final yy = int.parse(full.group(1)!);
    final mm = int.parse(full.group(2)!);
    final dd = int.parse(full.group(3)!);
    final date = DateTime.utc(2000 + yy, mm, dd);
    if (date.month == mm && date.day == dd) {
      return '${2000 + yy}-${full.group(2)}-${full.group(3)}';
    }
  }
  final month = RegExp(r'^(\d{2})(\d{2})n\d').firstMatch(key);
  if (month != null) {
    final mm = int.parse(month.group(2)!);
    if (mm >= 1 && mm <= 12) return '20${month.group(1)}-${month.group(2)}';
  }
  return '';
}
