import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/starter_set.dart';
import 'package:medito/utils/logger.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

const _migratedKey = 'ds_saves_migrated';

/// Carries "Save course" and "Save teacher" from before the library existed
/// (the `ds_saved` table in the Dharma Seed database) into the library, once.
///
/// The old rows stay where they are: nothing is deleted, and a marker in the
/// library says it has been done. An item the catalogue no longer holds still
/// comes across, under a plain title, so a save is never silently dropped.
Future<void> migrateDharmaSeedSaves(
  LibraryDatabase library,
  DharmaSeedDatabase dharmaSeed,
) async {
  if (await library.metaValue(_migratedKey) != null) return;
  try {
    final describe = DharmaSeedSource(db: dharmaSeed);
    for (final saved in await dharmaSeed.savedItems()) {
      final isTeacher = saved.kind == DsSavedKind.teacher.name;
      final id = isTeacher
          ? dsTeacherId(saved.itemId)
          : dsRetreatId(saved.itemId);
      if (await library.entryById(id) != null) continue;
      final draft = await describe.libraryDraft(id);
      await library.insertEntry(
        LibraryEntriesCompanion.insert(
          sourceId: id,
          kind: (isTeacher ? LibraryKind.teacher : LibraryKind.course).name,
          detectedGroup: Value((draft?.group ?? LibraryGroup.practice).name),
          title:
              draft?.title ??
              (isTeacher
                  ? 'Dharma Seed teacher ${saved.itemId}'
                  : 'Dharma Seed course ${saved.itemId}'),
          subtitle: Value(draft?.subtitle ?? ''),
          coverUrl: Value(draft?.coverUrl ?? ''),
          itemCount: Value(draft?.itemCount ?? 1),
          durationMs: Value(draft?.durationMs ?? 0),
          addedAt: saved.savedAt,
        ),
      );
    }
    await library.setMeta(_migratedKey, DateTime.now().toIso8601String());
  } catch (e, st) {
    // Try again next launch rather than mark a half-done migration finished.
    AppLogger.e('LIBRARY', 'Could not carry over Dharma Seed saves', e, st);
  }
}

const _groupDefaultsKey = 'group_defaults_v2';

/// One time: files Dharma Seed retreats under Practice. Until then an import
/// took the label of the retreat's recordings, and Dharma Seed calls most
/// guided retreat sittings "Talk", so retreats landed under Talks.
///
/// Only the detected group moves. A retreat the user classified themselves
/// keeps their choice (`group_override`), and so does everything else.
Future<void> reclassifyLibraryDefaults(LibraryDatabase library) async {
  if (await library.metaValue(_groupDefaultsKey) != null) return;
  try {
    await library.customStatement(
      'UPDATE library_entries SET detected_group = ? '
      "WHERE source_id LIKE 'ds-retreat-%' AND group_override IS NULL",
      [LibraryGroup.practice.name],
    );
    await library.setMeta(_groupDefaultsKey, DateTime.now().toIso8601String());
  } catch (e, st) {
    AppLogger.e('LIBRARY', 'Could not reclassify library defaults', e, st);
  }
}

const _starterSeededKey = 'starter_seeded';
const _starterVersionKey = 'starter_version';

/// Puts the [starterSet] in the library on the first run, once.
///
/// "First run" means no `starter_seeded` flag and an empty library. A library
/// that already holds things (an install from before the starter set, or a
/// carried-over save) is left alone, and either way the flag is set, so
/// anything the user later removes stays removed. A seeded library is also
/// marked as holding [starterSetVersion], so [addNewStarterItems] has
/// nothing to add to it.
///
/// Items are described from the on-device catalogue, with no network. One the
/// catalogue lacks is added under the title in the data file, which the course
/// page replaces with the real one when it first opens.
Future<void> seedStarterSet(
  LibraryDatabase library,
  DharmaSeedDatabase dharmaSeed, {
  List<StarterItem> items = starterSet,
  bool includeYoutube = true,
  int version = starterSetVersion,
  DateTime Function()? clock,
}) async {
  if (await library.metaValue(_starterSeededKey) != null) return;
  try {
    final drafts = <LibraryEntriesCompanion>[];
    final seeded = <StarterItem>[];
    if ((await library.allEntries()).isEmpty) {
      final now = (clock ?? DateTime.now)();
      final describe = DharmaSeedSource(db: dharmaSeed);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (!includeYoutube && item.id.startsWith('yt-')) continue;
        // The first item leads the library; a second apart keeps the
        // order stable, since lists sort by time.
        drafts.add(
          await _starterDraft(
            item,
            describe,
            now.subtract(Duration(seconds: i)),
          ),
        );
        seeded.add(item);
      }
    }
    // The entries and the flag go in together, so an interruption leaves
    // either nothing (seeded in full next launch) or everything (never again,
    // whatever the user then removes).
    await library.transaction(() async {
      if (drafts.isNotEmpty && (await library.allEntries()).isEmpty) {
        for (final draft in drafts) {
          await library.insertEntry(draft);
        }
        for (final item in seeded) {
          await _seedYoutubeRow(library, item);
        }
        await library.setMeta(_starterVersionKey, '$version');
      }
      await library.setMeta(
        _starterSeededKey,
        DateTime.now().toIso8601String(),
      );
    });
  } catch (e, st) {
    // Try again next launch rather than mark a half-done seed finished.
    AppLogger.e('LIBRARY', 'Could not add the starter set', e, st);
  }
}

