import 'dart:convert';

import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/completed_tracks_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists personal practice history on this device without an account.
class StatsService {
  final SharedPreferences _prefs;

  StatsService({required SharedPreferences prefs}) : _prefs = prefs;

  Future<LocalAllStats> loadStats() =>
      serializeStatsPreferences(_prefs, () async {
        final stored = _prefs.getString(
          SharedPreferenceConstants.localAllStatsKey,
        );
        if (stored == null || stored == 'null') return LocalAllStats.empty();
        try {
          return LocalAllStats.fromJson(
            jsonDecode(stored) as Map<String, dynamic>,
          );
        } catch (error) {
          AppLogger.e('STATS_SERVICE', 'Could not read local stats', error);
          rethrow;
        }
      });

  Future<void> saveStats(LocalAllStats stats) =>
      serializeStatsPreferences(_prefs, () async {
        final saved = await _prefs.setString(
          SharedPreferenceConstants.localAllStatsKey,
          jsonEncode(stats.toJson()),
        );
        if (!saved) throw StateError('Could not save local stats');
      });

  Future<void> clearStats() => serializeStatsPreferences(_prefs, () async {
    final cleared = await _prefs.remove(
      SharedPreferenceConstants.localAllStatsKey,
    );
    if (!cleared) throw StateError('Could not clear local stats');
  });
}
