import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';

import '../../helpers/library_fixtures.dart';

/// Deleting an import tells the personal courses listing it, with no course
/// page opened in between.
void main() {
  test(
    'a deleted import leaves the courses that list it unavailable',
    () async {
      final h = LibraryHarness.create();
      addTearDown(h.dispose);
      final single = await h.service.add(
        await h.service.resolve(h.writeAudio('Metta Practice.mp3').path),
        const ImportChoice(
          kind: LibraryKind.single,
          group: LibraryGroup.practice,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          libraryDatabaseProvider.overrideWithValue(h.db),
          libraryStoreProvider.overrideWithValue(h.store),
          libSourceProvider.overrideWithValue(h.lib),
          contentSourcesProvider.overrideWith((ref) => [h.lib]),
        ],
      );
      addTearDown(container.dispose);
      final mine = container.read(myCourseSourceProvider);
      final id = await mine.create(
        title: 'Mine',
        lines: [
          MyCourseLine.session(
            MyItemDraft(id: single.entryId, title: 'Metta Practice'),
          ),
        ],
      );
      expect((await mine.packTrackIds())[id], [single.entryId]);

      await h.lib.remove(single.entryId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect((await mine.packTrackIds())[id], isEmpty);
    },
  );
}