/// Adds, once, the starter items that joined the set after this install was
/// seeded (their `since` is above the version it holds), so an update brings
/// them as a fresh install would. Runs after [seedStarterSet].
///
/// An install with no recorded version holds version 1: it was seeded with
/// the first set, or it predates the starter set and was left alone. An item
/// already in the library is not added again, and the new version is
/// recorded either way, so anything the user then removes stays removed.
/// New items lead the library, in the set's order. Without YouTube (iOS) its
/// items are skipped, as the first seed skips them.
Future<void> addNewStarterItems(
  LibraryDatabase library,
  DharmaSeedDatabase dharmaSeed, {
  List<StarterItem> items = starterSet,
  bool includeYoutube = true,
  int version = starterSetVersion,
  DateTime Function()? clock,
}) async {
  // Only once the first seed has run (or decided to leave the library be).
  if (await library.metaValue(_starterSeededKey) == null) return;
  final held = int.tryParse(await library.metaValue(_starterVersionKey) ?? '');
  final from = held ?? 1;
  if (from >= version) return;
  try {
    final now = (clock ?? DateTime.now)();
    final describe = DharmaSeedSource(db: dharmaSeed);
    final fresh = [
      for (final item in items)
        if (item.since > from &&
            item.since <= version &&
            (includeYoutube || !item.id.startsWith('yt-')))
          item,
    ];
    final drafts = <(StarterItem, LibraryEntriesCompanion)>[];
    for (var i = 0; i < fresh.length; i++) {
      drafts.add((
        fresh[i],
        await _starterDraft(
          fresh[i],
          describe,
          now.subtract(Duration(seconds: i)),
        ),
      ));
    }
    await library.transaction(() async {
      for (final (item, draft) in drafts) {
        if (await library.entryById(item.id) != null) continue;
        await library.insertEntry(draft);
        await _seedYoutubeRow(library, item);
      }
      await library.setMeta(_starterVersionKey, '$version');
    });
  } catch (e, st) {
    // Try again next launch rather than mark a half-done addition finished.
    AppLogger.e('LIBRARY', 'Could not add the new starter items', e, st);
  }
}

/// The library row for a starter [item], described from the catalogue
/// where it can be, else from the data file.
Future<LibraryEntriesCompanion> _starterDraft(
  StarterItem item,
  DharmaSeedSource describe,
  DateTime addedAt,
) async {
  final draft = item.id.startsWith(dharmaSeedPrefix)
      ? await describe.libraryDraft(item.id)
      : null;
  return LibraryEntriesCompanion.insert(
    sourceId: item.id,
    kind: item.kind.name,
    detectedGroup: Value(
      (item.group ?? draft?.group ?? LibraryGroup.practice).name,
    ),
    title: draft?.title ?? item.title,
    subtitle: Value(draft?.subtitle ?? item.uploader),
    coverUrl: Value(draft?.coverUrl ?? ''),
    itemCount: Value(draft?.itemCount ?? item.itemCount),
    durationMs: Value(draft?.durationMs ?? 0),
    addedAt: addedAt,
  );
}

/// A YouTube course needs its playlist row to open at all, and a single its
/// video row. Seeds either as a placeholder that is already due: the first
/// open fetches the course's sessions, and the video's own details (picture,
/// length, description) are read when it is opened or in the background.
/// A row already stored (an earlier import) is kept as it is.
Future<void> _seedYoutubeRow(LibraryDatabase library, StarterItem item) async {
  if (item.id.startsWith('yt-playlist-')) {
    await library
        .into(library.youtubePlaylists)
        .insert(
          YoutubePlaylistsCompanion.insert(
            playlistId: item.id.substring('yt-playlist-'.length),
            title: item.title,
            uploader: item.uploader,
            thumbnail: '',
            videoIds: '[]',
            lastCheckedAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  } else if (item.id.startsWith('yt-video-')) {
    await library
        .into(library.youtubeVideos)
        .insert(
          YoutubeVideosCompanion.insert(
            videoId: item.id.substring('yt-video-'.length),
            title: item.title,
            uploader: item.uploader,
            thumbnail: '',
            durationSeconds: 0,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
