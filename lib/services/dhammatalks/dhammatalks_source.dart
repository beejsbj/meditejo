import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/catalogue_source.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';
import 'package:medito/services/dhammatalks/dhammatalks_feed.dart';
import 'package:medito/services/dhammatalks/dhammatalks_ids.dart';
import 'package:medito/services/library/import_http.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';

/// Thanissaro Bhikkhu's dhammatalks.org as a built-in catalogue (`dt-`).
///
/// The back catalogue ships in the app as a metadata-only snapshot (titles,
/// dates and file addresses; see `tools/meditejo/dhammatalks.py`). What was
/// given since is read from the site's two RSS feeds when Explore opens, never
/// at startup, and kept on the device. Audio is never fetched until played,
/// and streams unmodified from dhammatalks.org (CC BY-NC 4.0; every item
/// carries its credit and the licence link).
///
/// A collection (the guided meditations, Basics, …) is a course; a talk is a
/// single; a year of the evening or morning archive is a course-like list that
/// cannot be kept (the talks in it can). There is one teacher page.
class DhammatalksSource
    implements CatalogueSource, SavableContentSource, ParentedContentSource {
  DhammatalksSource({
    required this.loadSnapshot,
    this.http,
    DtFeedCache? cache,
    this.library,
    DateTime Function()? clock,
    this.feedInterval = const Duration(hours: 6),
  }) : cache = cache ?? MemoryDtFeedCache(),
       _clock = clock ?? DateTime.now;

  /// Reads the bundled snapshot.
  final Future<DtCatalogue> Function() loadSnapshot;

  /// For the RSS feeds. Null in tests that only read.
  final ImportHttp? http;
  final DtFeedCache cache;

  /// The user's library, where saves go. Null in tests that only read.
  final LibraryStore? library;
  final Duration feedInterval;
  final DateTime Function() _clock;

  @override
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<DtCatalogue>? _loading;
  DtCatalogue? _catalogue;
  DateTime? _feedFetchedAt;
  Future<void>? _catchingUp;

  @override
  String get prefix => dhammatalksPrefix;

  @override
  String get name => 'Dhammatalks';

  @override
  bool ownsTeacher(String id) => id == dtTeacherId;

  /// The snapshot with whatever the feeds added on earlier runs, loaded once.
  Future<DtCatalogue> catalogue() => _loading ??= () async {
    var loaded = await loadSnapshot();
    final remembered = await cache.read();
    if (remembered != null) {
      _feedFetchedAt = remembered.fetchedAt;
      loaded = loaded.withFeed(remembered.talks);
    }
    return _catalogue = loaded;
  }();

  // ---------------------------------------------------------------- refresh

  /// Reads the evening and morning feeds (one request each, one after the
  /// other) unless they were read within [feedInterval], and merges what they
  /// hold. Offline or failing, it keeps what is on the device.
  @override
  Future<void> catchUp({bool force = false}) =>
      _catchingUp ??= _catchUp(force).whenComplete(() => _catchingUp = null);

  Future<void> _catchUp(bool force) async {
    final client = http;
    if (client == null) return;
    try {
      var loaded = await catalogue();
      final last = _feedFetchedAt;
      if (!force && last != null && _clock().difference(last) < feedInterval) {
        return;
      }
      final fresh = <DtTalk>[];
      for (final (channel, url) in [
        (DtChannel.evening, dtEveningFeedUrl),
        (DtChannel.morning, dtMorningFeedUrl),
      ]) {
        final result = await client.get(Uri.parse(url));
        if (!result.ok) {
          AppLogger.w('DHAMMATALKS', 'Feed ${result.status} for $url');
          continue;
        }
        fresh.addAll(dtTalksFromFeed(result.text, channel));
      }
      if (fresh.isEmpty) return;
      final before = loaded.talks.length;
      loaded = loaded.withFeed(fresh);
      _catalogue = loaded;
      _feedFetchedAt = _clock();
      // Keep every talk the feeds added that the snapshot lacks, so a talk the
      // user kept stays playable after the feed moves on.
      final remembered = await cache.read();
      final all = {
        for (final t in [...?remembered?.talks, ...fresh]) t.id: t,
      };
      await cache.write(
        DtFeedState(fetchedAt: _feedFetchedAt!, talks: all.values.toList()),
      );
      if (loaded.talks.length != before || fresh.any((t) => t.durationMs > 0)) {
        revision.value++;
      }
    } catch (e) {
      AppLogger.w('DHAMMATALKS', 'Feed catch-up skipped: $e');
    }
  }

  // ---------------------------------------------------------- ContentSource

  @override
  Future<List<PackModel>> browsePacks() async {
    final cat = await catalogue();
    return [for (final course in cat.courses) _packOf(course)];
  }

  @override
  Future<PackModel> pack(String id) async {
    final cat = await catalogue();
    if (parseDtCourseId(id) case final courseId?) {
      final course = cat.course(courseId);
      if (course != null) return _packOf(course);
    }
    if (parseDtYearId(id) case final year?) {
      final talks = cat.yearTalks(year.channel, year.year);
      if (talks.isNotEmpty)
        return _yearPack(id, year.channel, year.year, talks);
    }
    throw CatalogueEntryUnavailable('pack', id);
  }

  @override
  Future<Track> track(String id) async {
    final cat = await catalogue();
    final talk = cat.talk(id);
    if (talk == null) throw CatalogueEntryUnavailable('track', id);
    return mapTalk(talk);
  }

  /// Saved collections plus collections holding a started talk. Years are
  /// never listed: they are archives, not courses to follow.
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async {
    final cat = await catalogue();
    final saved = {
      for (final e in await library?.entries() ?? const <LibraryEntry>[])
        e.sourceId,
    };
    return {
      for (final course in cat.courses)
        if (saved.contains(course.appId) ||
            course.items.any((t) => startedTrackIds.contains(t.id)))
          course.appId: [for (final t in course.items) t.id],
    };
  }

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async {
    final terms = DtCatalogue.termsOf(query);
    if (terms.isEmpty) return const [];
    final cat = await catalogue();
    return [
      for (final course in cat.courses)
        if (_matches(terms, '${course.title} ${course.description}'))
          _courseItem(course),
    ];
  }

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async {
    final cat = await catalogue();
    return [
      for (final talk in cat.search(query))
        TrackSearchModel(
          id: talk.id,
          title: talk.title,
          subtitle: _talkSubtitle(talk),
          description: '',
          coverUrl: '',
          path: '/tracks/${talk.id}',
        ),
    ];
  }

  // ----------------------------------------------------------------- saving

  @override
  bool canSave(String id) =>
      isDtTalkId(id) || isDtCourseId(id) || id == dtTeacherId;

  @override
  Future<bool> isSaved(String id) async =>
      canSave(id) && await library?.contains(id) == true;

  @override
  Future<void> setSaved(String id, {required bool saved}) async {
    final store = library;
    if (store == null || !canSave(id)) return;
    if (!saved) return store.remove(id);
    final draft = await libraryDraft(id);
    if (draft != null) await store.add(draft);
  }

  /// How the library describes a dhammatalks.org course, talk or the teacher.
  /// Null when the catalogue does not hold it.
  @override
  Future<LibraryDraft?> libraryDraft(String id) async {
    final cat = await catalogue();
    if (parseDtCourseId(id) case final courseId?) {
      final course = cat.course(courseId);
      if (course == null) return null;
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.course,
        title: course.title,
        group: course.group == ContentGroup.practice
            ? LibraryGroup.practice
            : LibraryGroup.talks,
        subtitle: _courseSubtitle(course),
        itemCount: course.items.length,
        durationMs: course.durationMs,
      );
    }
    if (isDtTalkId(id)) {
      final talk = cat.talk(id);
      if (talk == null) return null;
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.single,
        title: talk.title,
        group: talk.practice ? LibraryGroup.practice : LibraryGroup.talks,
        subtitle: _talkSubtitle(talk),
        durationMs: talk.durationMs,
      );
    }
    if (id == dtTeacherId) {
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.teacher,
        title: dtTeacherName,
        subtitle: '${cat.talkCount} talks',
        itemCount: cat.talkCount,
      );
    }
    return null;
  }

  @override
  Future<String?> parentOf(String trackId) async =>
      (await catalogue()).courseOfCollectionTalk(trackId)?.appId;

  // -------------------------------------------------------------- links

  /// The built-in item a dhammatalks.org address names, or null: a talk's page
  /// or file, a year of the archive, the guided meditations or a collection.
  Future<String?> idForLink(Uri uri) async {
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host != 'dhammatalks.org') return null;
    final cat = await catalogue();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();

    if (segments.length >= 2 && segments[0] == 'audio') {
      final channel = DtChannel.values
          .where((c) => c.path == segments[1])
          .firstOrNull;
      if (channel != null) {
        if (segments.length == 2) {
          // The landing page is the newest year.
          final years = cat.years(channel);
          return years.isEmpty ? null : dtYearId(channel, years.first);
        }
        if (segments.length == 3) {
          final year = int.tryParse(segments[2]);
          return year == null || cat.yearTalks(channel, year).isEmpty
              ? null
              : dtYearId(channel, year);
        }
        if (segments.length == 4 && segments[3].endsWith('.html')) {
          final key = segments[3].substring(0, segments[3].length - 5);
          final id = dtTalkId(channel.code, key);
          return cat.talk(id) == null ? null : id;
        }
      }
    }
    if (segments.length == 1 && segments[0] == 'mp3_guidedMed_index.html') {
      return dtCourseId('guided');
    }
    if (segments.length == 1 && segments[0] == 'mp3_collections_index.html') {
      return cat.course(uri.fragment) == null ? null : dtCourseId(uri.fragment);
    }
    if (uri.path.toLowerCase().endsWith('.mp3')) {
      return cat.talkForAudio(uri.path)?.id;
    }
    return null;
  }

  // ------------------------------------------------------ Catalogue screens

  @override
  Future<CatalogueExplore> explore({ContentGroup? group}) async {
    final cat = await catalogue();
    final saved = {
      for (final e in await library?.entries() ?? const <LibraryEntry>[])
        e.sourceId,
    };
    final teacher = _teacher(cat);
    final following = saved.contains(dtTeacherId);
    final held = cat.talkCount > 0;
    return CatalogueExplore(
      courses: [
        for (final course in cat.courses)
          if ((group == null || course.group == group) &&
              !saved.contains(course.appId))
            _courseItem(course),
      ],
      savedTeachers: held && following ? [teacher] : const [],
      teachers: held && !following ? [teacher] : const [],
      // With no chip, guided practice leads (BRIEF decision 11); Talks shows
      // the latest given.
      talks: [
        for (final talk
            in group == ContentGroup.talks
                ? cat.talks.take(20)
                : [
                    for (final course in cat.courses)
                      if (course.group == ContentGroup.practice)
                        ...course.items,
                  ])
          _talkItem(talk),
      ],
      archives: group == ContentGroup.practice ? const [] : _archives(cat),
      hasCatalogue: held,
    );
  }

  @override
  Future<CatalogueSearchResults> search(
    String query, {
    SessionLength? length,
  }) async {
    final terms = DtCatalogue.termsOf(query);
    if (terms.isEmpty) return const CatalogueSearchResults();
    final cat = await catalogue();
    final talks = cat.search(query);
    return CatalogueSearchResults(
      teachers:
          cat.talkCount > 0 &&
              _matches(terms, '$dtTeacherName ajaan geoff thanissaro')
          ? [_teacher(cat)]
          : const [],
      courses: [
        for (final course in cat.courses)
          if (_matches(terms, '${course.title} ${course.description}'))
            _courseItem(course),
      ],
      // The archive pages carry no length, so a length filter keeps only the
      // talks that have one.
      talks: [
        for (final talk in talks)
          if (length == null ||
              (talk.durationMs > 0 &&
                  length.matches(Duration(milliseconds: talk.durationMs))))
            _talkItem(talk),
      ],
    );
  }

  @override
  Future<CatalogueTeacherPage> teacherPage(
    String id, {
    int talkPage = 30,
  }) async {
    if (id != dtTeacherId) throw CatalogueEntryUnavailable('teacher', id);
    final cat = await catalogue();
    return CatalogueTeacherPage(
      teacher: _teacher(cat),
      courses: [for (final course in cat.courses) _courseItem(course)],
      talks: [for (final talk in cat.talks.take(talkPage)) _talkItem(talk)],
      hasMoreTalks: cat.talks.length > talkPage,
    );
  }

  @override
  Future<List<PackItemsModel>> teacherTalks(
    String id, {
    required int offset,
    int limit = 30,
  }) async {
    if (id != dtTeacherId) return const [];
    final cat = await catalogue();
    return [
      for (final talk in cat.talks.skip(offset).take(limit)) _talkItem(talk),
    ];
  }

  // ---------------------------------------------------------------- mapping

  static bool _matches(List<String> terms, String text) {
    final words = DtCatalogue.termsOf(text);
    return terms.every((t) => words.any((w) => w.startsWith(t)));
  }

  static SourceAttribution attribution({required String url}) =>
      SourceAttribution(
        source: 'dhammatalks.org',
        creator: dtTeacherName,
        url: url,
        licenseName: dhammatalksLicenceName,
        licenseUrl: dhammatalksLicenceUrl,
      );

  static const _bio =
      'An American-born monk of the Thai Forest Tradition, ordained in '
      'Thailand in 1976 and a student of Ajaan Fuang Jotiko. Abbot of Metta '
      'Forest Monastery in Valley Center, California. His talks, given most '
      'evenings and mornings, centre on breath meditation, right '
      'concentration (jhāna) and the Pali Canon.';

  CatalogueTeacher _teacher(DtCatalogue cat) => CatalogueTeacher(
    id: dtTeacherId,
    name: dtTeacherName,
    bio: _bio,
    website: dhammatalksSite,
    pageUrl: dhammatalksSite,
    talkCount: cat.talkCount,
    retreatCount: cat.courses.length,
    attribution: attribution(url: dhammatalksSite),
  );

  PackModel _packOf(DtCourse course) => PackModel(
    id: course.appId,
    title: course.title,
    subtitle: _courseSubtitle(course),
    coverUrl: '',
    path: '/packs/${course.appId}',
    description: course.description,
    isPublished: true,
    items: [for (final talk in course.items) _talkItem(talk)],
    teacher: PackTeacher(
      id: dtTeacherId,
      name: dtTeacherName,
      bio: _bio,
      pageUrl: dhammatalksSite,
    ),
    attribution: attribution(url: course.pageUrl),
  );

  PackModel _yearPack(
    String id,
    DtChannel channel,
    int year,
    List<DtTalk> talks,
  ) => PackModel(
    id: id,
    title: '${channel.label}s $year',
    subtitle: '$dtTeacherName · ${talks.length} talks',
    coverUrl: '',
    path: '/packs/$id',
    description:
        'Thanissaro Bhikkhu\'s ${channel.path} talks from $year, newest first.',
    isPublished: true,
    items: [for (final talk in talks) _talkItem(talk)],
    teacher: PackTeacher(
      id: dtTeacherId,
      name: dtTeacherName,
      bio: _bio,
      pageUrl: dhammatalksSite,
    ),
    attribution: attribution(
      url: '$dhammatalksSite/audio/${channel.path}/$year/',
    ),
  );

  PackItemsModel _courseItem(DtCourse course) => PackItemsModel(
    type: TypeConstants.pack,
    id: course.appId,
    title: course.title,
    subtitle: _courseSubtitle(course),
    coverUrl: '',
    path: '/packs/${course.appId}',
  );

  /// The year lists Explore offers: evening years, then morning years.
  List<PackItemsModel> _archives(DtCatalogue cat) => [
    for (final channel in DtChannel.values)
      for (final year in cat.years(channel))
        PackItemsModel(
          type: TypeConstants.pack,
          id: dtYearId(channel, year),
          title:
              '${channel == DtChannel.evening ? 'Evening' : 'Morning'} $year',
          subtitle: '${cat.yearTalks(channel, year).length} talks',
          coverUrl: '',
          path: '/packs/${dtYearId(channel, year)}',
        ),
  ];

  static PackItemsModel _talkItem(DtTalk talk) => PackItemsModel(
    type: TypeConstants.track,
    id: talk.id,
    title: talk.title,
    subtitle: _talkSubtitle(talk),
    coverUrl: '',
    path: '/tracks/${talk.id}',
    kind: _kindLabel(talk),
    teacher: dtTeacherName,
    durationMs: talk.durationMs > 0 ? talk.durationMs : null,
    date: talk.date.length >= 10 ? talk.date : null,
  );

  static String _kindLabel(DtTalk talk) =>
      talk.practice ? 'Guided meditation' : talk.channel?.label ?? 'Talk';

  /// "Evening talk · Thanissaro Bhikkhu · 11 min"
  static String _talkSubtitle(DtTalk talk) {
    final minutes = (talk.durationMs / Duration.millisecondsPerMinute).round();
    return [
      _kindLabel(talk),
      dtTeacherName,
      if (minutes > 0) '$minutes min',
    ].join(' · ');
  }

  /// "Thanissaro Bhikkhu · 50 talks"
  static String _courseSubtitle(DtCourse course) {
    final count = course.items.length;
    return '$dtTeacherName · $count ${count == 1 ? 'talk' : 'talks'}';
  }

  /// One voice, one file: the original dhammatalks.org audio, unmodified.
  static Track mapTalk(DtTalk talk) => Track(
    id: talk.id,
    title: talk.title,
    subtitle: _talkSubtitle(talk),
    description: '',
    coverUrl: '',
    isPublished: true,
    // Ambient sound suits sitting with a guided meditation, not a talk.
    hasBackgroundSound: talk.practice,
    artist: TrackArtist(name: dtTeacherName, path: talk.pageUrl),
    attribution: attribution(url: talk.pageUrl),
    voices: [
      TrackVoice(
        guideName: dtTeacherName,
        audioFiles: [
          TrackAudioFile(
            id: talk.id,
            path: talk.audioUrl,
            duration: talk.durationMs,
          ),
        ],
      ),
    ],
  );
}
