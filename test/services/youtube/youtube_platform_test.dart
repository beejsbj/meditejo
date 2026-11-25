import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_migration.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/youtube/youtube_platform.dart';

import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

void main() {
  test('host bridge is available only on Android', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final platform in TargetPlatform.values) {
      debugDefaultTargetPlatformOverride = platform;
      expect(youtubeBridgeAvailable, platform == TargetPlatform.android);
    }
  });

  test(
    'without a bridge no source is constructed or starters seeded',
    () async {
      final db = memoryLibraryDb();
      final ds = memoryDharmaSeedDb();
      final store = LibraryStore(db);
      final container = ProviderContainer(
        overrides: [
          youtubeAvailableProvider.overrideWithValue(false),
          youtubeSourceProvider.overrideWith(
            (_) => throw StateError('No host'),
          ),
          dharmaSeedSourceProvider.overrideWithValue(DharmaSeedSource(db: ds)),
          libSourceProvider.overrideWithValue(
            LibSource(db: db, library: store),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        store.dispose();
        await db.close();
        await ds.close();
      });
      expect(container.read(contentSourcesProvider).map((s) => s.prefix), [
        'ds-',
        'dt-',
        'lib-',
        // Personal courses: present on every platform, no YouTube needed.
        'my-',
      ]);
      await seedStarterSet(db, ds, includeYoutube: false);
      final entries = await db.allEntries();
      expect(entries, hasLength(5));
      expect(entries.any((e) => e.sourceId.startsWith('yt-')), isFalse);
      expect(await db.youtubeCourses(), isEmpty);
    },
  );
}
