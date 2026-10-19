import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';

/// What a pasted or shared link points at, decided from its text alone. No
/// network: the importer asks the network only for the cases that need it
/// ([ImportLinkKind.webAddress]).
enum ImportLinkKind {
  dharmaSeedRetreat,
  dharmaSeedTeacher,
  dharmaSeedTalk,

  /// A direct link to an audio file, by its extension.
  audioFile,

  /// A YouTube video or playlist, resolved by the native extractor.
  youtube,

  /// A podcast directory that has no readable feed (Spotify, and so on).
  unsupportedHost,

  /// Apple Podcasts: the feed is looked up from the show's ID.
  applePodcast,

  /// Any other web address. It may be a feed, an audio file behind a
  /// redirect, or a page that links to a feed; one request finds out.
  webAddress,

  /// A path on this device (`file://`, `content://` or absolute).
  localFile,

  /// Nothing recognisable.
  unrecognised,
}

class ImportLink {
  const ImportLink(this.kind, {this.raw = '', this.uri, this.id});

  final ImportLinkKind kind;

  /// The cleaned text the user gave.
  final String raw;

  /// The parsed address for web kinds.
  final Uri? uri;

  /// The Dharma Seed or Apple Podcasts number, where one applies.
  final int? id;

  @override
  String toString() => 'ImportLink($kind, $raw)';
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
  'wma',
  'mpga',
  'weba',
  'm4b',
};

final _urlPattern = RegExp(
  r'''(?:https?|file|content)://[^\s<>"']+''',
  caseSensitive: false,
);

/// The first link in [text], with trailing punctuation a chat or browser
/// adds (a full stop, a closing bracket) removed. Null when there is none.
String? firstLinkIn(String text) {
  final match = _urlPattern.firstMatch(text);
  if (match == null) return null;
  var link = match.group(0)!;
  while (link.isNotEmpty && '.,;:!?)]}'.contains(link[link.length - 1])) {
    // Keep a ")" that balances a "(" inside the address (Wikipedia style).
    if (link.endsWith(')') &&
        link.split('(').length >= link.split(')').length) {
      break;
    }
    link = link.substring(0, link.length - 1);
  }
  return link;
}

/// Whether [text] holds something worth offering to import, for the
/// clipboard check.
bool looksImportable(String text) {
  final link = firstLinkIn(text.trim());
  if (link == null) return false;
  final kind = classifyLink(link).kind;
  return kind != ImportLinkKind.unrecognised;
}

/// Classifies one link or path. Pass [firstLinkIn]'s result for shared text.
ImportLink classifyLink(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const ImportLink(ImportLinkKind.unrecognised);

  if (raw.startsWith('/') && !raw.startsWith('//')) {
    return ImportLink(ImportLinkKind.localFile, raw: raw);
  }

  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) {
    // "dharmaseed.org/talks/1/" typed without a scheme.
    if (RegExp(r'^[\w-]+(\.[\w-]+)+(/|$)').hasMatch(raw)) {
      return classifyLink('https://$raw');
    }
    return ImportLink(ImportLinkKind.unrecognised, raw: raw);
  }

  switch (uri.scheme.toLowerCase()) {
    case 'file':
    case 'content':
      return ImportLink(ImportLinkKind.localFile, raw: raw, uri: uri);
    case 'http':
    case 'https':
      break;
    default:
      return ImportLink(ImportLinkKind.unrecognised, raw: raw);
  }
  if (uri.host.isEmpty) {
    return ImportLink(ImportLinkKind.unrecognised, raw: raw);
  }

  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');

  if (host == 'dharmaseed.org') {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2) {
      final number = int.tryParse(segments[1]);
      if (number != null) {
        switch (segments[0]) {
          case 'retreats':
            return ImportLink(
              ImportLinkKind.dharmaSeedRetreat,
              raw: raw,
              uri: uri,
              id: number,
            );
          case 'teacher':
          case 'teachers':
            return ImportLink(
              ImportLinkKind.dharmaSeedTeacher,
              raw: raw,
              uri: uri,
              id: number,
            );
          case 'talks':
            return ImportLink(
              ImportLinkKind.dharmaSeedTalk,
              raw: raw,
              uri: uri,
              id: number,
            );
        }
      }
    }
    // A Dharma Seed audio file is still an audio file.
    if (_hasAudioExtension(uri)) {
      return ImportLink(ImportLinkKind.audioFile, raw: raw, uri: uri);
    }
    return ImportLink(ImportLinkKind.webAddress, raw: raw, uri: uri);
  }

  if (host == 'youtube.com' ||
      host == 'youtu.be' ||
      host == 'music.youtube.com' ||
      host == 'youtube-nocookie.com') {
    return ImportLink(ImportLinkKind.youtube, raw: raw, uri: uri);
  }

  if (host == 'open.spotify.com' ||
      host == 'spotify.link' ||
      host == 'spotify.com') {
    return ImportLink(ImportLinkKind.unsupportedHost, raw: raw, uri: uri);
  }

  if (host == 'podcasts.apple.com') {
    final id = RegExp(r'/id(\d+)').firstMatch(uri.path)?.group(1);
    if (id != null) {
      return ImportLink(
        ImportLinkKind.applePodcast,
        raw: raw,
        uri: uri,
        id: int.parse(id),
      );
    }
    return ImportLink(ImportLinkKind.unsupportedHost, raw: raw, uri: uri);
  }

  if (_hasAudioExtension(uri)) {
    return ImportLink(ImportLinkKind.audioFile, raw: raw, uri: uri);
  }
  return ImportLink(ImportLinkKind.webAddress, raw: raw, uri: uri);
}

bool _hasAudioExtension(Uri uri) {
  final path = uri.path.toLowerCase();
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < path.lastIndexOf('/')) return false;
  return _audioExtensions.contains(path.substring(dot + 1));
}

/// A tidy title from a file name or URL path:
/// `/files/2024-05_body-scan_20min.mp3` → `2024 05 body scan 20min`.
String titleFromFileName(String nameOrUrl) {
  var name = nameOrUrl;
  final uri = Uri.tryParse(nameOrUrl);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
    name = uri.pathSegments.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => uri.host,
    );
  } else if (name.contains('/')) {
    name = name.substring(name.lastIndexOf('/') + 1);
  }
  try {
    name = Uri.decodeComponent(name);
  } catch (_) {
    // Keep the raw name when it holds a stray percent sign.
  }
  final dot = name.lastIndexOf('.');
  if (dot > 0 &&
      _audioExtensions.contains(name.substring(dot + 1).toLowerCase())) {
    name = name.substring(0, dot);
  }
  name = name
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name.isEmpty ? 'Untitled' : name;
}

/// Hosts whose material is talks rather than guided practice.
const _talkHosts = {'dharmaseed.org', 'dhammatalks.org', 'audiodharma.org'};

/// Whether [host] is a known source of talks. Anything else defaults to
/// practice, since that is the app's default when nothing says otherwise.
bool isKnownTalkHost(String host) {
  final bare = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  return _talkHosts.any((h) => bare == h || bare.endsWith('.$h'));
}

/// The Dharma Seed IDs for a classified link, or null.
String? dharmaSeedIdFor(ImportLink link) => switch (link.kind) {
  ImportLinkKind.dharmaSeedRetreat => dsRetreatId(link.id!),
  ImportLinkKind.dharmaSeedTeacher => dsTeacherId(link.id!),
  ImportLinkKind.dharmaSeedTalk => dsTalkId(link.id!),
  _ => null,
};
