import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/favorites/favorite_item.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'favorites_repository.g.dart';

abstract class FavoritesRepository {
  Future<List<FavoriteItem>> loadFavorites();
  Future<void> saveFavorites(List<FavoriteItem> favorites);
}

class FavoritesRepositoryImpl implements FavoritesRepository {
  final SharedPreferences _prefs;

  FavoritesRepositoryImpl({required SharedPreferences prefs}) : _prefs = prefs;

  @override
  Future<List<FavoriteItem>> loadFavorites() async {
    final favoritesJson = _prefs.getString(SharedPreferenceConstants.favorites);
    if (favoritesJson == null) return [];

    final List<dynamic> jsonList = json.decode(favoritesJson);
    return jsonList.map((json) => FavoriteItem.fromJson(json)).toList();
  }

  @override
  Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    final jsonList = favorites.map((item) => item.toJson()).toList();
    try {
      final saved = await _prefs.setString(
        SharedPreferenceConstants.favorites,
        json.encode(jsonList),
      );
      if (!saved) {
        throw StateError('Failed to persist favorites');
      }
    } catch (_) {
      // SharedPreferences updates its cache before the disk write finishes.
      // Discard an unsaved value so a refresh cannot undo the UI rollback.
      await _prefs.reload();
      rethrow;
    }
  }
}

@riverpod
FavoritesRepository favoritesRepository(Ref ref) {
  return FavoritesRepositoryImpl(prefs: ref.read(sharedPreferencesProvider));
}
