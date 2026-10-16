import 'package:medito/models/explore/explore_list_item.dart';
import 'package:medito/models/tags/tag_model.dart';
import 'package:medito/services/local_catalogue.dart';

abstract class TagsRepository {
  /// All local tags and the track → tags map.
  Future<TagCatalog> fetchCatalog();

  /// Local tracks carrying [tagId], strongest match first.
  Future<List<TrackItem>> fetchTracksForTag(String tagId);
}

class TagsRepositoryImpl implements TagsRepository {
  TagsRepositoryImpl({this.catalogue = const LocalCatalogue()});

  final LocalCatalogue catalogue;

  @override
  Future<TagCatalog> fetchCatalog() async => catalogue.tags;

  @override
  Future<List<TrackItem>> fetchTracksForTag(String tagId) async =>
      catalogue.tracksForTag(tagId);
}
