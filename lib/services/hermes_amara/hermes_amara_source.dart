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
import 'package:medito/services/hermes_amara/hermes_amara_flag.dart';
import 'package:medito/services/hermes_amara/hermes_amara_ids.dart';
import 'package:medito/services/hermes_amara/hermes_amara_listing.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';

/// The last listing read, and when: what survives between launches.
class HaListingState {
  const HaListingState({required this.raw, required this.fetchedAt});

  /// The listing page exactly as it was fetched.
  final String raw;
  final DateTime fetchedAt;
}

/// Where [HaListingState] is kept.
abstract interface class HaListingCache {
  Future<HaListingState?> read();
  Future<void> write(HaListingState state);
}

class MemoryHaListingCache implements HaListingCache {
  MemoryHaListingCache([this.state]);

  HaListingState? state;

  @override
  Future<HaListingState?> read() async => state;

  @override
  Future<void> write(HaListingState value) async => state = value;
}

/// Rob Burbea's teachings from the Hermes Amāra Foundation (hermesamara.org)
/// as a built-in catalogue (`ha-`). **Dormant** unless [hermesAmaraEnabled]
/// (or [enabled]) is on: the site states no licence and permission is not yet
/// given, so a disabled source fetches nothing and answers every read empty.
///
/// Nothing is fetched until [catchUp], which the app calls when Explore
/// opens, never at startup. The listing page is read at most every
/// [refreshInterval] and kept on the device; audio is never copied, only
/// streamed from the address the site's own talk page plays.
///
/// A retreat (the listing's `event`) is a course with its talks in order; a
/// talk given on its own is a single. There is no teacher page: Rob Burbea
/// is already Dharma Seed's teacher 210.
class HermesAmaraSource implements CatalogueSource, SavableContentSource {
  HermesAmaraSource({
    required this.fetchListing,
    this.library,
    HaListingCache? cache,
    DateTime Function()? clock,
    this.refreshInterval = const Duration(hours: 12),
    this.enabled = hermesAmaraEnabled,
  }) : cache = cache ?? MemoryHaListingCache(),
       _clock = clock ?? DateTime.now;

  /// Fetches the listing page's HTML (the app passes a GET of [haListingUrl]
  /// with its User-Agent). Called only from [catchUp].
  final Future<String> Function() fetchListing;

  /// The user's library, where saves go. Null in tests that only read.
  final LibraryStore? library;
  final HaListingCache cache;
  final Duration refreshInterval;

  /// False leaves the whole source inert. Defaults to [hermesAmaraEnabled].
  final bool enabled;
  final DateTime Function() _clock;

  @override
  final ValueNotifier<int> revision = ValueNotifier(0);

  Future<void>? _loading;
  Future<void>? _catchingUp;
  HaListing _listing = HaListing.empty;
  DateTime? _fetchedAt;

  @override
  String get prefix => hermesAmaraPrefix;

  @override
  String get name => 'Hermes Amāra';

  @override
  bool ownsTeacher(String id) => false;

  /// The listing kept on the device, parsed once; empty before the first
  /// refresh or when the source is disabled.
  Future<HaListing> listing() async {
    if (!enabled) return HaListing.empty;
    await (_loading ??= _loadCached());
    return _listing;
  }

  Future<void> _loadCached() async {
    try {
      final remembered = await cache.read();
      if (remembered == null) return;
      _listing = parseHermesListing(remembered.raw);
      _fetchedAt = remembered.fetchedAt;
    } catch (e) {
      AppLogger.w('HERMES', 'Cached listing unreadable: $e');
    }
  }

  // ---------------------------------------------------------------- refresh

  /// Reads the listing page unless it was read within [refreshInterval]
  /// ([force] reads it regardless). Offline, failing or unreadable, it keeps
  /// the listing already on the device.
  @override
  Future<void> catchUp({bool force = false}) {
    if (!enabled) return Future.value();
    return _catchingUp ??= _catchUp(
      force,
    ).whenComplete(() => _catchingUp = null);
  }

