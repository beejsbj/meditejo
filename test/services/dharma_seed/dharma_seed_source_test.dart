import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/repositories/explore/search_repository.dart';
import 'package:medito/repositories/explore/track_search_repository.dart';
import 'package:medito/repositories/pack/packs_repository.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/services/local_catalogue.dart';

import '../../helpers/dharma_seed_fake_api.dart';

const _localTrack = Track(
  id: 'lib-session',
  title: 'Local session',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
);

class _LocalCatalogue extends LocalCatalogue {
  @override
  List<PackModel> get packs => const [PackModel(id: 'lib-course', title: 'L')];

  @override
  Track track(String id) => id == _localTrack.id ? _localTrack : super.track(id);
}

void main() {
  late DharmaSeedDatabase db;
  late FakeDharmaSeedApi api;
  late DharmaSeedSync sync;
  late DharmaSeedSource source;

  setUp(() {
    db = memoryDharmaSeedDb();
    api = FakeDharmaSeedApi();
    sync = DharmaSeedSync(db: db, client: api.client(), sleep: (_) async {});
    source = DharmaSeedSource(db: db, sync: sync);
  });
  tearDown(() => db.close());

  group('retreat → course', () {
    test('sessions are talks in recording order, fetched on open', () async {
      // Nothing synced yet: opening the retreat fetches it and its talks.
      final pack = await source.pack('ds-retreat-6689');

      expect(pack.id, 'ds-retreat-6689');
      expect(pack.title, 'Auckland Insight Meditation meetings 2026');
      expect(pack.subtitle, 'Jill Shepherd · 2026 · 7 talks');
      expect(
        pack.coverUrl,
        'https://www.dharmaseed.org/api/1/teachers/637/photo.png/?maxW=400',
      );
      expect(pack.items.map((i) => i.id), [
        'ds-talk-95073',
        'ds-talk-95232',
        'ds-talk-95421',
        'ds-talk-95545',
        'ds-talk-95800',
        'ds-talk-95953',
        'ds-talk-99944',
      ]);
      final first = pack.items.first;
      expect(first.type, 'track');
      expect(first.path, '/tracks/ds-talk-95073');
      expect(first.title, 'talk: Renewing motivation');
      expect(first.subtitle, 'Talk · Jill Shepherd · 25 min');
    });

    test('offline, a stored retreat still opens', () async {
      await sync.ensureRetreatTalks(6689);
      final offline = DharmaSeedSource(
        db: db,
        sync: DharmaSeedSync(
          db: db,
          client: DharmaSeedClient(
            httpClient: FakeDharmaSeedApi(
              fail: (_, _) => http.Response('', 503),
            ).httpClient,
            maxAttempts: 1,
          ),
        ),
      );
      final pack = await offline.pack('ds-retreat-6689');
      expect(pack.items, hasLength(7));
    });

    test('unknown or foreign IDs are unavailable', () async {
      await expectLater(
        source.pack('ds-retreat-1'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        source.pack('ds-talk-95073'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });
  });

  group('talk → single', () {
    test('one voice, one original file, with attribution link', () async {
      await sync.sync();
      final track = await source.track('ds-talk-95073');

      expect(track.id, 'ds-talk-95073');
      expect(track.title, 'talk: Renewing motivation');
      expect(track.subtitle, 'Talk · Jill Shepherd · 25 min');
      expect(track.hasBackgroundSound, isFalse);
      expect(track.artist?.name, 'Jill Shepherd');
      expect(track.artist?.path, 'https://dharmaseed.org/talks/95073/');
      final file = track.voices.single.audioFiles.single;
      expect(file.id, 'ds-talk-95073');
      expect(
        file.path,
        startsWith('https://dharmaseed.org/talks/95073/'),
      );
      expect(file.path, endsWith('.mp3'));
      expect(file.duration, closeTo(25.1 * 60000, 6000));
    });

    test('guided meditations allow background sound', () async {
      await sync.sync();
      final track = await source.track('ds-talk-97073');
      expect(track.subtitle, startsWith('Guided meditation'));
      expect(track.hasBackgroundSound, isTrue);
    });

    test('an unsynced talk is fetched when opened', () async {
      final track = await source.track('ds-talk-99944');
      expect(track.title, 'talk: Wise Effort p2');
      expect(track.artist?.name, 'Jill Shepherd');
      expect(api.requests.map((r) => r.toString()), [
        'talks detail [99944]',
        'teachers detail [637]',
      ]);
    });

    test('a talk Dharma Seed withdrew is unavailable', () async {
      await expectLater(
        source.track('ds-talk-1'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });
  });

  group('kinds', () {
    test('recording types map to practice or talks', () {
      expect(DharmaSeedKind.fromRecordingType('Meditation').isPractice, isTrue);
      expect(DharmaSeedKind.fromRecordingType('Chanting').isPractice, isTrue);
      expect(DharmaSeedKind.fromRecordingType('Talk').isPractice, isFalse);
      expect(
        DharmaSeedKind.fromRecordingType('Q & A'),
        DharmaSeedKind.questions,
      );
      expect(DharmaSeedKind.fromRecordingType('Other'), DharmaSeedKind.other);
      expect(DharmaSeedKind.fromRecordingType(null), DharmaSeedKind.other);
    });
  });

  group('completion and browsing', () {
    setUp(() => sync.sync());

    test('pack track IDs cover only saved and started courses', () async {
      expect(await source.packTrackIds(), isEmpty);

      final started = await source.packTrackIds(
        startedTrackIds: {'ds-talk-95232', 'lib-other'},
      );
      expect(started.keys, ['ds-retreat-6689']);
      // Dharma Seed lists 8 talks for the retreat but serves only 7 of them:
      // once every talk has synced, ticks follow what the course shows.
      final pack = await source.pack('ds-retreat-6689');
      expect(started['ds-retreat-6689'], pack.items.map((i) => i.id).toList());
      expect(started['ds-retreat-6689'], hasLength(7));

      await db.setSaved(DsSavedKind.retreat, 6689, saved: true);
      expect((await source.packTrackIds()).keys, ['ds-retreat-6689']);
    });

    test('before talks sync, ticks use the retreat\'s own list', () async {
      final fresh = memoryDharmaSeedDb();
      addTearDown(fresh.close);
      await fresh.upsertRetreatRecords({
        1: {'name': 'Course', 'talks': [10, 11, 12]},
      });
      await fresh.setSaved(DsSavedKind.retreat, 1, saved: true);

      final ids = await DharmaSeedSource(db: fresh).packTrackIds();

      expect(ids['ds-retreat-1'], ['ds-talk-10', 'ds-talk-11', 'ds-talk-12']);
    });

    test('browse lists saved courses first, then recent ones', () async {
      final packs = await source.browsePacks();
      expect(packs.map((p) => p.id), ['ds-retreat-6689']);
      expect(packs.single.items, isEmpty);
    });

    test('search maps retreats and talks to existing rows', () async {
      final packs = await source.searchPacks('auckland');
      expect(packs.single.type, 'pack');
      expect(packs.single.path, '/packs/ds-retreat-6689');

      final tracks = await source.searchTracks('eightfold');
      expect(tracks.single.id, 'ds-talk-95232');
      expect(tracks.single.path, '/tracks/ds-talk-95232');
    });
  });

  group('router', () {
    test('dispatches by prefix and falls back to the local catalogue', () async {
      await sync.sync();
      final router = ContentRouter(
        catalogue: _LocalCatalogue(),
        sources: [source],
      );

      expect((await router.track('ds-talk-95073')).title, contains('Renewing'));
      expect((await router.track('lib-session')).title, 'Local session');
      await expectLater(
        router.track('yt-abc'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect((await router.browsePacks()).map((p) => p.id), [
        'lib-course',
        'ds-retreat-6689',
      ]);
    });

    test('repositories reach the source through the router', () async {
      await sync.sync();
      final packs = PackRepositoryImpl(sources: [source]);
      expect((await packs.fetchPacks('ds-retreat-6689')).items, hasLength(7));
      expect(
        (await packs.fetchPackTrackIds(
          startedTrackIds: {'ds-talk-99944'},
        )).keys,
        ['ds-retreat-6689'],
      );
      final search = SearchRepository(sources: [source]);
      expect(await search.searchPacks('auckland'), hasLength(1));
      final tracks = TrackSearchRepository(sources: [source]);
      expect(await tracks.searchTracks('renewing'), hasLength(1));
    });

    test('a failing source does not break browsing or search', () async {
      await db.close();
      final broken = DharmaSeedSource(db: db);
      final router = ContentRouter(
        catalogue: _LocalCatalogue(),
        sources: [broken],
      );
      expect((await router.browsePacks()).map((p) => p.id), ['lib-course']);
      expect(await router.searchTracks('x'), isEmpty);
      expect(await router.packTrackIds(), isEmpty);
      db = memoryDharmaSeedDb(); // for tearDown
    });
  });
}
