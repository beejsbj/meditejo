/// [title] without a livestream's schedule at its end (pass 4): John
/// Vervaeke's titles end "-Livestream Mon-Fri 09:30 EST", "- Live Stream
/// Mon-Fri at 09:30 EST", "- Stream Mon-Fri 9:30 EST" and the like. Burooj
/// saw it in lists, the player, Continue and search, where [episodeTitle]
/// (which needs the course's other titles, all spelled alike) does not
/// reach. The schedule goes only when it ends the title and something is
/// left before it.
String withoutSchedule(String title) {
  final match = _schedule.firstMatch(title);
  if (match == null || match.start == 0) return title;
  final rest = title.substring(0, match.start).trimRight();
  return rest.replaceAll(RegExp(r'[\p{L}\p{N}]', unicode: true), '').length ==
          rest.length
      ? title
      : rest;
}

/// "Live", "Livestream", "Live stream" or "Stream", then days ("Mon-Fri",
/// "Mondays", "Mon & Wed"), then a time ("09:30", "9.30am") and an
/// optional zone, at the end, after an optional separator.
final _schedule = RegExp(
  r'\s*(?:[-–—|｜:·•]\s*)?\b(?:live\s*-?\s*stream(?:ed|ing|s)?|live|streams?)'
  r'\s+(?:on\s+|every\s+)?'
  r'(?:mon|tue|wed|thu|fri|sat|sun|week)[a-z]*\.?'
  r'(?:\s*(?:[-–/&,]|to|and)\s*(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\.?)*'
  r'\s*(?:at\s+|@\s*)?\d{1,2}(?:[:.]\d{2})?\s*(?:[ap]\.?m\.?)?'
  r'(?:\s*[a-z]{2,4})?\s*$',
  caseSensitive: false,
);

/// An episode's title as its own page shows it (#84): without the words
/// every episode of its course repeats ("Meditating with John Vervaeke:",
/// "| Livestream Mon-Fri 09:30 EST"), which the page already says once in
/// its course line.
///
/// What all of [siblings] (the course's episode titles, this one among
/// them) share at the start or at the end is cut, but only:
/// - at a separator (":", "|", "·", "—", " - ", " – ") that lies wholly in
///   the shared part, so "Day 1" never loses its number to "Day 10", and
///   never one inside brackets or quotes;
/// - when the words cut are mostly the course's name or the teacher's
///   ([courseTitle], [teacher]), or, at the end only, the course is long
///   enough ([_noiseAt] episodes) that what all of them repeat is noise
///   ("| Livestream Mon-Fri 09:30 EST");
/// - never when the words cut are a session's kind ("Talk", "Meditation
///   Instructions"), which is what tells the episodes apart.
///
/// A course of one episode still loses the course's own name from the
/// front. What is left must be more than a kind word ("Talk") and must not
/// leave a bracket open; otherwise the title is shown whole.
String episodeTitle(
  String title, {
  String? courseTitle,
  String? teacher,
  Iterable<String> siblings = const [],
}) {
  final whole = withoutSchedule(title.trim());
  final others = [
    for (final s in siblings)
      if (s.trim().isNotEmpty) withoutSchedule(s.trim()),
  ];
  final names = [
    for (final n in [courseTitle, teacher])
      if (_norm(n ?? '').isNotEmpty) _norm(n!),
  ];
  // A name may always go: the page says it elsewhere. A front that is not
  // one is often the series' own ("Learning How To Live: Part 1" in a
  // retreat named for something else): it stays. A repeated tail in a long
  // course is noise, unless it is a kind of session.
  _Cut cutOf(String words, {required bool front}) {
    final dropped = _norm(words);
    if (dropped.isEmpty) return _Cut.none;
    if (names.any((name) => _mostly(dropped, name))) return _Cut.name;
    if (_isKind(dropped)) return _Cut.none;
    return !front && others.length >= _noiseAt ? _Cut.noise : _Cut.none;
  }

  // Whether anything but a name was cut: then what is left must be more
  // than a kind word ("Talk"). Cutting only a name is always safe
  // ("Walking Meditation | Plum Village" by Plum Village).
  var cutNoise = false;

  var start = 0;
  var end = whole.length;
  if (others.length > 1) {
    final prefix = _commonPrefix(others);
    if (prefix.isNotEmpty && whole.startsWith(prefix)) {
      final cut = _lastSeparatorWithin(whole, prefix.length);
      final kind = cut == null
          ? _Cut.none
          : cutOf(whole.substring(0, cut.start), front: true);
      if (kind != _Cut.none) {
        start = cut!.end;
        cutNoise = kind == _Cut.noise;
      }
    }
    final suffix = _commonSuffix(others);
    if (suffix.isNotEmpty && whole.endsWith(suffix)) {
      final cut = _firstSeparatorFrom(whole, whole.length - suffix.length);
      final kind = cut == null || cut.start <= start
          ? _Cut.none
          : cutOf(whole.substring(cut.end), front: false);
      if (kind != _Cut.none) {
        end = cut!.start;
        cutNoise = cutNoise || kind == _Cut.noise;
      }
    }
  }
  if (start == 0) {
    // The course's own name in front, whatever the other titles say.
    final course = (courseTitle ?? '').trim();
    if (course.isNotEmpty &&
        whole.length > course.length &&
        whole.toLowerCase().startsWith(course.toLowerCase())) {
      for (final m in _separator.allMatches(whole)) {
        if (m.start < course.length) continue;
        if (m.start == course.length && m.end < end) start = m.end;
        break;
      }
    }
  }
  if (start == 0 && end == whole.length) return whole;
  if (end <= start) return whole;
  final rest = whole.substring(start, end).trim();
  // "Day 7" is a title; "7" or "(Note" is not, nor "Talk" once more than a
  // name was cut, nor what is left of a title that was all the course's
  // name ("Releasing, Receiving and Awakening Our Life - A Dana Retreat" in
  // that retreat).
  final course = _norm(courseTitle ?? '');
  if (rest.replaceAll(RegExp(r'[^\p{L}]', unicode: true), '').length < 2 ||
      (cutNoise && _isKind(_norm(rest))) ||
      !_balanced(rest) ||
      (course.isNotEmpty && _mostly(_norm(rest), course))) {
    return whole;
  }
  return rest;
}

