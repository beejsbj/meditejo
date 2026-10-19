import 'package:xml/xml.dart';

/// A podcast or Atom feed, read into the shapes the library stores.
class ParsedFeed {
  const ParsedFeed({
    required this.title,
    required this.episodes,
    this.description = '',
    this.author = '',
    this.imageUrl = '',
    this.siteUrl = '',
    this.copyright = '',
    this.licenseUrl = '',
    this.licenseName = '',
    this.isSerial = false,
    this.skippedItems = 0,
  });

  final String title;
  final String description;
  final String author;
  final String imageUrl;
  final String siteUrl;
  final String copyright;
  final String licenseUrl;
  final String licenseName;

  /// `itunes:type` is `serial`: a course meant to be heard in order.
  final bool isSerial;

  /// Episodes with audio, oldest first; [ParsedEpisode.ordinal] is the rank.
  final List<ParsedEpisode> episodes;

  /// Items without playable audio (text posts, video), left out.
  final int skippedItems;

  /// The sum of known durations; [durationComplete] says whether every
  /// episode had one.
  int get totalDurationMs =>
      episodes.fold(0, (sum, e) => sum + (e.durationMs ?? 0));
  bool get durationComplete =>
      episodes.isNotEmpty && episodes.every((e) => e.durationMs != null);
}

class ParsedEpisode {
  const ParsedEpisode({
    required this.guid,
    required this.title,
    required this.audioUrl,
    required this.ordinal,
    this.description = '',
    this.mimeType = '',
    this.lengthBytes,
    this.durationMs,
    this.publishedAt,
    this.imageUrl = '',
    this.pageUrl = '',
    this.author = '',
  });

  /// The feed's own ID for the episode, falling back to its audio address.
  final String guid;
  final String title;
  final String description;
  final String audioUrl;
  final String mimeType;
  final int? lengthBytes;
  final int? durationMs;
  final DateTime? publishedAt;
  final String imageUrl;
  final String pageUrl;
  final String author;

  /// Rank in oldest-first order.
  final int ordinal;
}

/// Thrown when the text is not an RSS or Atom feed.
class FeedFormatException implements Exception {
  const FeedFormatException(this.message);

  final String message;

  @override
  String toString() => 'FeedFormatException: $message';
}

/// Whether [body] looks like the start of a feed (RSS 2.0 or Atom), checked
/// cheaply without parsing everything.
bool looksLikeFeed(String body) {
  final head = body.length > 4096 ? body.substring(0, 4096) : body;
  return RegExp(
    r'<(rss|feed|rdf:RDF)[\s>]',
    caseSensitive: false,
  ).hasMatch(head);
}

/// Reads an RSS 2.0 or Atom feed. Relative addresses resolve against [base].
ParsedFeed parseFeed(String body, {Uri? base}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body.trimLeft());
  } on XmlException catch (e) {
    throw FeedFormatException('Not valid XML: ${e.message}');
  }
  final root = document.rootElement;
  return switch (root.name.local) {
    'rss' => _parseRss(root, base),
    'feed' => _parseAtom(root, base),
    _ => throw const FeedFormatException('Not an RSS or Atom feed'),
  };
}

// ------------------------------------------------------------------ helpers

bool _isItunes(XmlName name) =>
    name.prefix == 'itunes' || (name.namespaceUri?.contains('itunes') ?? false);

bool _isMedia(XmlName name) =>
    name.prefix == 'media' ||
    (name.namespaceUri?.contains('search.yahoo.com/mrss') ?? false);

/// The first child called [local]. With [itunes] true only `itunes:` tags
/// count; otherwise only unprefixed ones (so `itunes:title` is not `title`).
XmlElement? _child(XmlElement parent, String local, {bool itunes = false}) {
  for (final child in parent.childElements) {
    if (child.name.local != local) continue;
    if (itunes
        ? _isItunes(child.name)
        : (child.name.prefix == null || child.name.prefix!.isEmpty)) {
      return child;
    }
  }
  return null;
}

String _text(XmlElement? element) {
  if (element == null) return '';
  return element.innerText.replaceAll('\r', '').trim();
}

String _resolve(String? url, Uri? base) {
  final value = url?.trim() ?? '';
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null) return '';
  if (uri.hasScheme) return value;
  return base == null ? value : base.resolveUri(uri).toString();
}

