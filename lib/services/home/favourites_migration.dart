import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moves favourites from before #79 into pins, once.
///
/// Favourites and pins were the same idea, so the app keeps only pins. Each
/// favourite is pinned after what is already pinned (those keep their places
/// on Home), in the order they were saved; one already pinned is not pinned
/// twice. A favourite session becomes a pinned session, and each favourite's
/// saved title is kept for when its content is gone.
///
/// A flag makes it run once, so a favourite unpinned later never comes back.
/// The favourites themselves are left where they were, so a build without
/// pins still finds them.
// TODO(#79): delete SharedPreferenceConstants.legacyFavorites in a later
// release, once no build without pins is installed.
Future<void> migrateFavouritesToPins(SharedPreferences prefs) async {
  if (prefs.getBool(SharedPreferenceConstants.favouritesMigrated) ?? false) {
    return;
  }
  final raw = prefs.getString(SharedPreferenceConstants.legacyFavorites);
  if (raw != null) await _move(prefs, raw);
  await prefs.setBool(SharedPreferenceConstants.favouritesMigrated, true);
}

Future<void> _move(SharedPreferences prefs, String raw) async {
  final favourites = <({String id, bool session, String? title})>[];
  try {
    final list = jsonDecode(raw);
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String || id.isEmpty) continue;
        final type = item['type'];
        final title = item['title'];
        favourites.add((
          id: id,
          // Medito saved packs as "pack" and everything else as a track.
          session: type is! String || type.toLowerCase() != 'pack',
          title: title is String && title.trim().isNotEmpty ? title : null,
        ));
      }
    }
  } catch (e) {
    AppLogger.w('PINS', 'Could not read favourites to move into pins: $e');
  }
  if (favourites.isEmpty) return;

  final pins = [
    ...?prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds) ??
        _legacyUpNext(prefs),
  ];
  final sessions = {
    ...?prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds),
  };
  final titles = readPinnedTitles(prefs);
  for (final f in favourites) {
    if (pins.contains(f.id)) continue;
    pins.add(f.id);
    if (f.session) sessions.add(f.id);
    if (f.title case final title?) titles[f.id] = title;
  }

  await prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, pins);
  await prefs.setStringList(
    SharedPreferenceConstants.pinnedSessionIds,
    sessions.where(pins.contains).toList(),
  );
  await prefs.setString(
    SharedPreferenceConstants.pinnedTitles,
    jsonEncode(titles),
  );
}

/// Titles kept for pins whose content may be gone: id to title.
Map<String, String> readPinnedTitles(SharedPreferences prefs) {
  final raw = prefs.getString(SharedPreferenceConstants.pinnedTitles);
  if (raw == null) return {};
  try {
    final map = jsonDecode(raw);
    if (map is! Map) return {};
    return {
      for (final MapEntry(:key, :value) in map.entries)
        if (key is String && value is String) key: value,
    };
  } catch (_) {
    return {};
  }
}

/// The one course Home used to continue, which the pins start from when
/// nothing was pinned yet.
List<String>? _legacyUpNext(SharedPreferences prefs) {
  final id = prefs.getString(SharedPreferenceConstants.upNextPackId);
  return id == null || id.isEmpty ? null : [id];
}
