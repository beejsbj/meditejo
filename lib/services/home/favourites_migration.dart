import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Moves favourites from before #79 into pins, once.
///
/// Favourites and pins were the same idea, so the app keeps only pins. Each
/// favourite is pinned after what is already pinned (those keep their places
/// on Home), oldest favourite first; one already pinned is not pinned twice.
/// A favourite session becomes a pinned session. The favourites are then
/// removed, so a second run finds nothing to do. Unreadable favourites are
/// dropped: there is nothing in them to move.
Future<void> migrateFavouritesToPins(SharedPreferences prefs) async {
  final raw = prefs.getString(SharedPreferenceConstants.legacyFavorites);
  if (raw == null) return;

  final favourites = <({String id, bool session, int at, int order})>[];
  try {
    final list = jsonDecode(raw);
    if (list is List) {
      for (final (i, item) in list.indexed) {
        if (item is! Map) continue;
        final id = item['id'];
        if (id is! String || id.isEmpty) continue;
        final at = item['timestamp'];
        favourites.add((
          id: id,
          // Medito saved packs as "pack" and everything else as a track.
          session: item['type'] != 'pack',
          at: at is int ? at : 0,
          order: i,
        ));
      }
    }
  } catch (e) {
    AppLogger.w('PINS', 'Could not read favourites to move into pins: $e');
  }
  favourites.sort(
    (a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.order - b.order,
  );

  final pins = [
    ...?prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds) ??
        _legacyUpNext(prefs),
  ];
  final sessions = {
    ...?prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds),
  };
  for (final f in favourites) {
    if (pins.contains(f.id)) continue;
    pins.add(f.id);
    if (f.session) sessions.add(f.id);
  }

  await prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, pins);
  await prefs.setStringList(
    SharedPreferenceConstants.pinnedSessionIds,
    sessions.where(pins.contains).toList(),
  );
  await prefs.remove(SharedPreferenceConstants.legacyFavorites);
}

/// The one course Home used to continue, which the pins start from when
/// nothing was pinned yet.
List<String>? _legacyUpNext(SharedPreferences prefs) {
  final id = prefs.getString(SharedPreferenceConstants.upNextPackId);
  return id == null || id.isEmpty ? null : [id];
}
