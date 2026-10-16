import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/favorites/favorite_item.dart';
import 'package:medito/repositories/favorites/favorites_repository.dart';

import '../../utils/logger.dart';

class FavoritesNotifier extends AsyncNotifier<List<FavoriteItem>> {
  // Invalidating the provider re-runs build() on this instance.
  late FavoritesRepository _repository;

  @override
  Future<List<FavoriteItem>> build() async {
    _repository = ref.read(favoritesRepositoryProvider);
    return _repository.loadFavorites();
  }

  /// Reloads this device's saved favorites, including after a load error.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Adds [item] optimistically, reverting if the local save fails.
  Future<void> addToFavorites(FavoriteItem item) async {
    final previousFavorites = state.value ?? [];
    if (previousFavorites.any((fav) => fav.id == item.id)) return;

    final updatedFavorites = [...previousFavorites, item];
    state = AsyncValue.data(updatedFavorites);

    try {
      await _repository.saveFavorites(updatedFavorites);
    } catch (e) {
      AppLogger.e(
        'FAVORITES',
        'Failed to save after adding favorite, reverting: $e',
      );
      if (ref.mounted) state = AsyncValue.data(previousFavorites);
    }
  }

  /// Removes the favorite with [id], reverting if the local save fails.
  Future<void> removeFromFavorites(String id) async {
    final previousFavorites = state.value ?? [];
    final updatedFavorites = previousFavorites
        .where((item) => item.id != id)
        .toList();

    if (updatedFavorites.length == previousFavorites.length) return;

    state = AsyncValue.data(updatedFavorites);

    try {
      await _repository.saveFavorites(updatedFavorites);
    } catch (e) {
      AppLogger.e(
        'FAVORITES',
        'Failed to save after removing favorite, reverting: $e',
      );
      if (ref.mounted) state = AsyncValue.data(previousFavorites);
    }
  }
}

final favoritesNotifierProvider =
    AsyncNotifierProvider<FavoritesNotifier, List<FavoriteItem>>(
      FavoritesNotifier.new,
    );
