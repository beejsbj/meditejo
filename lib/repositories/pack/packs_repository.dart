import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'packs_repository.g.dart';

abstract class PacksRepository {
  Future<List<PackModel>> fetchAllPacks();

  Future<PackModel> fetchPacks(String packId);

  /// Every pack's track ids, including tracks in its sub-packs. Large
  /// sources may limit this to saved packs and packs containing one of
  /// [startedTrackIds].
  Future<Map<String, List<String>>> fetchPackTrackIds({
    Set<String> startedTrackIds = const {},
  });
}

class PackRepositoryImpl extends PacksRepository {
  PackRepositoryImpl({
    LocalCatalogue catalogue = const LocalCatalogue(),
    List<ContentSource> sources = const [],
  }) : router = ContentRouter(catalogue: catalogue, sources: sources);

  final ContentRouter router;

  @override
  Future<List<PackModel>> fetchAllPacks() => router.browsePacks();

  @override
  Future<PackModel> fetchPacks(String packId) => router.pack(packId);

  @override
  Future<Map<String, List<String>>> fetchPackTrackIds({
    Set<String> startedTrackIds = const {},
  }) => router.packTrackIds(startedTrackIds: startedTrackIds);
}

@Riverpod(keepAlive: true)
PackRepositoryImpl packRepository(Ref ref) {
  return PackRepositoryImpl(sources: ref.watch(contentSourcesProvider));
}
