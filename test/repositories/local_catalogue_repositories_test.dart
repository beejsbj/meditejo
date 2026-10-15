import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/favorites/favorite_item.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/repositories/background_sounds/background_sounds_repository.dart';
import 'package:medito/repositories/explore/search_repository.dart';
import 'package:medito/repositories/explore/track_search_repository.dart';
import 'package:medito/repositories/favorites/favorites_repository.dart';
import 'package:medito/repositories/home/home_repository.dart';
import 'package:medito/repositories/pack/packs_repository.dart';
import 'package:medito/repositories/track/track_repository.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _track = Track(
  id: 'lib-session',
  title: 'Local session',
  description: '',
  coverUrl: '',
  isPublished: true,
  hasBackgroundSound: false,
);
const _pack = PackModel(
  id: 'lib-course',
  title: 'Local course',
  items: [
    PackItemsModel(
      type: 'track',
      id: 'lib-session',
      title: 'Local session',
      path: '/tracks/lib-session',
    ),
  ],
);

class _SourceCatalogue extends LocalCatalogue {
  @override
  List<PackModel> get packs => [_pack];

  @override
  Map<String, List<String>> get packTrackIds => {
    _pack.id: [_track.id],
  };

  @override
  PackModel pack(String id) => id == _pack.id ? _pack : super.pack(id);

  @override
  Track track(String id) => id == _track.id ? _track : super.track(id);
}

class _FailingCatalogue extends LocalCatalogue {
  _FailingCatalogue(this.error);

  final Object error;

  @override
  Track track(String id) => throw error;
}

