import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/local_catalogue.dart';

/// One content source behind the existing pack/track UI: Dharma Seed today,
/// RSS feeds and YouTube next.
///
/// A source owns every ID that starts with [prefix] (`ds-`, `lib-`, `yt-`)
/// and maps its own records into [PackModel] (a course), [Track] (a single
/// session) and search rows, so PackView, the player, downloads, favourites
/// and completion work without knowing where content came from.
///
/// Rules for implementers:
/// - IDs are stable for the life of the content. They are stored in stats,
///   favourites, downloads and the native completion queue.
/// - Pack items are tracks in play order, `type: 'track'`, with
///   `path: '/tracks/<id>'`.
/// - [track] returns one voice holding one audio file whose `path` is the URL
///   to play now. A source with expiring URLs resolves a fresh one here.
/// - Unknown or withdrawn IDs throw [CatalogueEntryUnavailable]; downloads
///   then fall back to saved metadata. Network failures should degrade to
///   what is already on the device rather than throw.
abstract interface class ContentSource {
  /// The ID prefix this source owns, including its trailing dash.
  String get prefix;

  /// Packs to show when browsing. A large catalogue returns a bounded,
  /// useful slice (saved first), not everything it holds.
  Future<List<PackModel>> browsePacks();

  Future<PackModel> pack(String id);

  Future<Track> track(String id);

  /// Track IDs per pack, for pack completion ticks. A large catalogue may
  /// limit this to packs that are saved or contain one of [startedTrackIds].
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  });

  Future<List<PackItemsModel>> searchPacks(String query);

  Future<List<TrackSearchModel>> searchTracks(String query);
}

/// Dispatches by ID prefix to the owning [ContentSource], falling back to the
/// bundled [LocalCatalogue] for IDs no source claims.
class ContentRouter {
  ContentRouter({
    this.catalogue = const LocalCatalogue(),
    this.sources = const [],
  });

  final LocalCatalogue catalogue;
  final List<ContentSource> sources;

  ContentSource? sourceFor(String id) {
    for (final source in sources) {
      if (id.startsWith(source.prefix)) return source;
    }
    return null;
  }

  Future<List<PackModel>> browsePacks() async => [
    ...catalogue.packs,
    for (final packs in await Future.wait(sources.map((s) => s.browsePacks())))
      ...packs,
  ];

  Future<PackModel> pack(String id) async {
    final source = sourceFor(id);
    return source == null ? catalogue.pack(id) : source.pack(id);
  }

  Future<Track> track(String id) async {
    final source = sourceFor(id);
    return source == null ? catalogue.track(id) : source.track(id);
  }

  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async {
    final maps = await Future.wait(
      sources.map((s) => s.packTrackIds(startedTrackIds: startedTrackIds)),
    );
    return {
      ...catalogue.packTrackIds,
      for (final map in maps) ...map,
    };
  }

  Future<List<PackItemsModel>> searchPacks(String query) async => [
    ...catalogue.searchPacks(query),
    for (final results in await Future.wait(
      sources.map((s) => s.searchPacks(query)),
    ))
      ...results,
  ];

  Future<List<TrackSearchModel>> searchTracks(String query) async => [
    ...catalogue.searchTracks(query),
    for (final results in await Future.wait(
      sources.map((s) => s.searchTracks(query)),
    ))
      ...results,
  ];
}
