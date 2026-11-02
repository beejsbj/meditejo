import 'dart:convert';

import 'package:medito/services/hermes_amara/hermes_amara_ids.dart';

/// One talk from the Hermes Amāra audio listing.
class HaTalk {
  const HaTalk({
    required this.slug,
    required this.title,
    this.date = '',
    this.event = '',
    this.ordinal,
    this.durationMs = 0,
    this.tags = const [],
    this.author = '',
    this.practice = false,
  });

  final String slug;
  final String title;

  /// `yyyy-MM-dd`, or empty.
  final String date;

  /// The retreat or event it was given at; empty for a talk given alone.
  final String event;

  /// Its place within the event.
  final int? ordinal;
  final int durationMs;

  /// `basic_tags` and `ext_tags` together.
  final List<String> tags;

  /// The record's own author, when it names one (else Rob Burbea).
  final String author;

  /// Whether the talk is practice to do along with, by [isHaPractice].
  final bool practice;

  String get id => haTalkId(slug);
  String get audioUrl => haAudioUrl(slug);
  String get pageUrl => haTalkPageUrl(slug);

  /// Everything a change to the record would change, for noticing a refresh.
  String get fingerprint => [
    slug,
    title,
    date,
    event,
    ordinal,
    durationMs,
    tags.join('|'),
    author,
  ].join('\u0001');
}

/// A retreat or event with its talks in `ordinal`, then date, order.
class HaEvent {
  const HaEvent({required this.name, required this.slug, required this.talks});

  final String name;
  final String slug;
  final List<HaTalk> talks;

  String get id => haRetreatId(slug);
  int get durationMs => talks.fold(0, (sum, t) => sum + t.durationMs);

  /// The date of its latest talk.
  String get latestDate => talks.fold(
    '',
    (latest, t) => t.date.compareTo(latest) > 0 ? t.date : latest,
  );

  /// Practice when at least half its talks are.
  bool get practice =>
      talks.where((t) => t.practice).length * 2 >= talks.length;
}

/// What the listing page holds.
class HaListing {
  HaListing({this.talks = const [], this.events = const []})
    : _talksBySlug = {for (final t in talks) t.slug: t},
      _eventsBySlug = {for (final e in events) e.slug: e};

  static final empty = HaListing();

  final Map<String, HaTalk> _talksBySlug;
  final Map<String, HaEvent> _eventsBySlug;

  HaTalk? talk(String slug) => _talksBySlug[slug];
  HaEvent? event(String slug) => _eventsBySlug[slug];

  /// Newest first.
  final List<HaTalk> talks;
  final List<HaEvent> events;

  bool get isEmpty => talks.isEmpty;

  /// A string that differs when any talk does.
  String get fingerprint => talks.map((t) => t.fingerprint).join('\n');
}

final _nextData = RegExp(
  r'<script[^>]*\bid="__NEXT_DATA__"[^>]*>(.*?)</script>',
  dotAll: true,
);

/// Reads the talks out of the audio page's `__NEXT_DATA__` JSON
/// (`props.pageProps.data`). A page that is not that, or JSON that is not
/// what was expected, gives an empty listing; a record with no slug or title
/// is skipped; a missing field is just absent.
HaListing parseHermesListing(String html) {
  final match = _nextData.firstMatch(html);
  if (match == null) return HaListing.empty;
  final Object? json;
  try {
    json = jsonDecode(match.group(1)!);
  } catch (_) {
    return HaListing.empty;
  }
  final data = switch (json) {
    {'props': {'pageProps': {'data': final List<Object?> list}}} => list,
    _ => const <Object?>[],
  };

  final seen = <String>{};
  final talks = <HaTalk>[];
  for (final record in data) {
    if (record is! Map<String, Object?>) continue;
    final slug = _text(record['slug']);
    final title = _text(record['title']);
    if (slug.isEmpty || title.isEmpty || !seen.add(slug)) continue;
    final tags = [
      ..._split(_text(record['basic_tags'])),
      ..._split(_text(record['ext_tags'])),
    ];
    talks.add(
      HaTalk(
        slug: slug,
        title: title,
        date: _date(record['date']),
        event: _text(record['event']),
        ordinal: int.tryParse(_text(record['ordinal'])),
        durationMs: parseHaDuration(_text(record['duration'])),
        tags: tags,
        author: _text(record['author']),
        practice: isHaPractice(
          title: title,
          event: _text(record['event']),
          tags: tags,
        ),
      ),
    );
  }
  talks.sort((a, b) => b.date.compareTo(a.date));

  final byEvent = <String, List<HaTalk>>{};
  final names = <String, String>{};
  for (final talk in talks) {
    if (talk.event.isEmpty) continue;
    final slug = haEventSlug(talk.event);
    if (slug.isEmpty) continue;
    names.putIfAbsent(slug, () => talk.event);
    (byEvent[slug] ??= []).add(talk);
  }
  final events = [
    for (final entry in byEvent.entries)
      HaEvent(
        name: names[entry.key]!,
        slug: entry.key,
        talks: entry.value
          ..sort((a, b) {
            final byOrdinal = (a.ordinal ?? 1 << 30).compareTo(
              b.ordinal ?? 1 << 30,
            );
            return byOrdinal != 0 ? byOrdinal : a.date.compareTo(b.date);
          }),
      ),
  ]..sort((a, b) => b.latestDate.compareTo(a.latestDate));
  return HaListing(talks: talks, events: events);
}

/// Whether a talk is practice (something to do along with) rather than a
/// talk to listen to: its title, event or tags contain the whole word
/// "guided", "meditation" or "practice", case and diacritics aside.
///
/// A heuristic. The listing carries no type; the real one (talk, practice,
/// Q&A) is only on each talk's own page, which is not fetched, so a future
/// permitted build can read it there and drop this.
bool isHaPractice({
  required String title,
  String event = '',
  List<String> tags = const [],
}) {
  const words = {'guided', 'meditation', 'practice'};
  return haTerms([title, event, ...tags].join(' ')).any(words.contains);
}

/// `66:46` or `1:15:48` as milliseconds; 0 for anything else.
int parseHaDuration(String text) {
  final parts = text.trim().split(':');
  if (parts.length < 2 || parts.length > 3) return 0;
  final numbers = [for (final p in parts) int.tryParse(p.trim())];
  if (numbers.any((n) => n == null || n < 0)) return 0;
  final seconds = numbers.fold<int>(0, (sum, n) => sum * 60 + n!);
  return seconds * Duration.millisecondsPerSecond;
}

String _text(Object? value) => value is String
    ? value.trim()
    : value is num
    ? '$value'
    : '';

String _date(Object? value) {
  final text = _text(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(text)
      ? text.substring(0, 10)
      : '';
}

/// Comma-separated tags; a comma inside double quotes stays in its tag.
List<String> _split(String text) {
  if (text.isEmpty) return const [];
  final tags = <String>[];
  final current = StringBuffer();
  var quoted = false;
  void flush() {
    final tag = current.toString().trim();
    if (tag.isNotEmpty) tags.add(tag);
    current.clear();
  }

  for (final c in text.split('')) {
    if (c == '"') {
      quoted = !quoted;
    } else if (c == ',' && !quoted) {
      flush();
    } else {
      current.write(c);
    }
  }
  flush();
  return tags;
}
