import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/meditation/download_track_provider.dart';
import 'package:medito/providers/stats_provider.dart';

/// IDs of tracks saved for offline listening, for the "downloaded" mark on a
/// session row. Empty while loading or if the list is unavailable.
final downloadedTrackIdsProvider = Provider<Set<String>>(
  (ref) => {
    for (final track in ref.watch(downloadedTracksProvider).value ?? const [])
      track.id,
  },
);

/// IDs of tracks listened through to the end, from local stats.
final playedTrackIdsProvider = Provider<Set<String>>(
  (ref) => {...?ref.watch(statsProvider).value?.tracksChecked},
);
