import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/library/session_origin.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/dharma_seed_catalogue.dart';
import '../../helpers/dharma_seed_fake_api.dart';
import '../../helpers/library_fixtures.dart';

PlaybackRequest _request(String trackId) => PlaybackRequest(
  trackId: trackId,
  fileId: trackId,
  title: 'Talk',
  description: '',
  coverUrl: '',
  remoteUrl: 'https://a.test/$trackId',
  duration: 600000,
  hasBackgroundSound: true,
);

/// Dharma Seed's catch-all retreat 1 "Unknown" is no talk's default course
/// (#84), but a talk opened from that course's page still follows it: its
/// cues, autoplay and place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DharmaSeedDatabase dsDb;
  late LibraryDatabase db;
  late LibraryStore store;
  late ProviderContainer container;
  const unknown = 'ds-retreat-$dsUnknownRetreat';
  const talk = 'ds-talk-10';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dsDb = memoryDharmaSeedDb();
    await dsDb.upsertRetreatRecords({
      dsUnknownRetreat: {
        'name': 'Unknown',
        'talks': [10],
      },
    });
    await dsDb.upsertTalkRecords({
      10: dsTalkRecord('A talk at no retreat', teacher: 1, retreat: 1),
    });
    db = memoryLibraryDb();
    store = LibraryStore(db);
    final source = DharmaSeedSource(db: dsDb, library: store);
    container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(store),
        contentSourcesProvider.overrideWithValue([source]),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    store.dispose();
    await db.close();
    await dsDb.close();
  });

  Future<CueScope> scopeOf(String trackId) =>
      container.read(cueScopeForRequestProvider(_request(trackId)).future);

  test(
    'opened from the Unknown course\'s page, it follows that course',
    () async {
      await noteSessionOrigin(store, talk, unknown);
      final scope = await scopeOf(talk);
      expect(scope.courseId, unknown);

      // The course's own cues apply.
      final cues = CueSettingsStore(await SharedPreferences.getInstance());
      await cues.save(
        CueScope(scope.kind, courseId: unknown),
        const CueSettings(extendMinutes: 20),
      );
      expect(cues.read(scope).extendMinutes, 20);
    },
  );

  test('opened anywhere else, it is in no course', () async {
    await noteSessionOrigin(store, talk, null);
    await Future<void>.delayed(Duration.zero);
    expect((await scopeOf(talk)).courseId, isNull);
  });
}
