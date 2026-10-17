import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';

class SearchRepository {
  SearchRepository({
    LocalCatalogue catalogue = const LocalCatalogue(),
    List<ContentSource> sources = const [],
  }) : router = ContentRouter(catalogue: catalogue, sources: sources);

  final ContentRouter router;

  Future<List<PackItemsModel>> searchPacks(String query) async =>
      router.searchPacks(query);
}
