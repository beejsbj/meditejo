import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';

class TrackSearchRepository {
  TrackSearchRepository({
    LocalCatalogue catalogue = const LocalCatalogue(),
    List<ContentSource> sources = const [],
  }) : router = ContentRouter(catalogue: catalogue, sources: sources);

  final ContentRouter router;

  Future<List<TrackSearchModel>> searchTracks(String query) async =>
      router.searchTracks(query);
}
