import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/lib_ids.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/library/link_classifier.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';
import 'package:path/path.dart' as p;

/// Reads the length of an audio file or address, or null when it cannot be
/// found out. Kept behind a function so tests need no audio engine.
typedef DurationProbe = Future<int?> Function(String pathOrUrl);

/// Turns a link, a path or a set of files into a [ImportPreview], and stores
/// what the user chooses to keep.
///
/// A link costs one network request (two when a web page has to be searched
/// for its feed, or an Apple Podcasts link looked up). Dharma Seed links cost
/// what opening the course or talk already does. Nothing is stored until
/// [add].
class ImportService {
  ImportService({
    required this.http,
    required this.lib,
    required this.library,
    required this.storageDirectory,
    this.dharmaSeed,
    this.durationProbe,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ImportHttp http;
  final LibSource lib;
  final LibraryStore library;
  final DharmaSeedSource? dharmaSeed;

  /// Where imported files are kept, created on demand.
  final Future<Directory> Function() storageDirectory;
  final DurationProbe? durationProbe;
  final DateTime Function() _clock;

  static const _previewItems = 5;

  // ---------------------------------------------------------------- resolve

  /// Resolves pasted or shared text: a link (anywhere in the text) or a path.
  Future<ImportPreview> resolve(String input) async {
    final text = input.trim();
    if (text.isEmpty) throw const ImportFailure(ImportFailureReason.empty);
    final link = classifyLink(firstLinkIn(text) ?? text);
    switch (link.kind) {
      case ImportLinkKind.dharmaSeedRetreat:
      case ImportLinkKind.dharmaSeedTalk:
      case ImportLinkKind.dharmaSeedTeacher:
        return _resolveDharmaSeed(link);
      case ImportLinkKind.audioFile:
        return _resolveAudioUrl(link.uri!);
      case ImportLinkKind.webAddress:
        return _resolveWebAddress(link.uri!);
      case ImportLinkKind.applePodcast:
        return _resolveApplePodcast(link);
      case ImportLinkKind.localFile:
        final path = link.uri != null && link.uri!.scheme == 'file'
            ? link.uri!.toFilePath()
            : link.raw;
        if (await Directory(path).exists()) return resolveDirectory(path);
        return resolveFiles([PickedFile(path: path)]);
      case ImportLinkKind.youtube:
        throw ImportFailure(ImportFailureReason.youtube, link.raw);
      case ImportLinkKind.unsupportedHost:
        throw ImportFailure(ImportFailureReason.unsupportedHost, link.raw);
      case ImportLinkKind.unrecognised:
        throw ImportFailure(ImportFailureReason.unrecognised, link.raw);
    }
  }

  // ------------------------------------------------------------ Dharma Seed

  Future<ImportPreview> _resolveDharmaSeed(ImportLink link) async {
    final source = dharmaSeed;
    if (source == null) {
      throw ImportFailure(ImportFailureReason.unrecognised, link.raw);
    }
    final id = dharmaSeedIdFor(link)!;
    try {
      final draft = await source.libraryDraft(id);
      if (draft == null) throw const ImportFailure(ImportFailureReason.dharmaSeedMissing);
      final inLibrary = await library.contains(id);
      switch (link.kind) {
        case ImportLinkKind.dharmaSeedRetreat:
          final pack = await source.pack(id);
          return ImportPreview(
            origin: ImportOrigin.dharmaSeed,
            entryId: id,
            kind: LibraryKind.course,
            allowedKinds: const {LibraryKind.course},
            group: draft.group,
            title: draft.title,
            subtitle: draft.subtitle,
            description: pack.description ?? '',
            artworkUrl: draft.coverUrl,
            sourceLabel: 'Dharma Seed',
            itemCount: draft.itemCount,
            durationMs: draft.durationMs,
            durationComplete: draft.durationMs > 0,
            firstItems: [
              for (final item in pack.items.take(_previewItems))
                PreviewItem(title: item.title, durationMs: item.durationMs),
            ],
            attribution: pack.attribution,
            alreadyInLibrary: inLibrary,
          );
        case ImportLinkKind.dharmaSeedTalk:
          final track = await source.track(id);
          return ImportPreview(
            origin: ImportOrigin.dharmaSeed,
            entryId: id,
            kind: LibraryKind.single,
            allowedKinds: const {LibraryKind.single},
            group: draft.group,
            title: draft.title,
            subtitle: draft.subtitle,
            description: track.description,
            artworkUrl: draft.coverUrl,
            sourceLabel: 'Dharma Seed',
            durationMs: draft.durationMs,
            durationComplete: draft.durationMs > 0,
            attribution: track.attribution,
            alreadyInLibrary: inLibrary,
          );
        default:
          final page = await source.teacherPage(id);
          return ImportPreview(
            origin: ImportOrigin.dharmaSeed,
            entryId: id,
            kind: LibraryKind.teacher,
            allowedKinds: const {LibraryKind.teacher},
            group: draft.group,
            title: draft.title,
            subtitle: draft.subtitle,
            description: page.teacher.bio,
            artworkUrl: draft.coverUrl,
            sourceLabel: 'Dharma Seed',
            itemCount: page.teacher.talkCount,
            durationComplete: false,
            firstItems: [
              for (final c in page.courses.take(_previewItems))
                PreviewItem(title: c.title),
            ],
            alreadyInLibrary: inLibrary,
          );
      }
    } on CatalogueEntryUnavailable {
      throw const ImportFailure(ImportFailureReason.dharmaSeedMissing);
    }
  }

  // ----------------------------------------------------------- audio / web

  Future<FetchResult> _fetch(Uri uri, {bool headersOnly = false}) async {
    try {
      final result = await http.get(uri, headersOnly: headersOnly);
      if (result.status == 404 || result.status == 410) {
        throw ImportFailure(ImportFailureReason.notFound, uri.toString());
      }
      if (!result.ok) {
        throw ImportFailure(ImportFailureReason.unreachable, '${result.status} $uri');
      }
      return result;
    } on ImportFailure {
      rethrow;
    } on SocketException catch (e) {
      throw ImportFailure(ImportFailureReason.offline, e.message);
    } on TimeoutException catch (e) {
      throw ImportFailure(ImportFailureReason.offline, e.message);
    } on HttpException catch (e) {
      throw ImportFailure(ImportFailureReason.unreachable, e.message);
    } on FormatException catch (e) {
      throw ImportFailure(ImportFailureReason.unreachable, e.message);
    } catch (e) {
      // http's ClientException (and anything the platform throws) means the
      // request never completed.
      throw ImportFailure(ImportFailureReason.offline, e.toString());
    }
  }

  Future<ImportPreview> _resolveAudioUrl(Uri uri, {FetchResult? known}) async {
    final result = known ?? await _fetch(uri, headersOnly: true);
    if (result.contentType.startsWith('text/html')) {
      throw ImportFailure(ImportFailureReason.noFeedOrAudio, uri.toString());
    }
    final url = result.finalUri.removeFragment().toString();
    final id = libTrackIdFor(uri.removeFragment().toString());
    final title = titleFromFileName(url);
    final duration = await _probe(url);
    final host = result.finalUri.host.replaceFirst(RegExp(r'^www\.'), '');
    return ImportPreview(
      origin: ImportOrigin.audioUrl,
      entryId: id,
      kind: LibraryKind.single,
      allowedKinds: const {LibraryKind.single},
      group: isKnownTalkHost(host) ? LibraryGroup.talks : LibraryGroup.practice,
      title: title,
      subtitle: host,
      sourceLabel: host,
      durationMs: duration ?? 0,
      durationComplete: duration != null,
      attribution: SourceAttribution(
        source: host,
        url: '',
        licenseName: '',
        licenseUrl: '',
      ),
      alreadyInLibrary: await library.contains(id),
      audioUrl: url,
      mimeType: result.isAudio ? result.contentType.split(';').first : '',
    );
  }

  Future<ImportPreview> _resolveWebAddress(Uri uri) async {
    final first = await _fetch(uri);
    if (first.isAudio) return _resolveAudioUrl(uri, known: first);

    final body = first.text;
    if (looksLikeFeed(body)) return _feedPreview(body, first);

    // A web page: look for the feed it advertises.
    final discovered = _discoverFeed(body, first.finalUri);
    if (discovered == null) {
      throw ImportFailure(ImportFailureReason.noFeedOrAudio, uri.toString());
    }
    final second = await _fetch(discovered);
    if (!looksLikeFeed(second.text)) {
      throw ImportFailure(ImportFailureReason.noFeedOrAudio, discovered.toString());
    }
    return _feedPreview(second.text, second);
  }

  /// The first RSS or Atom feed a page advertises in its head.
  Uri? _discoverFeed(String html, Uri base) {
    final head = html.length > 200000 ? html.substring(0, 200000) : html;
    for (final tag in RegExp(r'<link\b[^>]*>', caseSensitive: false).allMatches(head)) {
      final text = tag.group(0)!;
      final rel = _attribute(text, 'rel')?.toLowerCase() ?? '';
      final type = _attribute(text, 'type')?.toLowerCase() ?? '';
      final href = _attribute(text, 'href');
      if (!rel.split(RegExp(r'\s+')).contains('alternate') || href == null) continue;
      if (type.contains('rss') || type.contains('atom')) {
        final resolved = base.resolve(href);
        if (resolved.scheme == 'http' || resolved.scheme == 'https') return resolved;
      }
    }
    return null;
  }

  String? _attribute(String tag, String name) {
    final match = RegExp(
      '$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }

  Future<ImportPreview> _resolveApplePodcast(ImportLink link) async {
    final lookup = Uri.https('itunes.apple.com', '/lookup', {'id': '${link.id}', 'entity': 'podcast'});
    final response = await _fetch(lookup);
    String? feedUrl;
    try {
      final json = jsonDecode(response.text) as Map<String, dynamic>;
      final results = json['results'] as List<dynamic>? ?? const [];
      if (results.isNotEmpty) {
        feedUrl = (results.first as Map<String, dynamic>)['feedUrl'] as String?;
      }
    } on FormatException {
      feedUrl = null;
    }
    final feed = feedUrl == null ? null : Uri.tryParse(feedUrl);
    if (feed == null || !feed.hasScheme) {
      throw ImportFailure(ImportFailureReason.noFeedOrAudio, link.raw);
    }
    final fetched = await _fetch(feed);
    if (!looksLikeFeed(fetched.text)) {
      throw ImportFailure(ImportFailureReason.noFeedOrAudio, feed.toString());
    }
    return _feedPreview(fetched.text, fetched);
  }

  // ------------------------------------------------------------------ feeds

  Future<ImportPreview> _feedPreview(String body, FetchResult response) async {
    final ParsedFeed feed;
    try {
      feed = parseFeed(body, base: response.finalUri);
    } on FeedFormatException catch (e) {
      throw ImportFailure(ImportFailureReason.brokenFeed, e.message);
    }
    if (feed.episodes.isEmpty) {
      throw ImportFailure(ImportFailureReason.noEpisodes, feed.title);
    }
    final feedUrl = response.finalUri.removeFragment().toString();
    final courseId = libCourseIdFor(feedUrl);
    final host = response.finalUri.host.replaceFirst(RegExp(r'^www\.'), '');
    final siteHost = Uri.tryParse(feed.siteUrl)?.host ?? '';
    final talks = isKnownTalkHost(host) || (siteHost.isNotEmpty && isKnownTalkHost(siteHost));
    return ImportPreview(
      origin: ImportOrigin.feed,
      entryId: courseId,
      kind: LibraryKind.course,
      allowedKinds: const {LibraryKind.course, LibraryKind.single},
      group: talks ? LibraryGroup.talks : LibraryGroup.practice,
      title: feed.title,
      subtitle: feed.author,
      description: feed.description,
      artworkUrl: feed.imageUrl,
      sourceLabel: siteHost.isNotEmpty ? siteHost.replaceFirst(RegExp(r'^www\.'), '') : host,
      itemCount: feed.episodes.length,
      durationMs: feed.totalDurationMs,
      durationComplete: feed.durationComplete,
      firstItems: [
        for (final e in feed.episodes.take(_previewItems))
          PreviewItem(title: e.title, durationMs: e.durationMs),
      ],
      attribution: SourceAttribution(
        source: siteHost.isNotEmpty ? siteHost.replaceFirst(RegExp(r'^www\.'), '') : host,
        creator: feed.author.isEmpty ? null : feed.author,
        url: feed.siteUrl.isNotEmpty ? feed.siteUrl : feedUrl,
        licenseName: feed.licenseName,
        licenseUrl: feed.licenseUrl,
      ),
      alreadyInLibrary: await library.contains(courseId),
      skippedItems: feed.skippedItems,
      feed: feed,
      feedUrl: feedUrl,
      etag: response.etag,
      lastModified: response.lastModified,
    );
  }

  // ------------------------------------------------------------ local files

  static const _audioExtensions = {
    '.mp3', '.m4a', '.aac', '.ogg', '.oga', '.opus', '.wav', '.flac', '.m4b', '.wma', '.weba',
  };

  static bool isAudioPath(String path) =>
      _audioExtensions.contains(p.extension(path).toLowerCase());

  /// A folder: its audio files, in name order, become a course.
  Future<ImportPreview> resolveDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw ImportFailure(ImportFailureReason.fileMissing, path);
    }
    final files = <PickedFile>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && isAudioPath(entity.path)) {
        files.add(PickedFile(path: entity.path, sizeBytes: await entity.length()));
      }
    }
    if (files.isEmpty) throw ImportFailure(ImportFailureReason.noAudioFiles, path);
    files.sort((a, b) => _naturalCompare(p.basename(a.path), p.basename(b.path)));
    return resolveFiles(files, suggestedTitle: p.basename(path));
  }

