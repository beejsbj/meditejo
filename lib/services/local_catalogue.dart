import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/explore/explore_list_item.dart';
import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/home/home_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/tags/tag_model.dart';
import 'package:medito/models/track/track.dart';

/// Local source boundary for the existing pack/track UI.
///
/// Intentionally ships without content. Future source adapters can implement
/// this boundary using source-prefixed IDs and the existing UI models. There
/// is no remote fallback, including for IDs saved by an earlier app version.
class LocalCatalogue {
  const LocalCatalogue();

  List<PackModel> get packs => const [];
  Map<String, List<String>> get packTrackIds => const {};
  HomeModel get home => const HomeModel();
  TagCatalog get tags => TagCatalog.empty;

  // The bundled session bell is a timer cue, not an ambient recording.
  List<BackgroundSoundsModel> get backgroundSounds => const [];

  PackModel pack(String id) => throw CatalogueEntryUnavailable('pack', id);
  Track track(String id) => throw CatalogueEntryUnavailable('track', id);
  List<PackItemsModel> searchPacks(String query) => const [];
  List<TrackSearchModel> searchTracks(String query) => const [];
  List<TrackItem> tracksForTag(String tagId) => const [];
}

/// A saved link can outlive the catalogue entry it points to.
class CatalogueEntryUnavailable implements Exception {
  const CatalogueEntryUnavailable(this.kind, this.id);

  final String kind;
  final String id;

  @override
  String toString() => 'This $kind is not available in the local catalogue.';
}