/// Strips markup from a description, keeping paragraph breaks.
String plainText(String html) {
  if (!html.contains('<') && !html.contains('&')) return html.trim();
  var text = html
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n\n',
      )
      .replaceAll(RegExp(r'<[^>]+>'), '');
  const entities = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
    '&rsquo;': '’',
    '&lsquo;': '‘',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&ndash;': '–',
    '&mdash;': '—',
  };
  entities.forEach((entity, value) => text = text.replaceAll(entity, value));
  text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!) ?? 0;
    return code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : '';
  });
  return text
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// `itunes:duration`: seconds (`1830`), `mm:ss` or `hh:mm:ss`.
int? parseDurationMs(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length > 3) return null;
  var seconds = 0.0;
  for (final part in parts) {
    final number = double.tryParse(part.trim());
    if (number == null || number < 0) return null;
    seconds = seconds * 60 + number;
  }
  if (!seconds.isFinite) return null;
  final ms = (seconds * 1000).round();
  return ms > 0 ? ms : null;
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
const _zones = {
  'GMT': 0,
  'UT': 0,
  'UTC': 0,
  'Z': 0,
  'EST': -5,
  'EDT': -4,
  'CST': -6,
  'CDT': -5,
  'MST': -7,
  'MDT': -6,
  'PST': -8,
  'PDT': -7,
};

