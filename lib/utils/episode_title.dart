/// An episode's title as its own page shows it (#84): without the words
/// every episode of its course repeats ("Meditating with John Vervaeke:",
/// "| Livestream Mon-Fri 09:30 EST"), which the page already says once in
/// its "Part of" line.
///
/// Cuts what all of [siblings] (the course's episode titles, this one among
/// them) share at the start and at the end, but only at a separator (":",
/// "|", "·", " - ", "–", "—"), so "Day 1" and "Day 12" never lose their
/// "Day". A course of one episode still loses the course's own name,
/// [courseTitle], when the title starts with it and a separator. What is
/// left must be a few letters, else the title is shown whole.
String episodeTitle(
  String title, {
  String? courseTitle,
  Iterable<String> siblings = const [],
}) {
  final whole = title.trim();
  final others = [
    for (final s in siblings)
      if (s.trim().isNotEmpty) s.trim(),
  ];
  var start = 0;
  var end = whole.length;
  if (others.length > 1) {
    final prefix = _commonPrefix(others);
    if (whole.startsWith(prefix)) start = _cutAfter(whole, prefix.length);
    final suffix = _commonSuffix(others);
    if (whole.endsWith(suffix)) {
      end = _cutBefore(whole, whole.length - suffix.length);
    }
  }
  if (start == 0) {
    final course = (courseTitle ?? '').trim().toLowerCase();
    if (course.isNotEmpty && whole.toLowerCase().startsWith(course)) {
      start = _cutAfter(whole, course.length);
    }
  }
  if (end <= start) return whole;
  final rest = whole.substring(start, end).trim();
  // "Day 7" is a title; "7" or "" is not.
  if (rest.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '').length < 2) {
    return whole;
  }
  return rest;
}

/// A separator between a title's parts: a colon or bar or dot, or a dash
/// with spaces round it. Not the colon in "09:30" or the dash in "Mon-Fri".
final _separator = RegExp(r'\s*(?::(?=\s)|\||·|•|\s[-–—](?=\s))\s*');

String _commonPrefix(List<String> titles) {
  var prefix = titles.first;
  for (final t in titles.skip(1)) {
    var i = 0;
    while (i < prefix.length && i < t.length && prefix[i] == t[i]) {
      i++;
    }
    prefix = prefix.substring(0, i);
    if (prefix.isEmpty) break;
  }
  return prefix;
}

String _commonSuffix(List<String> titles) {
  String reversed(String s) => String.fromCharCodes(s.runes.toList().reversed);
  return reversed(_commonPrefix([for (final t in titles) reversed(t)]));
}

/// Where [title]'s own words begin when its first [shared] characters are
/// shared: just past the last separator that starts inside them. 0 when
/// there is none.
int _cutAfter(String title, int shared) {
  var cut = 0;
  for (final m in _separator.allMatches(title)) {
    if (m.start > shared) break;
    if (m.start > 0) cut = m.end;
  }
  return cut;
}

/// Where [title]'s own words end when everything from [from] on is shared:
/// at the first separator that reaches into that part. The whole length
/// when there is none.
int _cutBefore(String title, int from) {
  for (final m in _separator.allMatches(title)) {
    if (m.end > from && m.start > 0) return m.start;
  }
  return title.length;
}