/// Below this many episodes a course's repeated words are only cut when
/// they are its name or its teacher's.
const _noiseAt = 5;

/// What a shared part of the titles is, if it may go: a name (the course's
/// or the teacher's) or, at the end of a long course's titles, noise.
enum _Cut { none, name, noise }

/// A separator between a title's parts: a colon or bar (also fullwidth),
/// a dot, an em dash, or a hyphen or en dash with spaces round it. Not the
/// colon in "09:30" or the dash in "Mon-Fri".
final _separator = RegExp(r'\s*(?::(?=\s)|：|\||｜|·|•|—|\s[-–](?=\s))\s*');

/// What a session is, rather than what it is about: left alone, it says
/// nothing; cut, the episodes cannot be told apart.
final _kind = RegExp(
  r'^(?:(?:guided |dharma |dhamma |morning |evening |afternoon |opening |closing )?'
  r'(?:talks?|meditations?|meditation instructions?|instructions?|'
  r'questions(?: and answers)?|q and a|q a|qa|chanting|chants?|'
  r'reflections?|practice|discussion|sits?|sitting|opening|closing|'
  r'morning|evening)|opening talk|closing talk|'
  r'walking meditation|metta|metta meditation)(?: session)?(?: \d+)?$',
);

bool _isKind(String normalized) => _kind.hasMatch(normalized);

/// Lower case, "&" as "and", only letters, digits and single spaces.
String _norm(String s) => s
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Whether the [dropped] words are mostly the name [name] (both
/// normalized): at least 60% of them are words of the name ("Equanimity
/// Daylong" of "Equanimity - In the Dharma & In Your Brain (Daylong)",
/// "2019 3CE Retreat" of "2019 Three Characteristics of Existence
/// Retreat").
bool _mostly(String dropped, String name) {
  final words = dropped.split(' ');
  final named = name.split(' ').toSet();
  return words.where(named.contains).length * 10 >= words.length * 6;
}

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

/// The last separator wholly within [title]'s first [shared] characters,
/// not at its very start and not inside brackets or quotes.
Match? _lastSeparatorWithin(String title, int shared) {
  Match? cut;
  for (final m in _separator.allMatches(title)) {
    if (m.end > shared) break;
    if (m.start > 0 && _balanced(title.substring(0, m.start))) cut = m;
  }
  return cut;
}

/// The first separator wholly within [title] from [from] on, not inside
/// brackets or quotes.
Match? _firstSeparatorFrom(String title, int from) {
  for (final m in _separator.allMatches(title)) {
    if (m.start < from || m.start == 0) continue;
    if (_balanced(title.substring(0, m.start))) return m;
  }
  return null;
}

/// Whether every bracket opened in [s] is closed and its double quotes
/// pair up. A quote [s] opens, or a bracket, makes a separator after it
/// part of what is quoted.
bool _balanced(String s) {
  var round = 0;
  var square = 0;
  var guillemets = 0;
  var quotes = 0;
  for (final c in s.split('')) {
    switch (c) {
      case '(':
        round++;
      case ')':
        round--;
      case '[':
        square++;
      case ']':
        square--;
      case '«':
        guillemets++;
      case '»':
        guillemets--;
      // “…”, „…“ and "…" each come in pairs.
      case '"' || '“' || '”' || '„':
        quotes++;
    }
  }
  return round == 0 && square == 0 && guillemets == 0 && quotes.isEven;
}