/// RFC 822 dates (`Tue, 10 Jun 2025 04:00:00 +0000`) as RSS uses them, or
/// ISO 8601 as Atom does. Null when unreadable.
DateTime? parseFeedDate(String? text) {
  final value = text?.trim() ?? '';
  if (value.isEmpty) return null;
  final iso = DateTime.tryParse(value);
  if (iso != null) return iso.toUtc();
  final match = RegExp(
    r'^(?:[A-Za-z]{3,9},?\s+)?(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{2,4})'
    r'(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?\s*([+-]\d{4}|[A-Za-z]{1,4})?',
  ).firstMatch(value);
  if (match == null) return null;
  final month = _months[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(match.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  final hour = int.tryParse(match.group(4) ?? '') ?? 0;
  final minute = int.tryParse(match.group(5) ?? '') ?? 0;
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  var offset = Duration.zero;
  final zone = match.group(7);
  if (zone != null) {
    if (RegExp(r'^[+-]\d{4}$').hasMatch(zone)) {
      final sign = zone.startsWith('-') ? -1 : 1;
      offset = Duration(
        hours: sign * int.parse(zone.substring(1, 3)),
        minutes: sign * int.parse(zone.substring(3, 5)),
      );
    } else {
      offset = Duration(hours: _zones[zone.toUpperCase()] ?? 0);
    }
  }
  return DateTime.utc(
    year,
    month,
    int.parse(match.group(1)!),
    hour,
    minute,
    second,
  ).subtract(offset);
}

const _audioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'ogg',
  'oga',
  'opus',
  'wav',
  'flac',
  'm4b',
  'wma',
  'weba',
};

bool _isAudio(String mime, String url) {
  final type = mime.toLowerCase();
  if (type.startsWith('audio/')) return true;
  if (type.startsWith('video/') ||
      type.startsWith('image/') ||
      type.startsWith('text/')) {
    return false;
  }
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  final dot = path.lastIndexOf('.');
  return dot >= 0 && _audioExtensions.contains(path.substring(dot + 1));
}

/// `https://creativecommons.org/licenses/by-nc-nd/4.0/` → `CC BY-NC-ND 4.0`.
String licenseNameFromUrl(String url) {
  final match = RegExp(
    r'creativecommons\.org/(licenses|publicdomain)/([a-z\-]+)(?:/([\d.]+))?',
    caseSensitive: false,
  ).firstMatch(url);
  if (match == null) return '';
  final kind = match.group(2)!.toLowerCase();
  if (match.group(1) == 'publicdomain' || kind == 'zero') return 'CC0';
  final version = match.group(3);
  return 'CC ${kind.toUpperCase()}${version == null ? '' : ' $version'}';
}

class _Draft {
  _Draft({
    required this.guid,
    required this.title,
    required this.audioUrl,
    required this.feedIndex,
    this.description = '',
    this.mimeType = '',
    this.lengthBytes,
    this.durationMs,
    this.publishedAt,
    this.imageUrl = '',
    this.pageUrl = '',
    this.author = '',
    this.episode,
    this.season,
  });

  final String guid;
  final String title;
  final String audioUrl;
  final int feedIndex;
  final String description;
  final String mimeType;
  final int? lengthBytes;
  final int? durationMs;
  final DateTime? publishedAt;
  final String imageUrl;
  final String pageUrl;
  final String author;
  final int? episode;
  final int? season;
}

/// Orders drafts oldest first and numbers them.
///
/// A serial feed with episode numbers is ordered by them (the publisher's own
/// order of play); otherwise by date; otherwise the feed is read backwards,
/// since feeds list their newest entry first.
List<ParsedEpisode> _order(List<_Draft> drafts, {required bool serial}) {
  final ordered = List<_Draft>.of(drafts);
  int byFeedBackwards(_Draft a, _Draft b) => b.feedIndex.compareTo(a.feedIndex);

  if (serial && ordered.isNotEmpty && ordered.every((d) => d.episode != null)) {
    ordered.sort((a, b) {
      final season = (a.season ?? 0).compareTo(b.season ?? 0);
      if (season != 0) return season;
      final episode = a.episode!.compareTo(b.episode!);
      return episode != 0 ? episode : byFeedBackwards(a, b);
    });
  } else if (ordered.isNotEmpty &&
      ordered.every((d) => d.publishedAt != null)) {
    ordered.sort((a, b) {
      final date = a.publishedAt!.compareTo(b.publishedAt!);
      return date != 0 ? date : byFeedBackwards(a, b);
    });
  } else {
    ordered.sort(byFeedBackwards);
  }

  return [
    for (var i = 0; i < ordered.length; i++)
      ParsedEpisode(
        guid: ordered[i].guid,
        title: ordered[i].title,
        description: ordered[i].description,
        audioUrl: ordered[i].audioUrl,
        mimeType: ordered[i].mimeType,
        lengthBytes: ordered[i].lengthBytes,
        durationMs: ordered[i].durationMs,
        publishedAt: ordered[i].publishedAt,
        imageUrl: ordered[i].imageUrl,
        pageUrl: ordered[i].pageUrl,
        author: ordered[i].author,
        ordinal: i,
      ),
  ];
}

// ---------------------------------------------------------------------- RSS

ParsedFeed _parseRss(XmlElement rss, Uri? base) {
  final channel = _child(rss, 'channel');
  if (channel == null) {
    throw const FeedFormatException('RSS feed has no channel');
  }

  final title = plainText(_text(_child(channel, 'title')));
  var image = _text(_child(_child(channel, 'image') ?? channel, 'url'));
  final itunesImage = _child(
    channel,
    'image',
    itunes: true,
  )?.getAttribute('href');
  if (itunesImage != null && itunesImage.trim().isNotEmpty) image = itunesImage;

  final author = _text(_child(channel, 'author', itunes: true)).isNotEmpty
      ? _text(_child(channel, 'author', itunes: true))
      : _text(_child(channel, 'managingEditor'));

  var licenseUrl = '';
  for (final child in channel.childElements) {
    if (child.name.local == 'license') licenseUrl = _text(child);
  }

  final serial =
      _text(_child(channel, 'type', itunes: true)).toLowerCase() == 'serial';

  final drafts = <_Draft>[];
  var skipped = 0;
  var index = 0;
  for (final item in channel.findElements('item')) {
    final draft = _rssItem(item, index++, base, fallbackAuthor: author);
    if (draft == null) {
      skipped++;
    } else {
      drafts.add(draft);
    }
  }

  return ParsedFeed(
    title: title.isEmpty ? 'Untitled feed' : title,
    description: plainText(
      _text(_child(channel, 'description')).isNotEmpty
          ? _text(_child(channel, 'description'))
          : _text(_child(channel, 'summary', itunes: true)),
    ),
    author: author,
    imageUrl: _resolve(image, base),
    siteUrl: _resolve(_text(_child(channel, 'link')), base),
    copyright: _text(_child(channel, 'copyright')),
    licenseUrl: licenseUrl,
    licenseName: licenseNameFromUrl(licenseUrl),
    isSerial: serial,
    episodes: _order(drafts, serial: serial),
    skippedItems: skipped,
  );
}

_Draft? _rssItem(
  XmlElement item,
  int index,
  Uri? base, {
  required String fallbackAuthor,
}) {
  String url = '';
  String mime = '';
  int? length;
  for (final enclosure in item.findElements('enclosure')) {
    final candidate = _resolve(enclosure.getAttribute('url'), base);
    final type = enclosure.getAttribute('type') ?? '';
    if (candidate.isNotEmpty && _isAudio(type, candidate)) {
      url = candidate;
      mime = type;
      length = int.tryParse(enclosure.getAttribute('length') ?? '');
      break;
    }
  }
  if (url.isEmpty) {
    // media:content is how some feeds carry their audio.
    for (final child in item.childElements) {
      if (child.name.local != 'content' || !_isMedia(child.name)) continue;
      final candidate = _resolve(child.getAttribute('url'), base);
      var type = child.getAttribute('type') ?? '';
      // medium="audio" says it is audio when there is no type or extension.
      final medium = (child.getAttribute('medium') ?? '').toLowerCase();
      if (type.isEmpty && medium == 'audio') type = 'audio/mpeg';
      if (candidate.isNotEmpty && _isAudio(type, candidate)) {
        url = candidate;
        mime = child.getAttribute('type') ?? '';
        break;
      }
    }
  }
  if (url.isEmpty) return null;

  final title = plainText(
    _text(_child(item, 'title')).isNotEmpty
        ? _text(_child(item, 'title'))
        : _text(_child(item, 'title', itunes: true)),
  );
  var description = '';
  // content:encoded carries the full show notes; prefer it.
  XmlElement? encoded;
  for (final child in item.childElements) {
    if (child.name.local == 'encoded') encoded = child;
  }
  for (final candidate in [
    encoded,
    _child(item, 'description'),
    _child(item, 'summary', itunes: true),
  ]) {
    final text = _text(candidate);
    if (text.isNotEmpty) {
      description = plainText(text);
      break;
    }
  }

  final guid = _text(_child(item, 'guid'));
  final itunesAuthor = _text(_child(item, 'author', itunes: true));
  return _Draft(
    guid: guid.isEmpty ? url : guid,
    title: title.isEmpty ? 'Episode ${index + 1}' : title,
    audioUrl: url,
    feedIndex: index,
    description: description,
    mimeType: mime,
    lengthBytes: length,
    durationMs: parseDurationMs(_text(_child(item, 'duration', itunes: true))),
    publishedAt: parseFeedDate(_text(_child(item, 'pubDate'))),
    imageUrl: _resolve(
      _child(item, 'image', itunes: true)?.getAttribute('href'),
      base,
    ),
    pageUrl: _resolve(_text(_child(item, 'link')), base),
    author: itunesAuthor.isNotEmpty ? itunesAuthor : fallbackAuthor,
    episode: int.tryParse(_text(_child(item, 'episode', itunes: true))),
    season: int.tryParse(_text(_child(item, 'season', itunes: true))),
  );
}

// --------------------------------------------------------------------- Atom

ParsedFeed _parseAtom(XmlElement feed, Uri? base) {
  String siteUrl = '';
  String licenseUrl = '';
  for (final link in feed.findElements('link')) {
    final rel = link.getAttribute('rel') ?? 'alternate';
    final href = _resolve(link.getAttribute('href'), base);
    if (rel == 'alternate' && siteUrl.isEmpty) siteUrl = href;
    if (rel == 'license') licenseUrl = href;
  }
  final author = _text(_child(_child(feed, 'author') ?? feed, 'name'));

  final drafts = <_Draft>[];
  var skipped = 0;
  var index = 0;
  for (final entry in feed.findElements('entry')) {
    final draft = _atomEntry(entry, index++, base, fallbackAuthor: author);
    if (draft == null) {
      skipped++;
    } else {
      drafts.add(draft);
    }
  }

  final title = plainText(_text(_child(feed, 'title')));
  final logo = _text(_child(feed, 'logo')).isNotEmpty
      ? _text(_child(feed, 'logo'))
      : _text(_child(feed, 'icon'));
  return ParsedFeed(
    title: title.isEmpty ? 'Untitled feed' : title,
    description: plainText(_text(_child(feed, 'subtitle'))),
    author: author,
    imageUrl: _resolve(logo, base),
    siteUrl: siteUrl,
    copyright: _text(_child(feed, 'rights')),
    licenseUrl: licenseUrl,
    licenseName: licenseNameFromUrl(licenseUrl),
    episodes: _order(drafts, serial: false),
    skippedItems: skipped,
  );
}

_Draft? _atomEntry(
  XmlElement entry,
  int index,
  Uri? base, {
  required String fallbackAuthor,
}) {
  String url = '';
  String mime = '';
  int? length;
  String page = '';
  for (final link in entry.findElements('link')) {
    final rel = link.getAttribute('rel') ?? 'alternate';
    final href = _resolve(link.getAttribute('href'), base);
    if (rel == 'enclosure' && url.isEmpty) {
      final type = link.getAttribute('type') ?? '';
      if (href.isNotEmpty && _isAudio(type, href)) {
        url = href;
        mime = type;
        length = int.tryParse(link.getAttribute('length') ?? '');
      }
    } else if (rel == 'alternate' && page.isEmpty) {
      page = href;
    }
  }
  if (url.isEmpty) return null;

  final title = plainText(_text(_child(entry, 'title')));
  final body = _text(_child(entry, 'content')).isNotEmpty
      ? _text(_child(entry, 'content'))
      : _text(_child(entry, 'summary'));
  final id = _text(_child(entry, 'id'));
  final entryAuthor = _text(_child(_child(entry, 'author') ?? entry, 'name'));
  return _Draft(
    guid: id.isEmpty ? url : id,
    title: title.isEmpty ? 'Episode ${index + 1}' : title,
    audioUrl: url,
    feedIndex: index,
    description: plainText(body),
    mimeType: mime,
    lengthBytes: length,
    durationMs: parseDurationMs(_text(_child(entry, 'duration', itunes: true))),
    publishedAt: parseFeedDate(
      _text(_child(entry, 'published')).isNotEmpty
          ? _text(_child(entry, 'published'))
          : _text(_child(entry, 'updated')),
    ),
    pageUrl: page,
    author: entryAuthor.isNotEmpty ? entryAuthor : fallbackAuthor,
  );
}
