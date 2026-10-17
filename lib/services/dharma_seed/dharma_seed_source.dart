import 'dart:async';

import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';

/// Dharma Seed as a [ContentSource]: a retreat is a course (pack) whose
/// sessions are its talks in recording order; a talk is a single (track).
///
/// Reads come from the on-device database. Opening a retreat or talk that
/// has not synced yet asks [sync] to fetch it first, bounded by
/// [fetchTimeout]; offline, it shows what is stored.
class DharmaSeedSource implements ContentSource {
  DharmaSeedSource({
    required this.db,
    this.sync,
    this.browseLimit = 40,
    this.fetchTimeout = const Duration(seconds: 20),
  });

  final DharmaSeedDatabase db;
  final DharmaSeedSync? sync;
  final int browseLimit;
  final Duration fetchTimeout;

  @override
  String get prefix => dharmaSeedPrefix;

  @override
  Future<List<PackModel>> browsePacks() => _quietly('browse', () async {
    final saved = await db.retreatsById(
      await db.savedIds(DsSavedKind.retreat),
    );
    final savedIds = {for (final r in saved) r.id};
    final recent = await db.recentRetreats(limit: browseLimit);
    final retreats = [
      ...saved,
      ...recent.where((r) => !savedIds.contains(r.id)),
    ];
    final leads = await db.leadTeacherOfRetreats(retreats.map((r) => r.id));
    final teachers = await db.teachersById(leads.values);
    return [
      for (final retreat in retreats)
        mapRetreat(retreat, const [], teachers[leads[retreat.id]]),
    ];
  }, orElse: const []);

  @override
  Future<PackModel> pack(String id) async {
    final retreatId = parseDsRetreatId(id);
    if (retreatId == null) throw CatalogueEntryUnavailable('pack', id);
    await _fetch(() => sync?.ensureRetreatTalks(retreatId));
    final retreat = await db.retreatById(retreatId);
    if (retreat == null) throw CatalogueEntryUnavailable('pack', id);
    final talks = await db.talksOfRetreat(retreatId);
    final teachers = await db.teachersById(talks.map((t) => t.teacherId).nonNulls);
    final leads = await db.leadTeacherOfRetreats([retreatId]);
    return mapRetreat(
      retreat,
      [for (final talk in talks) DsTalkWithTeacher(talk, teachers[talk.teacherId])],
      teachers[leads[retreatId]],
    );
  }

  @override
  Future<Track> track(String id) async {
    final talkId = parseDsTalkId(id);
    if (talkId == null) throw CatalogueEntryUnavailable('track', id);
    var talk = await db.talkById(talkId);
    if (talk == null) {
      await _fetch(() => sync?.ensureTalk(talkId));
      talk = await db.talkById(talkId);
    }
    if (talk == null) throw CatalogueEntryUnavailable('track', id);
    final teacher = talk.teacherId == null
        ? null
        : await db.teacherById(talk.teacherId!);
    return mapTalk(DsTalkWithTeacher(talk, teacher));
  }