  Future<void> _catchUp(bool force) async {
    try {
      await listing();
      final last = _fetchedAt;
      if (!force &&
          last != null &&
          _clock().difference(last) < refreshInterval) {
        return;
      }
      final raw = await fetchListing();
      final fresh = parseHermesListing(raw);
      if (fresh.isEmpty) {
        AppLogger.w('HERMES', 'Listing held no talks; keeping the cached one');
        return;
      }
      final changed = fresh.fingerprint != _listing.fingerprint;
      _listing = fresh;
      _fetchedAt = _clock();
      await cache.write(HaListingState(raw: raw, fetchedAt: _fetchedAt!));
      if (changed) revision.value++;
    } catch (e) {
      AppLogger.w('HERMES', 'Catch-up skipped: $e');
    }
  }

  // ---------------------------------------------------------- ContentSource

  @override
  Future<List<PackModel>> browsePacks() async {
    final all = await listing();
    return [for (final event in all.events) _packOf(event)];
  }

  @override
  Future<PackModel> pack(String id) async {
    final all = await listing();
    if (parseHaRetreatId(id) case final slug?) {
      final event = all.event(slug);
      if (event != null) return _packOf(event);
    }
    throw CatalogueEntryUnavailable('pack', id);
  }

  @override
  Future<Track> track(String id) async {
    final all = await listing();
    final talk = parseHaTalkId(id) == null
        ? null
        : all.talk(parseHaTalkId(id)!);
    if (talk == null) throw CatalogueEntryUnavailable('track', id);
    return mapTalk(talk);
  }

