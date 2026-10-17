import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'track_repository.g.dart';

abstract class TrackRepository {
  Future<Track> fetchTrack(String trackId);

  Future<List<Track>> fetchTrackFromPreference();

  Future<void> addTrackInPreference(List<Track> trackList);

  Future<void> addCurrentlyPlayingTrackInPreference(Track track);

  Future<void> removeCurrentlyPlayingTrackInPreference();

  Future<Track?> fetchCurrentlyPlayingTrackFromPreference();
}

class TrackRepositoryImpl extends TrackRepository {
  final Ref ref;
  final ContentRouter router;

  TrackRepositoryImpl({
    required this.ref,
    LocalCatalogue catalogue = const LocalCatalogue(),
    List<ContentSource> sources = const [],
  }) : router = ContentRouter(catalogue: catalogue, sources: sources);

  @override
  Future<Track> fetchTrack(String trackId) async {
    try {
      return await router.track(trackId);
    } on CatalogueEntryUnavailable {
      // Saved favourites resolve by ID too. Keep downloaded metadata usable
      // when its source catalogue is empty or no longer carries the track.
      final downloads = await fetchTrackFromPreference();
      for (final track in downloads) {
        if (track.id == trackId) return track;
      }
      rethrow;
    }
  }

  @override
  Future<List<Track>> fetchTrackFromPreference() async {
    var downloadedTrackList = <Track>[];
    var downloadedTrackFromPref = ref
        .read(sharedPreferencesProvider)
        .getString(SharedPreferenceConstants.downloads);
    if (downloadedTrackFromPref != null) {
      var tempList = [];
      tempList = json.decode(downloadedTrackFromPref);
      for (var element in tempList) {
        downloadedTrackList.add(Track.fromJson(element));
      }
    }

    return downloadedTrackList;
  }

  @override
  Future<void> addTrackInPreference(List<Track> trackList) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(SharedPreferenceConstants.downloads, json.encode(trackList));
  }

  @override
  Future<void> addCurrentlyPlayingTrackInPreference(Track track) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(
          SharedPreferenceConstants.currentPlayingTrack,
          json.encode(track),
        );
  }

  @override
  Future<void> removeCurrentlyPlayingTrackInPreference() async {
    await ref
        .read(sharedPreferencesProvider)
        .remove(SharedPreferenceConstants.currentPlayingTrack);
  }

  @override
  Future<Track?> fetchCurrentlyPlayingTrackFromPreference() async {
    var track = ref
        .read(sharedPreferencesProvider)
        .getString(SharedPreferenceConstants.currentPlayingTrack);
    if (track != null) {
      return Track.fromJson(json.decode(track));
    }

    return null;
  }
}

@riverpod
TrackRepository trackRepository(Ref ref) {
  return TrackRepositoryImpl(
    ref: ref,
    sources: ref.watch(contentSourcesProvider),
  );
}
