import 'package:medito/models/local_all_stats.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:medito/services/home_widget_service.dart';

part 'stats_provider.g.dart';

final statsManagerProvider = Provider<StatsManager>((ref) => StatsManager());

@Riverpod(keepAlive: true)
class StatsNotifier extends AsyncNotifier<LocalAllStats> {
  DateTime? _lastRefresh;
  static const _minRefreshInterval = Duration(seconds: 2);

  @override
  Future<LocalAllStats> build() async {
    AppLogger.d('STATS_PROVIDER', 'StatsNotifier: Building');

    return _fetchStats();
  }

  Future<LocalAllStats> _fetchStats() async {
    var statsManager = ref.read(statsManagerProvider);

    try {
      await statsManager.initialize();
      await statsManager.sync();

      return await statsManager.localAllStats;
    } catch (error) {
      AppLogger.e('STATS_PROVIDER', 'StatsNotifier: Error during fetch', error);

      if (error is AppError) {
        rethrow;
      }
      throw const UnknownError();
    }
  }

  Future<void> refresh() async {
    AppLogger.d('STATS_PROVIDER', 'StatsNotifier: Starting refresh');
    if (_lastRefresh != null) {
      var timeSinceLastRefresh = DateTime.now().difference(_lastRefresh!);
      if (timeSinceLastRefresh < _minRefreshInterval) {
        AppLogger.d(
          'STATS_PROVIDER',
          'StatsNotifier: Skipping refresh - too soon',
        );

        return;
      }
    }

    _lastRefresh = DateTime.now();
    state = await AsyncValue.guard(_fetchStats);
    AppLogger.d('STATS_PROVIDER', 'StatsNotifier: Refresh completed');

    // Update home widget if stats are available (fire-and-forget to avoid blocking)
    if (state.hasValue && state.value != null) {
      // Don't await widget updates to prevent blocking the UI thread
      // Widget updates are non-critical and should not cause ANRs
      HomeWidgetService.updateWidgetFromStats(state.value!).catchError((e) {
        // Silently fail - widget updates are not critical
      });
    }
  }

  Future<void> refreshFromLocal() async {
    AppLogger.d(
      'STATS_PROVIDER',
      'StatsNotifier: Starting refresh from local stats',
    );
    try {
      var localStats = await _fetchStats();
      state = AsyncValue.data(localStats);
      AppLogger.d(
        'STATS_PROVIDER',
        'StatsNotifier: Refresh from local completed',
      );

      // Update home widget (fire-and-forget to avoid blocking)
      HomeWidgetService.updateWidgetFromStats(localStats).catchError((e) {
        // Silently fail - widget updates are not critical
      });
    } catch (error) {
      AppLogger.e(
        'STATS_PROVIDER',
        'StatsNotifier: Error during refresh from local',
        error,
      );

      if (error is AppError) {
        state = AsyncValue.error(error, StackTrace.current);
      } else {
        state = AsyncValue.error(const UnknownError(), StackTrace.current);
      }
    }
  }
}
