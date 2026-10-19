import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/starter_set.dart';
import 'package:medito/utils/logger.dart';
import 'package:drift/drift.dart' show Value;

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

/// Puts the [starterSet] in the library on the first run, once.
///
/// "First run" means no `starter_seeded` flag and an empty library. A library
/// that already holds things (an install from before the starter set, or a
/// carried-over save) is left alone, and either way the flag is set, so
/// anything the user later removes stays removed.
///
/// Items are described from the on-device catalogue, with no network. One the
/// catalogue lacks is added under the title in the data file, which the course
/// page replaces with the real one when it first opens.
Future<void> seedStarterSet(
  LibraryDatabase library,
  DharmaSeedDatabase dharmaSeed, {
  List<StarterItem> items = starterSet,
  DateTime Function()? clock,
}) async {
  if (await library.metaValue(_starterSeededKey) != null) return;
  try {
    if ((await library.allEntries()).isEmpty) {
      final now = (clock ?? DateTime.now)();
      final describe = DharmaSeedSource(db: dharmaSeed);
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        final draft = item.id.startsWith(dharmaSeedPrefix)
            ? await describe.libraryDraft(item.id)
            : null;
        await library.insertEntry(
          LibraryEntriesCompanion.insert(
            sourceId: item.id,
            kind: item.kind.name,
            detectedGroup: Value(
              (item.group ?? draft?.group ?? LibraryGroup.practice).name,
            ),
            title: draft?.title ?? item.title,
            subtitle: Value(draft?.subtitle ?? ''),
            coverUrl: Value(draft?.coverUrl ?? ''),
            itemCount: Value(draft?.itemCount ?? item.itemCount),
            durationMs: Value(draft?.durationMs ?? 0),
            // The first item leads the library; a second apart keeps the
            // order stable, since lists sort by time.
            addedAt: now.subtract(Duration(seconds: i)),
          ),
        );
      }
    }
    await library.setMeta(_starterSeededKey, DateTime.now().toIso8601String());
  } catch (e, st) {
    // Try again next launch rather than mark a half-done seed finished.
    AppLogger.e('LIBRARY', 'Could not add the starter set', e, st);
  }
}