  /// Files picked or shared: one is a single, several a course (or singles).
  Future<ImportPreview> resolveFiles(
    List<PickedFile> files, {
    String? suggestedTitle,
  }) async {
    if (files.isEmpty) throw const ImportFailure(ImportFailureReason.noAudioFiles);
    for (final file in files) {
      if (!await File(file.path).exists()) {
        throw ImportFailure(ImportFailureReason.fileMissing, file.path);
      }
    }
    final audio = [
      for (final file in files)
        if (isAudioPath(file.name ?? file.path) ||
            (file.mimeType ?? '').startsWith('audio/'))
          file,
    ];
    if (audio.isEmpty) throw const ImportFailure(ImportFailureReason.noAudioFiles);

    final durations = await Future.wait([for (final f in audio) _probe(f.path)]);
    final multiple = audio.length > 1;
    final known = durations.whereType<int>().fold(0, (a, b) => a + b);
    final titles = [for (final f in audio) titleFromFileName(f.name ?? f.path)];
    return ImportPreview(
      origin: ImportOrigin.localFiles,
      entryId: '',
      kind: multiple ? LibraryKind.course : LibraryKind.single,
      allowedKinds: multiple
          ? const {LibraryKind.course, LibraryKind.single}
          : const {LibraryKind.single},
      group: LibraryGroup.practice,
      title: multiple ? (suggestedTitle ?? '') : titles.first,
      subtitle: '',
      sourceLabel: 'This device',
      itemCount: audio.length,
      durationMs: known,
      durationComplete: durations.every((d) => d != null),
      firstItems: [
        for (var i = 0; i < audio.length && i < _previewItems; i++)
          PreviewItem(title: titles[i], durationMs: durations[i]),
      ],
      files: audio,
      fileDurationsMs: durations,
    );
  }

