import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'packs_repository.g.dart';

abstract class PacksRepository {
  Future<List<PackModel>> fetchAllPacks();

  Future<PackModel> fetchPacks(String packId);

  /// Every pack's track ids, including tracks in its sub-packs.
  Future<Map<String, List<String>>> fetchPackTrackIds();
}

class PackRepositoryImpl extends PacksRepository {
  PackRepositoryImpl({this.catalogue = const LocalCatalogue()});

  final LocalCatalogue catalogue;

  @override
  Future<List<PackModel>> fetchAllPacks() async => catalogue.packs;

  @override
  Future<PackModel> fetchPacks(String packId) async => catalogue.pack(packId);

  @override
  Future<Map<String, List<String>>> fetchPackTrackIds() async =>
      catalogue.packTrackIds;
}

@Riverpod(keepAlive: true)
PackRepositoryImpl packRepository(Ref _) {
  return PackRepositoryImpl();
}
