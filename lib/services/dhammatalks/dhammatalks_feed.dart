import 'dart:convert';

import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The talks in one of dhammatalks.org's RSS feeds (50 newest items).
///
/// The feed's own `pubDate` is when the file was published, not when the talk
/// was given, so the date comes from the talk's key (`261026-…`). An item
/// with no page link or an unusable key is skipped, since it cannot be given
/// a stable ID.
List<DtTalk> dtTalksFromFeed(String xml, DtChannel channel) {
  final feed = parseFeed(xml);
  final talks = <DtTalk>[];
  for (final episode in feed.episodes) {
    final page = Uri.tryParse(episode.pageUrl);
    final file = page == null || page.pathSegments.isEmpty
        ? ''
        : page.pathSegments.last;
    if (!file.endsWith('.html') || episode.audioUrl.isEmpty) continue;
    final key = file.substring(0, file.length - '.html'.length);
    final audio = episode.audioUrl.startsWith(dhammatalksSite)
        ? episode.audioUrl.substring(dhammatalksSite.length)
        : episode.audioUrl;
    talks.add(
      DtTalk(
        id: dtTalkId(channel.code, key),
        code: channel.code,
        key: key,
        title: episode.title,
        date: dtDateOfKey(key),
        audioPath: audio,
        durationMs: episode.durationMs ?? 0,
      ),
    );
  }
  return talks;
}

/// What the app remembers of the feeds between launches: the talks they
/// added to the snapshot, and when they were last read.
class DtFeedState {
  const DtFeedState({required this.fetchedAt, this.talks = const []});

  final DateTime fetchedAt;
  final List<DtTalk> talks;

  String encode() => jsonEncode({
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
    'talks': [
      for (final t in talks)
        [t.code, t.key, t.title, t.date, t.audioPath, t.pagePath, t.durationMs],
    ],
  });

  /// Null for anything that is not what [encode] wrote.
  static DtFeedState? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text) as Map<String, Object?>;
      return DtFeedState(
        fetchedAt: DateTime.parse(json['fetchedAt']! as String),
        talks: [
          for (final row in json['talks']! as List<Object?>)
            _talk((row! as List<Object?>).cast<Object?>()),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static DtTalk _talk(List<Object?> row) => DtTalk(
    id: dtTalkId(row[0]! as String, row[1]! as String),
    code: row[0]! as String,
    key: row[1]! as String,
    title: row[2]! as String,
    date: row[3]! as String,
    audioPath: row[4]! as String,
    pagePath: row[5]! as String,
    durationMs: (row[6]! as num).toInt(),
  );
}

/// Where [DtFeedState] is kept.
abstract interface class DtFeedCache {
  Future<DtFeedState?> read();
  Future<void> write(DtFeedState state);
}

class MemoryDtFeedCache implements DtFeedCache {
  MemoryDtFeedCache([this.state]);

  DtFeedState? state;

  @override
  Future<DtFeedState?> read() async => state;

  @override
  Future<void> write(DtFeedState value) async => state = value;
}

/// Keeps [DtFeedState] in the app's shared preferences.
class SharedPreferencesDtFeedCache implements DtFeedCache {
  static const _key = 'dhammatalks_feed_v1';

  @override
  Future<DtFeedState?> read() async => DtFeedState.decode(
    (await SharedPreferences.getInstance()).getString(_key),
  );

  @override
  Future<void> write(DtFeedState state) async =>
      (await SharedPreferences.getInstance()).setString(_key, state.encode());
}
