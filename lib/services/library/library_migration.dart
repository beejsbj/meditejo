import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
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
          title: draft?.title ?? (isTeacher ? 'Dharma Seed teacher ${saved.itemId}' : 'Dharma Seed course ${saved.itemId}'),
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
