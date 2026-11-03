import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/repositories/explore/search_repository.dart';

final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository(sources: ref.watch(contentSourcesProvider));
});

final searchPacksProvider = FutureProvider.autoDispose
    .family<List<PackItemsModel>, String>(
  (ref, query) async {
    final repository = ref.watch(searchRepositoryProvider);
    return repository.searchPacks(query);
  },
);
