import 'package:medito/models/explore/track_search_model.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/models/track/track.dart';
import 'package:medito/services/content/content_source.dart';

/// A source that only knows how to save: for widget tests that show a Save
/// button without opening the Dharma Seed database.
class FakeSavableSource implements ContentSource, SavableContentSource {
  FakeSavableSource({Set<String> saved = const {}}) : saved = {...saved};

  final Set<String> saved;

  @override
  String get prefix => 'ds-';

  @override
  bool canSave(String id) =>
      id.startsWith('ds-retreat-') || id.startsWith('ds-teacher-');

  @override
  Future<bool> isSaved(String id) async => saved.contains(id);

  @override
  Future<void> setSaved(String id, {required bool saved}) async =>
      saved ? this.saved.add(id) : this.saved.remove(id);

  @override
  Future<List<PackModel>> browsePacks() async => const [];

  @override
  Future<PackModel> pack(String id) => throw UnimplementedError();

  @override
  Future<Track> track(String id) => throw UnimplementedError();

  @override
  Future<Map<String, List<String>>> packTrackIds({
    Set<String> startedTrackIds = const {},
  }) async => const {};

  @override
  Future<List<PackItemsModel>> searchPacks(String query) async => const [];

  @override
  Future<List<TrackSearchModel>> searchTracks(String query) async => const [];
}