  /// Saved retreats plus retreats holding a started talk.
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async {
    final all = await listing();
    final saved = await _savedIds();
    return {
      for (final event in all.events)
        if (saved.contains(event.id) ||
            event.talks.any((t) => startedTrackIds.contains(t.id)))
          event.id: [for (final t in event.talks) t.id],
    };
  }

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async {
    final terms = haTerms(query);
    if (terms.isEmpty) return const [];
    final all = await listing();
    return [
      for (final event in all.events)
        if (_matches(terms, event.name)) _courseItem(event),
    ];
  }

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async {
    final terms = haTerms(query);
    if (terms.isEmpty) return const [];
    final all = await listing();
    return [
      for (final talk in all.talks)
        if (_matchesTalk(terms, talk))
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
  bool canSave(String id) => enabled && (isHaTalkId(id) || isHaRetreatId(id));

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

  /// How the library describes a retreat or a talk; null when the listing
  /// does not hold it.
  @override
  Future<LibraryDraft?> libraryDraft(String id) async {
    final all = await listing();
    if (parseHaRetreatId(id) case final slug?) {
      final event = all.event(slug);
      if (event == null) return null;
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.course,
        title: event.name,
        group: event.practice ? LibraryGroup.practice : LibraryGroup.talks,
        subtitle: _courseSubtitle(event),
        itemCount: event.talks.length,
        durationMs: event.durationMs,
      );
    }
    if (parseHaTalkId(id) case final slug?) {
      final talk = all.talk(slug);
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
    return null;
  }

  Future<Set<String>> _savedIds() async => {
    for (final e in await library?.entries() ?? const <LibraryEntry>[])
      e.sourceId,
  };

  // ------------------------------------------------------ Catalogue screens

  @override
  Future<CatalogueExplore> explore({ContentGroup? group}) async {
    final all = await listing();
    final saved = await _savedIds();
    bool inGroup(bool practice) =>
        group == null || practice == (group == ContentGroup.practice);
    return CatalogueExplore(
      courses: [
        for (final event in all.events)
          if (inGroup(event.practice) && !saved.contains(event.id))
            _courseItem(event),
      ],
      talks: [
        for (final talk in all.talks.where((t) => inGroup(t.practice)).take(20))
          _talkItem(talk),
      ],
      hasCatalogue: !all.isEmpty,
    );
  }

  @override
  Future<CatalogueSearchResults> search(
    String query, {
    SessionLength? length,
  }) async {
    final terms = haTerms(query);
    if (terms.isEmpty) return const CatalogueSearchResults();
    final all = await listing();
    return CatalogueSearchResults(
      courses: [
        for (final event in all.events)
          if (_matches(terms, event.name)) _courseItem(event),
      ],
      // A talk with no length cannot be placed in one, so a length filter
      // drops it.
      talks: [
        for (final talk in all.talks)
          if (_matchesTalk(terms, talk) &&
              (length == null ||
                  (talk.durationMs > 0 &&
                      length.matches(Duration(milliseconds: talk.durationMs)))))
            _talkItem(talk),
      ],
    );
  }

  @override
  Future<CatalogueTeacherPage> teacherPage(String id, {int talkPage = 30}) =>
      Future.error(CatalogueEntryUnavailable('teacher', id));

  @override
  Future<List<PackItemsModel>> teacherTalks(
    String id, {
    required int offset,
    int limit = 30,
  }) async => const [];

  // ---------------------------------------------------------------- mapping

  static bool _matches(List<String> terms, String text) {
    final words = haTerms(text);
    return terms.every((t) => words.any((w) => w.startsWith(t)));
  }

  static bool _matchesTalk(List<String> terms, HaTalk talk) =>
      _matches(terms, '${talk.title} ${talk.event} ${talk.tags.join(' ')}');

  static String _creator(HaTalk talk) =>
      talk.author.isEmpty ? haDefaultCreator : talk.author;

  PackModel _packOf(HaEvent event) => PackModel(
    id: event.id,
    title: event.name,
    subtitle: _courseSubtitle(event),
    coverUrl: '',
    path: '/packs/${event.id}',
    description: '',
    isPublished: true,
    items: [for (final talk in event.talks) _talkItem(talk)],
    // The retreat has no page of its own; the listing is where it is found.
    attribution: haAttribution(url: haListingUrl),
  );

  PackItemsModel _courseItem(HaEvent event) => PackItemsModel(
    type: TypeConstants.pack,
    id: event.id,
    title: event.name,
    subtitle: _courseSubtitle(event),
    coverUrl: '',
    path: '/packs/${event.id}',
  );

  static PackItemsModel _talkItem(HaTalk talk) => PackItemsModel(
    type: TypeConstants.track,
    id: talk.id,
    title: talk.title,
    subtitle: _talkSubtitle(talk),
    coverUrl: '',
    path: '/tracks/${talk.id}',
    kind: _kindLabel(talk),
    teacher: _creator(talk),
    durationMs: talk.durationMs > 0 ? talk.durationMs : null,
    date: talk.date.length >= 10 ? talk.date : null,
  );

  static String _kindLabel(HaTalk talk) => talk.practice ? 'Practice' : 'Talk';

  /// "Talk · Rob Burbea · 56 min"
  static String _talkSubtitle(HaTalk talk) {
    final minutes = (talk.durationMs / Duration.millisecondsPerMinute).round();
    return [
      _kindLabel(talk),
      _creator(talk),
      if (minutes > 0) '$minutes min',
    ].join(' · ');
  }

  /// "Rob Burbea · 4 talks"
  static String _courseSubtitle(HaEvent event) {
    final count = event.talks.length;
    return '$haDefaultCreator · $count ${count == 1 ? 'talk' : 'talks'}';
  }

  static SourceAttribution _attributionOf(HaTalk talk) =>
      haAttribution(url: talk.pageUrl, creator: talk.author);

  /// One voice, one file: the audio the site's own talk page plays.
  static Track mapTalk(HaTalk talk) => Track(
    id: talk.id,
    title: talk.title,
    subtitle: _talkSubtitle(talk),
    description: '',
    coverUrl: '',
    isPublished: true,
    // Ambient sound suits sitting with a practice, not a talk.
    hasBackgroundSound: talk.practice,
    artist: TrackArtist(name: _creator(talk), path: talk.pageUrl),
    attribution: _attributionOf(talk),
    voices: [
      TrackVoice(
        guideName: _creator(talk),
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
