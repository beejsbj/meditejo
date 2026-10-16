import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/local_catalogue.dart';

class SearchRepository {
  SearchRepository({this.catalogue = const LocalCatalogue()});

  final LocalCatalogue catalogue;

  Future<List<PackItemsModel>> searchPacks(String query) async =>
      catalogue.searchPacks(query);
}