void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.listen(trackRepositoryProvider, (_, _) {});
    container.listen(backgroundSoundsRepositoryProvider, (_, _) {});
    return container;
  }

  test('home, explore and search succeed with an empty catalogue', () async {
    final home = HomeRepositoryImpl();
    final data = await home.fetchHome();
    expect(data.carousel, isEmpty);
    expect(data.shortcuts, isEmpty);
    expect(data.todayQuote, isNull);
    expect(await home.fetchLatestAnnouncement(), isNull);

    final packs = PackRepositoryImpl();
    expect(await packs.fetchAllPacks(), isEmpty);
    expect(await packs.fetchPackTrackIds(), isEmpty);
    for (final query in ['', '   ', 'meditation', '睡眠']) {
      expect(await SearchRepository().searchPacks(query), isEmpty);
      expect(await TrackSearchRepository().searchTracks(query), isEmpty);
    }
  });

  test('missing and old IDs fail locally without fabricated content', () async {
    final container = await containerWith({});
    final tracks = container.read(trackRepositoryProvider);
    for (final id in ['', 'legacy-id', 'ds-not-yet-imported']) {
      await expectLater(
        PackRepositoryImpl().fetchPacks(id),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        tracks.fetchTrack(id),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    }
  });

  test(
    'saved favourite IDs resolve downloaded metadata with an empty catalogue',
    () async {
      final savedTracks = [
        for (final id in [
          'lib-session',
          'ds-session',
          'yt-session',
          'opaque-id',
        ])
          _track.copyWith(
            id: id,
            voices: [
              TrackVoice(
                audioFiles: [
                  TrackAudioFile(
                    id: '$id-file',
                    path: 'https://example.org/$id.mp3',
                    duration: 60000,
                  ),
                ],
              ),
            ],
          ),
      ];
      final encodedDownloads = jsonEncode(savedTracks);
      final encodedFavorites = jsonEncode([
        for (final track in savedTracks)
          FavoriteItem(
            id: track.id,
            title: track.title,
            type: FavoriteItemType.track,
            timestamp: 1,
          ).toJson(),
      ]);
      final container = await containerWith({
        SharedPreferenceConstants.downloads: encodedDownloads,
        SharedPreferenceConstants.favorites: encodedFavorites,
      });
      final prefs = container.read(sharedPreferencesProvider);
      final favorites = await FavoritesRepositoryImpl(
        prefs: prefs,
      ).loadFavorites();
      final repo = container.read(trackRepositoryProvider);
      for (var i = 0; i < favorites.length; i++) {
        expect(await repo.fetchTrack(favorites[i].id), savedTracks[i]);
      }
      await expectLater(
        repo.fetchTrack('unknown-id'),
        throwsA(
          isA<CatalogueEntryUnavailable>().having(
            (error) => error.id,
            'id',
            'unknown-id',
          ),
        ),
      );
      expect(
        prefs.getString(SharedPreferenceConstants.downloads),
        encodedDownloads,
      );
      expect(
        prefs.getString(SharedPreferenceConstants.favorites),
        encodedFavorites,
      );
    },
  );

  test(
    'other catalogue failures do not fall back to downloaded metadata',
    () async {
      final error = StateError('catalogue failed');
      final container = await containerWith({
        SharedPreferenceConstants.downloads: jsonEncode([_track]),
      });
      final provider = Provider<TrackRepository>(
        (ref) =>
            TrackRepositoryImpl(ref: ref, catalogue: _FailingCatalogue(error)),
      );
      await expectLater(
        container.read(provider).fetchTrack(_track.id),
        throwsA(same(error)),
      );
    },
  );

  test('source adapters keep the existing pack and track interfaces', () async {
    final catalogue = _SourceCatalogue();
    final repo = PackRepositoryImpl(catalogue: catalogue);
    expect(await repo.fetchAllPacks(), [_pack]);
    expect(await repo.fetchPacks(_pack.id), _pack);
    expect(await repo.fetchPackTrackIds(), {
      _pack.id: [_track.id],
    });
    final provider = Provider<TrackRepository>((ref) {
      return TrackRepositoryImpl(ref: ref, catalogue: catalogue);
    });
    final container = await containerWith({
      SharedPreferenceConstants.downloads: jsonEncode([
        _track.copyWith(title: 'Older downloaded metadata'),
      ]),
    });
    expect(await container.read(provider).fetchTrack(_track.id), _track);
  });

  test('download and current track preferences still round trip', () async {
    final container = await containerWith({
      SharedPreferenceConstants.localAllStatsKey:
          '{"tracksChecked":["lib-session"]}',
      SharedPreferenceConstants.upNextPackId: _pack.id,
    });
    final repo = container.read(trackRepositoryProvider);
    expect(await repo.fetchTrackFromPreference(), isEmpty);
    expect(await repo.fetchCurrentlyPlayingTrackFromPreference(), isNull);
    await repo.addTrackInPreference([_track]);
    expect(await repo.fetchTrackFromPreference(), [_track]);
    await repo.addCurrentlyPlayingTrackInPreference(_track);
    expect(await repo.fetchCurrentlyPlayingTrackFromPreference(), _track);
    await repo.removeCurrentlyPlayingTrackInPreference();
    expect(await repo.fetchCurrentlyPlayingTrackFromPreference(), isNull);
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString(SharedPreferenceConstants.upNextPackId), _pack.id);
    expect(
      prefs.getString(SharedPreferenceConstants.localAllStatsKey),
      '{"tracksChecked":["lib-session"]}',
    );
  });

  test('old sound caches and selected remote URLs are not exposed', () async {
    const legacy = BackgroundSoundsModel(
      id: 'old-sound',
      title: 'Old sound',
      path: 'https://old.example/sound.mp3',
      duration: 60,
    );
    final container = await containerWith({
      SharedPreferenceConstants.bgSoundCatalog: jsonEncode([legacy.toJson()]),
      SharedPreferenceConstants.listBgSound: [jsonEncode(legacy.toJson())],
      SharedPreferenceConstants.bgSound: jsonEncode(legacy.toJson()),
      SharedPreferenceConstants.bgSoundVolume: 0.4,
      SharedPreferenceConstants.timerSessionBellsEnabled: false,
    });
    final repo = container.read(backgroundSoundsRepositoryProvider);
    expect(await repo.fetchBackgroundSounds(), isEmpty);
    expect(repo.fetchCachedBackgroundSounds(), isEmpty);
    expect(await repo.fetchLocallySavedBackgroundSounds(), isEmpty);
    expect(repo.getSelectedBgSoundFromSharedPreferences(), isNull);
    expect(repo.getSessionBellsEnabled(forTimer: true), isFalse);
    expect(repo.getBgSoundVolume(), 0.4);
    // Hide unavailable recordings without deleting existing preferences.
    expect(
      container
          .read(sharedPreferencesProvider)
          .getString(SharedPreferenceConstants.bgSound),
      jsonEncode(legacy.toJson()),
    );
  });
}
