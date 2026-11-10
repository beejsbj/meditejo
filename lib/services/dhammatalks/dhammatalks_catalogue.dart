import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';

/// How far back the RSS feeds (50 items each) reach: past this many days a
/// snapshot leaves a gap they cannot bridge. A test enforces it on `develop`;
/// `release.sh` is stricter (14 days), since users open a release for weeks.
/// Refresh with `python3 -I tools/meditejo/dhammatalks.py build`.
const dtSnapshotMaxAgeDays = 45;

/// Whether a snapshot made at [asOf] has aged past what the feeds can cover.
bool dtSnapshotIsStale(
  DateTime asOf,
  DateTime now, {
  int maxAgeDays = dtSnapshotMaxAgeDays,
}) => now.difference(asOf).inDays > maxAgeDays;

/// One talk: a row of the archive, a feed item, or a file a collection lists.
@immutable
class DtTalk {
  const DtTalk({
    required this.id,
    required this.code,
    required this.key,
    required this.title,
    required this.date,
    required this.audioPath,
    this.pagePath = '',
    this.durationMs = 0,
    this.practice = false,
  });

  /// The app ID, `dt-talk-e-260131-a-slug`.
  final String id;

  /// `e`, `m` or `c` ([dtCollectionCode]).
  final String code;

  /// The site's own entry id, or a collection item's slug.
  final String key;
  final String title;

  /// `YYYY-MM-DD`, or `YYYY-MM` or `YYYY` when the archive is less exact,
  /// or empty.
  final String date;

  /// Site-relative (`/Archive/y2025/…mp3`), or a full address.
  final String audioPath;

  /// Site-relative page, empty when the usual one applies or none exists.
  final String pagePath;

  /// Zero when unknown (the archive pages carry no length).
  final int durationMs;

  /// Listed by a practice collection (the guided meditations).
  final bool practice;

  DtChannel? get channel => DtChannel.fromCode(code);

  String get audioUrl => dtAudioUrl(audioPath);

  /// The talk's own page; empty when it has none.
  String get pageUrl {
    if (pagePath.isNotEmpty) return dtAudioUrl(pagePath);
    final channel = this.channel;
    return channel == null ? '' : dtTalkPageUrl(channel, key);
  }

  /// The year it was given, or null.
  int? get year => date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;

  DtTalk withDuration(int ms) => DtTalk(
    id: id,
    code: code,
    key: key,
    title: title,
    date: date,
    audioPath: audioPath,
    pagePath: pagePath,
    durationMs: ms,
    practice: practice,
  );
}

/// A curated collection (the guided meditations, Basics).
@immutable
class DtCourse {
  const DtCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    required this.pagePath,
    required this.anchor,
    required this.items,
  });

  /// The collection's own id (`basics`); the app ID is `dt-course-<id>`.
  final String id;
  final String title;
  final String description;
  final ContentGroup group;
  final String pagePath;
  final String anchor;
  final List<DtTalk> items;

  String get appId => dtCourseId(id);

  String get pageUrl =>
      '${dtAudioUrl(pagePath)}${anchor.isEmpty ? '' : '#$anchor'}';

  int get durationMs => items.fold(0, (sum, t) => sum + t.durationMs);
}

/// Everything the app knows of dhammatalks.org: the bundled snapshot, plus
/// what the RSS feeds added since.
class DtCatalogue {
  DtCatalogue._({
    required this.asOf,
    required this.talks,
    required this.courses,
    required this.feedAdded,
  }) {
    for (final talk in talks) {
      _byId[talk.id] = talk;
      _byAudio[_audioKey(talk.audioPath)] = talk;
    }
    for (final course in courses) {
      for (final item in course.items) {
        _byId[item.id] ??= item;
        _byAudio[_audioKey(item.audioPath)] ??= item;
      }
    }
  }

  /// When the snapshot was read from the site.
  final DateTime asOf;

