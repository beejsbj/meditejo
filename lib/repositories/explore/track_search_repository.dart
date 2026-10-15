import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/services/local_catalogue.dart';

class TrackSearchRepository {
  TrackSearchRepository({this.catalogue = const LocalCatalogue()});

  final LocalCatalogue catalogue;

  Future<List<TrackSearchModel>> searchTracks(String query) async =>
      catalogue.searchTracks(query);
}