  /// Saved retreats plus retreats containing a started talk. Never every
  /// retreat: completion ticks only matter for courses the user has touched.
  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) => _quietly('packTrackIds', () async {
    final started = await db.retreatIdsOfTalks(
      startedTrackIds.map(parseDsTalkId).nonNulls,
    );
    final ids = {...await db.savedIds(DsSavedKind.retreat), ...started};
    return {
      for (final retreat in await db.retreatsById(ids))
        dsRetreatId(retreat.id): [
          for (final talkId in await db.liveTalkIdsOf(retreat))
            dsTalkId(talkId),
        ],
    };
  }, orElse: const {});

  @override
  Future<List<PackItemsModel>> searchPacks(String query) =>
      _quietly('searchPacks', () async {
        final retreats = await db.searchRetreats(query);
        final leads = await db.leadTeacherOfRetreats(retreats.map((r) => r.id));
        final teachers = await db.teachersById(leads.values);
        return [
          for (final retreat in retreats)
            retreatItem(retreat, teachers[leads[retreat.id]]),
        ];
      }, orElse: const []);

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) =>
      _quietly('searchTracks', () async {
        return [
          for (final hit in await db.searchTalks(query))
            TrackSearchModel(
              id: dsTalkId(hit.talk.id),
              title: hit.talk.title,
              subtitle: talkSubtitle(hit),
              description: hit.talk.description,
              coverUrl: teacherPhoto(hit.teacher),
              path: '/tracks/${dsTalkId(hit.talk.id)}',
            ),
        ];
      }, orElse: const []);

  /// Waits for an on-demand fetch, but never fails the read because of it.
  Future<void> _fetch(Future<Object?>? Function() fetch) async {
    try {
      await fetch()?.timeout(fetchTimeout);
    } catch (e) {
      AppLogger.w('DHARMA_SEED', 'Using stored data: $e');
    }
  }

  /// Browsing and search degrade to empty rather than break the screen
  /// they share with other sources.
  Future<T> _quietly<T>(
    String what,
    Future<T> Function() read, {
    required T orElse,
  }) async {
    try {
      return await read();
    } catch (e, st) {
      AppLogger.e('DHARMA_SEED', '$what failed', e, st);
      return orElse;
    }
  }

  // ---------------------------------------------------------------- mapping

  static PackModel mapRetreat(
    DsRetreat retreat,
    List<DsTalkWithTeacher> talks,
    DsTeacher? lead,
  ) {
    return PackModel(
      id: dsRetreatId(retreat.id),
      title: retreat.name,
      subtitle: retreatSubtitle(retreat, lead),
      coverUrl: teacherPhoto(lead),
      path: '/packs/${dsRetreatId(retreat.id)}',
      description: retreat.description,
      isPublished: true,
      items: [
        for (final talk in talks)
          PackItemsModel(
            type: TypeConstants.track,
            id: dsTalkId(talk.talk.id),
            title: talk.talk.title,
            subtitle: talkSubtitle(talk),
            coverUrl: teacherPhoto(talk.teacher),
            path: '/tracks/${dsTalkId(talk.talk.id)}',
          ),
      ],
    );
  }

  static PackItemsModel retreatItem(DsRetreat retreat, DsTeacher? lead) =>
      PackItemsModel(
        type: TypeConstants.pack,
        id: dsRetreatId(retreat.id),
        title: retreat.name,
        subtitle: retreatSubtitle(retreat, lead),
        coverUrl: teacherPhoto(lead),
        path: '/packs/${dsRetreatId(retreat.id)}',
      );

  /// One voice, one file: the original Dharma Seed audio, unmodified.
  static Track mapTalk(DsTalkWithTeacher hit) {
    final talk = hit.talk;
    final teacher = hit.teacher;
    final kind = DharmaSeedKind.fromRecordingType(talk.recordingType);
    return Track(
      id: dsTalkId(talk.id),
      title: talk.title,
      subtitle: talkSubtitle(hit),
      description: talk.description,
      coverUrl: teacherPhoto(teacher),
      isPublished: true,
      // Ambient sound suits sitting with a guided practice, not a talk.
      hasBackgroundSound: kind.isPractice,
      // The player links the artist line; point it at the talk's own page
      // so attribution is one tap away.
      artist: TrackArtist(
        name: teacher?.name ?? 'Dharma Seed',
        path: dsTalkPageUrl(talk.id),
      ),
      voices: [
        TrackVoice(
          guideName: teacher?.name,
          audioFiles: [
            TrackAudioFile(
              id: dsTalkId(talk.id),
              path: dsAudioUrl(talk.audioUrl),
              duration: talk.durationMs,
            ),
          ],
        ),
      ],
    );
  }

  /// "Guided meditation · Rob Burbea · 42 min"
  static String talkSubtitle(DsTalkWithTeacher hit) {
    final kind = DharmaSeedKind.fromRecordingType(hit.talk.recordingType);
    final minutes = (hit.talk.durationMs / Duration.millisecondsPerMinute)
        .round();
    return [
      kind.label,
      if (hit.teacher != null) hit.teacher!.name,
      if (minutes > 0) '$minutes min',
    ].join(' · ');
  }

  /// "Rob Burbea · 2014 · 38 talks"
  static String retreatSubtitle(DsRetreat retreat, DsTeacher? lead) {
    final count = DharmaSeedDatabase.talkIdsOf(retreat).length;
    final year = retreat.startDate.length >= 4
        ? retreat.startDate.substring(0, 4)
        : '';
    return [
      if (lead != null) lead.name,
      if (year.isNotEmpty) year,
      '$count ${count == 1 ? 'talk' : 'talks'}',
    ].join(' · ');
  }

  static String teacherPhoto(DsTeacher? teacher) =>
      teacher == null ? '' : dsTeacherPhotoUrl(teacher.id, teacher.photo);
}