  /// Archive and feed talks, newest first.
  final List<DtTalk> talks;
  final List<DtCourse> courses;

  /// How many of [talks] came from the feeds, beyond the snapshot.
  final int feedAdded;

  final Map<String, DtTalk> _byId = {};
  final Map<String, DtTalk> _byAudio = {};

  int get talkCount => talks.length;

  DtTalk? talk(String id) => _byId[id];

  DtCourse? course(String id) {
    for (final course in courses) {
      if (course.id == id) return course;
    }
    return null;
  }

  /// The talk whose file is at [audio] (a path or address), if known.
  DtTalk? talkForAudio(String audio) => _byAudio[_audioKey(audio)];

  /// The collection that lists [talkId], when exactly the collection's own
  /// file (a talk the archive also holds belongs to several places).
  DtCourse? courseOfCollectionTalk(String talkId) {
    final ref = parseDtTalkId(talkId);
    if (ref == null || ref.code != dtCollectionCode) return null;
    for (final course in courses) {
      if (course.items.any((t) => t.id == talkId)) return course;
    }
    return null;
  }

  /// Years with talks in [channel], newest first.
  List<int> years(DtChannel channel) {
    final years = <int>{
      for (final talk in talks)
        if (talk.code == channel.code) ?talk.year,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<DtTalk> yearTalks(DtChannel channel, int year) => [
    for (final talk in talks)
      if (talk.code == channel.code && talk.year == year) talk,
  ];

  /// Talks whose title holds every word of [query] (each as a word prefix),
  /// newest first within the exact-phrase matches first.
  List<DtTalk> search(String query, {int limit = 40}) {
    final terms = _terms(query);
    if (terms.isEmpty) return const [];
    final phrase = terms.join(' ');
    final exact = <DtTalk>[];
    final rest = <DtTalk>[];
    for (final (talk, words) in _index) {
      if (!terms.every((t) => words.any((w) => w.startsWith(t)))) continue;
      (words.join(' ').contains(phrase) ? exact : rest).add(talk);
    }
    return [...exact, ...rest].take(limit).toList();
  }

  /// Each talk with the words of its title, folded once.
  late final List<(DtTalk, List<String>)> _index = [
    for (final talk in [...talks, ..._collectionOnly])
      (talk, _terms(talk.title)),
  ];

  late final List<DtTalk> _collectionOnly = [
    for (final course in courses)
      for (final item in course.items)
        if (item.code == dtCollectionCode) item,
  ];

  /// The same catalogue with [fresh] feed talks merged in. A feed talk the
  /// snapshot already holds only lends it its length.
  DtCatalogue withFeed(List<DtTalk> fresh) {
    final known = {for (final t in talks) t.id: t};
    var added = 0;
    final merged = [...talks];
    for (final talk in fresh) {
      final held = known[talk.id];
      if (held == null) {
        merged.add(talk);
        known[talk.id] = talk;
        added++;
      } else if (held.durationMs == 0 && talk.durationMs > 0) {
        merged[merged.indexOf(held)] = held.withDuration(talk.durationMs);
      }
    }
    merged.sort(_newestFirst);
    return DtCatalogue._(
      asOf: asOf,
      talks: merged,
      courses: courses,
      feedAdded: feedAdded + added,
    );
  }

  /// Reads the snapshot JSON (`tools/meditejo/dhammatalks.py` documents the
  /// format).
  factory DtCatalogue.fromJson(Map<String, Object?> json) {
    final talks = <DtTalk>[
      for (final row in json['talks']! as List<Object?>)
        _talkFromRow((row! as List<Object?>).cast<Object?>()),
    ]..sort(_newestFirst);
    final byAudio = {for (final t in talks) _audioKey(t.audioPath): t};

    final courses = <DtCourse>[];
    for (final raw in json['courses']! as List<Object?>) {
      final c = (raw! as Map).cast<String, Object?>();
      final id = c['id']! as String;
      final practice = c['group'] == 'practice';
      courses.add(
        DtCourse(
          id: id,
          title: c['title']! as String,
          description: (c['description'] as String?) ?? '',
          group: practice ? ContentGroup.practice : ContentGroup.talks,
          pagePath: c['page']! as String,
          anchor: (c['anchor'] as String?) ?? '',
          items: [
            for (final item in c['items']! as List<Object?>)
              _courseItem(
                (item! as List<Object?>).cast<Object?>(),
                practice: practice,
                archive: byAudio,
                pagePath: _coursePage(c),
              ),
          ],
        ),
      );
    }
    return DtCatalogue._(
      asOf: DateTime.parse(json['asOf']! as String),
      talks: talks,
      courses: courses,
      feedAdded: 0,
    );
  }

  /// Reads the gzipped asset bytes. Heavy: run it in an isolate.
  static Map<String, Object?> decode(Uint8List gz) =>
      (jsonDecode(utf8.decode(gzip.decode(gz))) as Map).cast<String, Object?>();

  static DtTalk _talkFromRow(List<Object?> row) {
    final code = row[0]! as String;
    final key = row[1]! as String;
    return DtTalk(
      id: dtTalkId(code, key),
      code: code,
      key: key,
      title: row[2]! as String,
      date: row[3]! as String,
      audioPath: row[4]! as String,
      pagePath: row.length > 5 ? (row[5] as String?) ?? '' : '',
    );
  }

  /// A collection's file. When the archive holds the same file, the archive's
  /// talk stands in, so a talk has one ID wherever it is listed.
  static DtTalk _courseItem(
    List<Object?> row, {
    required bool practice,
    required Map<String, DtTalk> archive,
    required String pagePath,
  }) {
    final audio = row[2]! as String;
    final held = archive[_audioKey(audio)];
    if (held != null) return held;
    final key = row[0]! as String;
    return DtTalk(
      id: dtTalkId(dtCollectionCode, key),
      code: dtCollectionCode,
      key: key,
      title: row[1]! as String,
      date: '',
      audioPath: audio,
      pagePath: pagePath,
      durationMs: ((row[3] as num?) ?? 0).toInt() * 1000,
      practice: practice,
    );
  }

  static String _coursePage(Map<String, Object?> course) {
    final anchor = (course['anchor'] as String?) ?? '';
    return '${course['page']}${anchor.isEmpty ? '' : '#$anchor'}';
  }

  static int _newestFirst(DtTalk a, DtTalk b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.key.compareTo(a.key);
  }

  static String _audioKey(String audio) {
    var path = audio;
    if (path.startsWith(dhammatalksSite)) {
      path = path.substring(dhammatalksSite.length);
    }
    try {
      path = Uri.decodeFull(path);
    } catch (_) {
      // Keep the raw path when it holds a stray percent sign.
    }
    return path.toLowerCase();
  }

  /// Lower-case words, apostrophes dropped (`Nothing’s` → `nothings`), other
  /// punctuation and diacritics folded, so "samadhi" finds "Samādhi".
  static List<String> _terms(String text) {
    final folded = text
        .toLowerCase()
        .replaceAll(RegExp(r"['’‘`]"), '')
        .split('')
        .map((c) => _fold[c] ?? c)
        .join();
    return folded
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static const _fold = {
    'ā': 'a',
    'ī': 'i',
    'ū': 'u',
    'ṅ': 'n',
    'ñ': 'n',
    'ṇ': 'n',
    'ṭ': 't',
    'ḍ': 'd',
    'ḷ': 'l',
    'ṃ': 'm',
    'ṁ': 'm',
    'ś': 's',
    'ṣ': 's',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ü': 'u',
    'ö': 'o',
    'ä': 'a',
    'á': 'a',
    'à': 'a',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ç': 'c',
  };

  /// Words of [text] as search sees them; exposed for the source's course and
  /// teacher matching.
  static List<String> termsOf(String text) => _terms(text);
}
