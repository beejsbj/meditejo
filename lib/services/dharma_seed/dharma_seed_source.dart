import 'dart:async';

import 'package:medito/constants/types/type_constants.dart';
import 'package:medito/models/attribution/source_attribution.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart'
    show DsKind;
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';

/// Dharma Seed as a [ContentSource]: a retreat is a course (pack) whose
/// sessions are its talks in recording order; a talk is a single (track).
///
/// What the user keeps lives in the [library] (courses, talks and teachers
/// alike); this source only knows how to describe a Dharma Seed item for it.
///
/// Reads come from the on-device database. Opening a retreat or talk that
/// has not synced yet asks [sync] to fetch it first, bounded by
/// [fetchTimeout]; offline, it shows what is stored.
class DharmaSeedSource
    implements ContentSource, SavableContentSource, ParentedContentSource {
  DharmaSeedSource({
    required this.db,
    this.sync,
    this.library,
    this.browseLimit = 40,
    this.fetchTimeout = const Duration(seconds: 20),
  });

  final DharmaSeedDatabase db;
  final DharmaSeedSync? sync;

  /// The user's library, where saves go. Null in tests that only read.
  final LibraryStore? library;
  final int browseLimit;
  final Duration fetchTimeout;

  @override
  String get prefix => dharmaSeedPrefix;

  @override
  Future<List<PackModel>> browsePacks() => _quietly('browse', () async {
    final saved = await db.retreatsById(await _savedIds(DsSavedKind.retreat));
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
    final teachers = await db.teachersById(
      talks.map((t) => t.teacherId).nonNulls,
    );
    final leads = await db.leadTeacherOfRetreats([retreatId]);
    return mapRetreat(retreat, [
      for (final talk in talks)
        DsTalkWithTeacher(talk, teachers[talk.teacherId]),
    ], teachers[leads[retreatId]]);
  }

  @override
  Future<Track> track(String id) async {
    final talkId = parseDsTalkId(id);
    if (talkId == null) throw CatalogueEntryUnavailable('track', id);
    var talk = await db.talkById(talkId);
    if (talk == null) {
      final asked = await _fetch(() => sync?.ensureTalk(talkId));
      talk = await db.talkById(talkId);
      if (talk == null && !asked) throw CatalogueEntryUnreachable('track', id);
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
    final ids = {...await _savedIds(DsSavedKind.retreat), ...started};
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

  // ----------------------------------------------------------- saving

  @override
  bool canSave(String id) =>
      parseDsRetreatId(id) != null ||
      parseDsTeacherId(id) != null ||
      parseDsTalkId(id) != null;

  @override
  Future<bool> isSaved(String id) async =>
      canSave(id) && await library?.contains(id) == true;

  /// "Saving" is adding to the library: a course, a talk or a teacher.
  @override
  Future<void> setSaved(String id, {required bool saved}) async {
    final store = library;
    if (store == null || !canSave(id)) return;
    if (!saved) return store.remove(id);
    final draft = await libraryDraft(id);
    if (draft != null) await store.add(draft);
  }

  /// IDs of this kind in the library, most recently added first.
  Future<List<int>> _savedIds(DsSavedKind kind) async {
    final entries = await library?.entries() ?? const <LibraryEntry>[];
    final parse = switch (kind) {
      DsSavedKind.retreat => parseDsRetreatId,
      DsSavedKind.teacher => parseDsTeacherId,
    };
    return [for (final entry in entries) ?parse(entry.sourceId)];
  }

  /// How the library describes a Dharma Seed course, talk or teacher: its
  /// title, artwork, size and whether it is practice or talks. A course or
  /// talk not stored yet is fetched first (the same on-demand fetch as
  /// opening it). Null when Dharma Seed does not have it.
  Future<LibraryDraft?> libraryDraft(String id) async {
    if (parseDsRetreatId(id) case final retreatId?) {
      await _fetch(() => sync?.ensureRetreatTalks(retreatId));
      final retreat = await db.retreatById(retreatId);
      if (retreat == null) return null;
      final talks = await db.talksOfRetreat(retreatId);
      final lead = (await db.leadTeacherOfRetreats([retreatId]))[retreatId];
      final leadTeacher = lead == null ? null : await db.teacherById(lead);
      // A retreat is practice whatever Dharma Seed labels its recordings:
      // most of Rob Burbea's guided retreat sittings are filed as "Talk".
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.course,
        title: retreat.name,
        group: LibraryGroup.practice,
        subtitle: retreatSubtitle(retreat, leadTeacher),
        coverUrl: teacherPhoto(leadTeacher),
        itemCount: talks.isEmpty
            ? DharmaSeedDatabase.talkIdsOf(retreat).length
            : talks.length,
        durationMs: talks.fold(0, (sum, t) => sum + t.durationMs),
      );
    }
    if (parseDsTalkId(id) case final talkId?) {
      var talk = await db.talkById(talkId);
      if (talk == null) {
        await _fetch(() => sync?.ensureTalk(talkId));
        talk = await db.talkById(talkId);
      }
      if (talk == null) return null;
      final teacher = talk.teacherId == null
          ? null
          : await db.teacherById(talk.teacherId!);
      final hit = DsTalkWithTeacher(talk, teacher);
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.single,
        title: talk.title,
        group: DharmaSeedKind.fromRecordingType(talk.recordingType).isPractice
            ? LibraryGroup.practice
            : LibraryGroup.talks,
        subtitle: talkSubtitle(hit),
        coverUrl: teacherPhoto(teacher),
        durationMs: talk.durationMs,
      );
    }
    if (parseDsTeacherId(id) case final teacherId?) {
      await _fetch(() => sync?.ensureTeacher(teacherId));
      final teacher = await db.teacherById(teacherId);
      if (teacher == null) return null;
      final count = (await db.talkCounts([teacherId]))[teacherId] ?? 0;
      return LibraryDraft(
        sourceId: id,
        kind: LibraryKind.teacher,
        title: teacher.name,
        subtitle: count == 0 ? '' : '$count ${count == 1 ? 'talk' : 'talks'}',
        coverUrl: teacherPhoto(teacher),
        itemCount: count,
      );
    }
    return null;
  }

  /// Fetches one teacher ahead of the background queue, for an import.
  Future<void> ensureTeacher(int teacherId) =>
      _fetch(() => sync?.ensureTeacher(teacherId));

  @override
  Future<String?> parentOf(String trackId) async {
    final talkId = parseDsTalkId(trackId);
    if (talkId == null) return null;
    final retreat = (await db.talkById(talkId))?.retreatId;
    return retreat == null || retreat == 0 ? null : dsRetreatId(retreat);
  }

  // ------------------------------------------------- Dharma Seed screens
  //
  // Teachers, content groups and the length filter are Dharma Seed features
  // for now. They stay out of [ContentSource] until a second source shows
  // what is really shared.

  /// Explore for one content group, or both when [group] is null: saved
  /// courses and teachers first (unfiltered view only), then the newest
  /// courses of that group, the busiest teachers, and, with a group chosen,
  /// the latest single sessions.
  Future<DsExplore> explore({DsContentGroup? group}) =>
      _quietly('explore', () async {
        // Courses in the library are shown by the Explore screen itself, so
        // they stay visible under any chip; here they are only left out of
        // the browse list to avoid showing them twice.
        final savedIds = {...await _savedIds(DsSavedKind.retreat)};
        final recent = await db.recentRetreatsOf(group, limit: browseLimit);
        final courses = [
          for (final r in recent)
            if (!savedIds.contains(r.id)) r,
        ];
        final leads = await db.leadTeacherOfRetreats([
          ...courses.map((r) => r.id),
        ]);
        final leadTeachers = await db.teachersById(leads.values);
        PackItemsModel course(DsRetreat r) =>
            retreatItem(r, leadTeachers[leads[r.id]]);

        final savedTeacherIds = await _savedIds(DsSavedKind.teacher);
        final savedTeachers =
            (await db.teachersById(savedTeacherIds)).values.toList()..sort(
              (a, b) => savedTeacherIds
                  .indexOf(a.id)
                  .compareTo(savedTeacherIds.indexOf(b.id)),
            );
        final top = await db.topTeachers(group: group, limit: 20);
        final savedSet = {for (final t in savedTeachers) t.id};

        final talks = group == null
            ? const <DsTalkWithTeacher>[]
            : await db.recentTalks(filter: DsTalkFilter(group: group));

        return DsExplore(
          courses: [for (final r in courses) course(r)],
          savedTeachers: [for (final t in savedTeachers) teacherItem(t)],
          teachers: [
            for (final summary in top)
              if (!savedSet.contains(summary.teacher.id))
                teacherItem(summary.teacher, talkCount: summary.talkCount),
          ],
          talks: [for (final t in talks) talkItem(t)],
          // A chip classifies courses by their stored talks, so before any
          // talk has synced it has nothing to show yet: that is "still
          // syncing", not "nothing here".
          hasCatalogue:
              await db.countOf(DsKind.retreats) > 0 &&
              (group == null || await db.countOf(DsKind.talks) > 0),
        );
      }, orElse: const DsExplore());

  /// Search over the local index, grouped: teachers lead (a talk quoting a
  /// teacher outranks the teacher's own talks otherwise), then courses, then
  /// talks, which alone honour [length].
  Future<DsSearchResults> search(
    String query, {
    SessionLength? length,
  }) => _quietly('search', () async {
    final teachers = await db.searchTeachers(query, limit: 8);
    final retreats = await db.searchRetreats(query, limit: 12);
    final talks = await db.searchTalks(
      query,
      filter: DsTalkFilter(minDuration: length?.min, maxDuration: length?.max),
    );
    final counts = await db.talkCounts(teachers.map((t) => t.id));
    final leads = await db.leadTeacherOfRetreats(retreats.map((r) => r.id));
    final leadTeachers = await db.teachersById(leads.values);
    return DsSearchResults(
      teachers: [
        for (final t in teachers) teacherItem(t, talkCount: counts[t.id] ?? 0),
      ],
      courses: [
        for (final r in retreats) retreatItem(r, leadTeachers[leads[r.id]]),
      ],
      talks: [for (final t in talks) talkItem(t)],
    );
  }, orElse: const DsSearchResults());

  /// A teacher's page, or [CatalogueEntryUnavailable] when they are not
  /// stored (yet).
  Future<DsTeacherPage> teacherPage(String id, {int talkPage = 30}) async {
    final teacherId = parseDsTeacherId(id);
    if (teacherId == null) throw CatalogueEntryUnavailable('teacher', id);
    final teacher = await db.teacherById(teacherId);
    if (teacher == null) throw CatalogueEntryUnavailable('teacher', id);
    final counts = await db.talkCounts([teacherId]);
    final retreats = await db.retreatsOfTeacher(teacherId);
    final leads = await db.leadTeacherOfRetreats(retreats.map((r) => r.id));
    final leadTeachers = await db.teachersById(leads.values);
    final talks = await db.talksOfTeacher(teacherId, limit: talkPage + 1);
    final talkCount = counts[teacherId] ?? 0;
    return DsTeacherPage(
      teacher: teacherItem(
        teacher,
        talkCount: talkCount,
        retreatCount: retreats.length,
      ),
      courses: [
        for (final r in retreats) retreatItem(r, leadTeachers[leads[r.id]]),
      ],
      talks: [for (final t in talks.take(talkPage)) talkItem(t)],
      hasMoreTalks: talks.length > talkPage,
    );
  }

  /// More of a teacher's talks, after the [offset] already shown.
  Future<List<PackItemsModel>> teacherTalks(
    String id, {
    required int offset,
    int limit = 30,
  }) => _quietly('teacherTalks', () async {
    final teacherId = parseDsTeacherId(id);
    if (teacherId == null) return const [];
    final talks = await db.talksOfTeacher(
      teacherId,
      limit: limit,
      offset: offset,
    );
    return [for (final t in talks) talkItem(t)];
  }, orElse: const []);

  /// Waits for an on-demand fetch, but never fails the read because of it.
  /// False when the fetch failed, so the source was not heard from.
  Future<bool> _fetch(Future<Object?>? Function() fetch) async {
    try {
      await fetch()?.timeout(fetchTimeout);
      return true;
    } catch (e) {
      AppLogger.w('DHARMA_SEED', 'Using stored data: $e');
      return false;
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
      items: [for (final talk in talks) talkItem(talk)],
      teacher: lead == null
          ? null
          : PackTeacher(
              id: dsTeacherId(lead.id),
              name: lead.name,
              bio: lead.bio,
              photoUrl: teacherPhoto(lead),
              pageUrl: dsTeacherPageUrl(lead.id),
            ),
      attribution: _attribution(
        url: dsRetreatPageUrl(retreat.id),
        creator: lead?.name,
      ),
    );
  }

  static SourceAttribution _attribution({
    required String url,
    String? creator,
  }) => SourceAttribution(
    source: 'Dharma Seed',
    creator: creator,
    url: url,
    licenseName: dharmaSeedLicenceName,
    licenseUrl: dharmaSeedLicenceUrl,
  );

  /// One session row: the details a course or talk list shows.
  static PackItemsModel talkItem(DsTalkWithTeacher hit) {
    final talk = hit.talk;
    return PackItemsModel(
      type: TypeConstants.track,
      id: dsTalkId(talk.id),
      title: talk.title,
      subtitle: talkSubtitle(hit),
      coverUrl: teacherPhoto(hit.teacher),
      path: '/tracks/${dsTalkId(talk.id)}',
      kind: DharmaSeedKind.fromRecordingType(talk.recordingType).label,
      teacher: hit.teacher?.name,
      durationMs: talk.durationMs,
      date: talk.recDate.length >= 10 ? talk.recDate.substring(0, 10) : null,
    );
  }

  static DsTeacherItem teacherItem(
    DsTeacher teacher, {
    int talkCount = 0,
    int retreatCount = 0,
  }) => DsTeacherItem(
    id: dsTeacherId(teacher.id),
    name: teacher.name,
    photoUrl: teacherPhoto(teacher),
    bio: teacher.bio,
    website: teacher.website,
    pageUrl: dsTeacherPageUrl(teacher.id),
    talkCount: talkCount,
    retreatCount: retreatCount,
  );

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
      attribution: _attribution(
        url: dsTalkPageUrl(talk.id),
        creator: teacher?.name,
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
