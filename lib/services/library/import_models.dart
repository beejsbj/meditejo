import 'package:flutter/foundation.dart';
import 'package:medito/src/youtube_api.g.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:medito/services/library/library_models.dart';

/// Where a preview came from. [catalogue] is a built-in catalogue (Dharma
/// Seed, dhammatalks.org): the item is already known to the app.
enum ImportOrigin { catalogue, feed, audioUrl, localFiles, youtube }

/// Why an import did not work. The screen turns each into a plain sentence;
/// nothing here is shown to the user as it stands.
enum ImportFailureReason {
  empty,
  unrecognised,
  youtubeUnavailable,
  youtubeAgeRestricted,
  youtubePrivate,
  youtubeRateLimited,
  unsupportedHost,
  offline,
  notFound,
  unreachable,
  noFeedOrAudio,
  noEpisodes,
  brokenFeed,
  dharmaSeedMissing,
  fileMissing,
  noAudioFiles,

  /// A picked folder with nothing in it.
  folderEmpty,

  /// A picked folder with more audio than a course should hold.
  folderTooLarge,

  /// Not enough free space to copy a picked folder.
  folderNoSpace,

  /// The folder could not be opened or none of its files could be read.
  folderUnreadable,

  /// No folder picker on this device.
  folderUnavailable,
}

class ImportFailure implements Exception {
  const ImportFailure(this.reason, [this.detail]);

  final ImportFailureReason reason;

  /// For logs only.
  final String? detail;

  @override
  String toString() =>
      'ImportFailure($reason${detail == null ? '' : ': $detail'})';
}

/// A file the user chose or shared, before it is copied into the app.
@immutable
class PickedFile {
  const PickedFile({
    required this.path,
    this.name,
    this.sizeBytes,
    this.mimeType,
  });

  final String path;

  /// The display name, when the picker gave one; otherwise the file name.
  final String? name;
  final int? sizeBytes;
  final String? mimeType;
}

/// A folder the user chose. On Android its audio has already been copied
/// into the app ([files]); elsewhere only its [path] is known and the
/// importer lists it.
@immutable
class PickedFolder {
  const PickedFolder.path(String this.path)
    : name = '',
      files = const [],
      unreadable = 0;

  const PickedFolder.copied({
    required this.name,
    required this.files,
    this.unreadable = 0,
  }) : path = null;

  final String? path;

  /// The folder's own name, the suggested course title.
  final String name;
  final List<PickedFile> files;

  /// Files and folders that could not be read and were left out.
  final int unreadable;
}

/// One episode of a list that Single can pick from.
@immutable
class ImportEpisode {
  const ImportEpisode({
    required this.id,
    required this.title,
    this.durationMs,
    this.publishedAt,
    this.subtitle = '',
    this.artworkUrl = '',
  });

  /// The feed's own episode ID, or the YouTube video ID.
  final String id;
  final String title;
  final int? durationMs;
  final DateTime? publishedAt;

  /// The uploader or author, when it differs from the list's.
  final String subtitle;
  final String artworkUrl;
}

@immutable
class PreviewItem {
  const PreviewItem({required this.title, this.durationMs});

  final String title;
  final int? durationMs;
}

/// What the user sees before adding: enough to recognise the thing and trust
/// it, and everything [ImportService.add] needs to store it.
class ImportPreview {
  const ImportPreview({
    required this.origin,
    required this.entryId,
    required this.kind,
    required this.allowedKinds,
    required this.group,
    required this.title,
    required this.sourceLabel,
    this.subtitle = '',
    this.description = '',
    this.artworkUrl = '',
    this.itemCount = 1,
    this.durationMs = 0,
    this.durationComplete = true,
    this.firstItems = const [],
    this.attribution,
    this.alreadyInLibrary = false,
    this.skippedItems = 0,
    this.youtubeVideo,
    this.youtubePlaylist,
    this.youtubePlaylistId,
    this.feed,
    this.feedUrl,
    this.etag,
    this.lastModified,
    this.audioUrl,
    this.mimeType,
    this.files = const [],
    this.fileDurationsMs = const [],
    this.unreadableItems = 0,
    this.episodes = const [],
    this.defaultEpisodeId,
  });

  final ImportOrigin origin;

  /// The library ID this will have. Empty for local files, whose IDs are
  /// made when they are copied.
  final String entryId;

  /// What it will be added as unless the user changes it.
  final LibraryKind kind;

  /// The kinds the user may choose between; one means no choice.
  final Set<LibraryKind> allowedKinds;

  /// Detected Practice/Talks, Practice when nothing says otherwise.
  final LibraryGroup group;

  final String title;
  final String subtitle;
  final String description;
  final String artworkUrl;

  /// "Dharma Seed", a website's name, or "This device".
  final String sourceLabel;

  final int itemCount;
  final int durationMs;

  /// False when some sessions have no known length, so [durationMs] is a
  /// lower bound.
  final bool durationComplete;
  final List<PreviewItem> firstItems;
  final SourceAttribution? attribution;
  final bool alreadyInLibrary;

  /// Feed items without audio that were left out.
  final int skippedItems;

  // What storing needs.
  final YoutubeVideo? youtubeVideo;
  final YoutubePlaylist? youtubePlaylist;
  final String? youtubePlaylistId;
  final ParsedFeed? feed;
  final String? feedUrl;
  final String? etag;
  final String? lastModified;
  final String? audioUrl;
  final String? mimeType;
  final List<PickedFile> files;
  final List<int?> fileDurationsMs;

  /// Items a folder import could not read and left out.
  final int unreadableItems;

  /// What Single picks from, newest first for a feed, in list order for a
  /// playlist. Empty when there is nothing to pick.
  final List<ImportEpisode> episodes;

  /// The episode Single starts on: the feed's latest, or the video in a
  /// watch link.
  final String? defaultEpisodeId;

  bool get hasKindChoice => allowedKinds.length > 1;

  /// Whether Single has more than one episode to pick from.
  bool get hasEpisodeChoice => episodes.length > 1;

  ImportEpisode? episode(String? id) {
    final wanted = id ?? defaultEpisodeId;
    for (final e in episodes) {
      if (e.id == wanted) return e;
    }
    return null;
  }
}

/// What the user decided in the preview.
@immutable
class ImportChoice {
  const ImportChoice({
    required this.kind,
    required this.group,
    this.title,
    this.episodeOrder = 'oldest',
    this.episodeId,
  });

  final LibraryKind kind;
  final LibraryGroup group;

  /// A new title for the library entry; null keeps the one it came with.
  final String? title;

  /// `oldest` (the default) or `newest`, for feeds.
  final String episodeOrder;

  /// For a Single from a list: the episode picked; null takes the preview's
  /// default.
  final String? episodeId;
}

/// Where an import ended up.
@immutable
class ImportResult {
  const ImportResult({
    required this.entryId,
    required this.kind,
    this.alreadyPresent = false,
    this.addedCount = 1,
  });

  /// The first entry added (or found), for "Open".
  final String entryId;
  final LibraryKind kind;

  /// It was in the library already; nothing changed.
  final bool alreadyPresent;

  /// How many entries were added (several files added as singles).
  final int addedCount;
}