  Future<int?> _probe(String pathOrUrl) async {
    final probe = durationProbe;
    if (probe == null) return null;
    try {
      final ms = await probe(pathOrUrl).timeout(const Duration(seconds: 8));
      return ms != null && ms > 0 ? ms : null;
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------- add

  /// Stores the preview as the user chose and puts it in the library. Adding
  /// something already there changes nothing and says so.
  Future<ImportResult> add(ImportPreview preview, ImportChoice choice) async {
    final kind = preview.allowedKinds.contains(choice.kind) ? choice.kind : preview.kind;
    switch (preview.origin) {
      case ImportOrigin.dharmaSeed:
        return _addDharmaSeed(preview, choice);
      case ImportOrigin.feed:
        return kind == LibraryKind.course
            ? _addFeedCourse(preview, choice)
            : _addFeedLatest(preview, choice);
      case ImportOrigin.audioUrl:
        return _addAudioUrl(preview, choice);
      case ImportOrigin.localFiles:
        return _addFiles(preview, choice, asCourse: kind == LibraryKind.course);
    }
  }

  /// Puts [id] in the library. The detected group is the preview's; a
  /// different choice by the user is stored as an override, so "detected"
  /// stays what the app saw.
  Future<ImportResult> _finish(
    String id,
    LibraryKind kind,
    ImportChoice choice,
    ImportPreview preview, {
    LibraryDraft? draft,
  }) async {
    final fresh = draft ?? await lib.draftFor(id, group: preview.group);
    final added = await library.add(
      LibraryDraft(
        sourceId: id,
        kind: kind,
        title: fresh?.title ?? preview.title,
        group: preview.group,
        subtitle: fresh?.subtitle ?? preview.subtitle,
        coverUrl: fresh?.coverUrl ?? preview.artworkUrl,
        itemCount: fresh?.itemCount ?? preview.itemCount,
        durationMs: fresh?.durationMs ?? preview.durationMs,
      ),
    );
    if (added) {
      if (choice.group != preview.group) await library.setGroup(id, choice.group);
      await _applyTitle(id, choice, fresh?.title ?? preview.title);
    }
    return ImportResult(entryId: id, kind: kind, alreadyPresent: !added);
  }

  Future<void> _applyTitle(String id, ImportChoice choice, String original) async {
    final wanted = choice.title?.trim();
    if (wanted != null && wanted.isNotEmpty && wanted != original) {
      await library.setTitle(id, wanted);
    }
  }

  Future<ImportResult> _addDharmaSeed(ImportPreview preview, ImportChoice choice) async {
    final source = dharmaSeed!;
    final draft = await source.libraryDraft(preview.entryId);
    if (draft == null) throw const ImportFailure(ImportFailureReason.dharmaSeedMissing);
    return _finish(preview.entryId, preview.kind, choice, preview, draft: draft);
  }

  Future<ImportResult> _addFeedCourse(ImportPreview preview, ImportChoice choice) async {
    await lib.storeFeed(
      courseId: preview.entryId,
      feedUrl: preview.feedUrl!,
      feed: preview.feed!,
      episodeOrder: choice.episodeOrder,
      etag: preview.etag,
      lastModified: preview.lastModified,
      now: _clock(),
    );
    return _finish(preview.entryId, LibraryKind.course, choice, preview);
  }

  Future<ImportResult> _addFeedLatest(ImportPreview preview, ImportChoice choice) async {
    final latest = preview.feed!.episodes.last;
    final id = await lib.storeEpisode(
      latest,
      feedUrl: preview.feedUrl!,
      now: _clock(),
    );
    return _finish(id, LibraryKind.single, choice, preview);
  }

  Future<ImportResult> _addAudioUrl(ImportPreview preview, ImportChoice choice) async {
    final id = preview.entryId;
    await lib.storeSingle(
      id: id,
      title: preview.title,
      audioUrl: preview.audioUrl!,
      mimeType: preview.mimeType ?? '',
      durationMs: preview.durationMs,
      pageUrl: '',
      now: _clock(),
    );
    return _finish(id, LibraryKind.single, choice, preview);
  }

  Future<ImportResult> _addFiles(
    ImportPreview preview,
    ImportChoice choice, {
    required bool asCourse,
  }) async {
    final stored = <StoredFile>[];
    for (var i = 0; i < preview.files.length; i++) {
      final file = preview.files[i];
      final id = newLibTrackId();
      final path = await _copyIntoStorage(file.path, id);
      stored.add(
        StoredFile(
          id: id,
          title: titleFromFileName(file.name ?? file.path),
          path: path,
          mimeType: file.mimeType ?? '',
          durationMs: i < preview.fileDurationsMs.length ? preview.fileDurationsMs[i] ?? 0 : 0,
        ),
      );
    }
    final now = _clock();
    if (asCourse) {
      final courseId = newLibCourseId();
      final title = (choice.title?.trim().isNotEmpty ?? false)
          ? choice.title!.trim()
          : (preview.title.isNotEmpty ? preview.title : 'Imported audio');
      await lib.storeFileCourse(courseId: courseId, title: title, files: stored, now: now);
      return _finish(courseId, LibraryKind.course, ImportChoice(kind: choice.kind, group: choice.group), preview);
    }
    String? first;
    for (final file in stored) {
      await lib.storeSingle(
        id: file.id,
        title: file.title,
        audioUrl: file.path,
        isLocalFile: true,
        mimeType: file.mimeType,
        durationMs: file.durationMs,
        now: now,
      );
      final single = await lib.draftFor(file.id, group: preview.group);
      await library.add(single!);
      if (choice.group != preview.group) await library.setGroup(file.id, choice.group);
      first ??= file.id;
    }
    // A single file keeps a title the user typed.
    if (stored.length == 1) await _applyTitle(first!, choice, stored.first.title);
    return ImportResult(entryId: first!, kind: LibraryKind.single, addedCount: stored.length);
  }

  /// Moves a file into app storage, or copies it when it cannot be moved
  /// (another volume). The original of a picked file is a cache copy that
  /// nothing else wants; a file the user pointed at by path is left alone.
  Future<String> _copyIntoStorage(String source, String id) async {
    final directory = await storageDirectory();
    final folder = Directory(p.join(directory.path, 'library'));
    await folder.create(recursive: true);
    var extension = p.extension(source).toLowerCase();
    if (!_audioExtensions.contains(extension)) extension = '.audio';
    final target = p.join(folder.path, '$id$extension');
    final file = File(source);
    final isCache = source.contains('${Platform.pathSeparator}cache${Platform.pathSeparator}');
    if (isCache) {
      try {
        await file.rename(target);
        return target;
      } on FileSystemException {
        // Fall through to copy.
      }
    }
    await file.copy(target);
    if (isCache) {
      try {
        await file.delete();
      } catch (e) {
        AppLogger.w('LIBRARY', 'Could not remove the temporary copy: $e');
      }
    }
    return target;
  }
}

/// Orders "Session 2" before "Session 10".
int _naturalCompare(String a, String b) {
  final pattern = RegExp(r'(\d+|\D+)');
  final left = pattern.allMatches(a.toLowerCase()).map((m) => m.group(0)!).toList();
  final right = pattern.allMatches(b.toLowerCase()).map((m) => m.group(0)!).toList();
  for (var i = 0; i < left.length && i < right.length; i++) {
    final x = int.tryParse(left[i]);
    final y = int.tryParse(right[i]);
    final c = (x != null && y != null) ? x.compareTo(y) : left[i].compareTo(right[i]);
    if (c != 0) return c;
  }
  return left.length.compareTo(right.length);
}
