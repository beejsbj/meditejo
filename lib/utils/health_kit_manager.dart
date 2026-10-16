import 'dart:io';

import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/audio_pigeon.g.dart';
import 'logger.dart';

class HealthKitManager {
  static const _syncEnabledKey = 'healthSyncEnabled';

  static final HealthKitManager _instance = HealthKitManager._internal();
  final Health health;
  final MeditoHealthConnectManager _androidBridge;
  final bool _isAndroid;
  bool _configured = false;

  factory HealthKitManager() {
    return _instance;
  }

  HealthKitManager._internal()
    : health = Health(),
      _androidBridge = MeditoHealthConnectManager(),
      _isAndroid = Platform.isAndroid;

  HealthKitManager.forTesting({
    required this.health,
    required bool isAndroid,
    MeditoHealthConnectManager? androidBridge,
  }) : _isAndroid = isAndroid,
       _androidBridge = androidBridge ?? MeditoHealthConnectManager();

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    if (Platform.isIOS) {
      await health.configure();
    }
    _configured = true;
  }

  Future<bool> isHealthConnectAvailable() async {
    if (!_isAndroid) return true;
    try {
      final status = await _androidBridge.getStatus();
      return status == HealthConnectStatus.available;
    } catch (_) {
      return false;
    }
  }

  Future<void> installHealthConnect() async {
    if (!_isAndroid) return;
    try {
      await _androidBridge.openHealthConnectInstall();
    } catch (_) {}
  }

  Future<bool?> isHealthSyncPermitted() async {
    try {
      await _ensureConfigured();
      if (_isAndroid) {
        if (!await isHealthConnectAvailable()) return false;
        return await _androidBridge.hasMindfulnessPermissions();
      }
      return await health.hasPermissions(
        [HealthDataType.MINDFULNESS],
        // HealthKit cannot disclose read grants; only writing is needed here.
        permissions: [HealthDataAccess.WRITE],
      );
    } catch (e) {
      return false;
    }
  }

  /// Migrate once using a silent permission check. A previous prompt alone
  /// does not mean the user agreed to sync.
  Future<bool> isSyncEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_syncEnabledKey);
    if (saved != null) return saved;
    final enabled = await isHealthSyncPermitted() == true;
    // A Settings action may have completed while the OS check was pending.
    final updated = prefs.getBool(_syncEnabledKey);
    if (updated != null) return updated;
    await prefs.setBool(_syncEnabledKey, enabled);
    return enabled;
  }

  /// Called only by the Settings switch. Disabling never changes OS permissions.
  Future<bool> setSyncEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.setBool(_syncEnabledKey, false);
      return false;
    }
    var granted = false;
    try {
      await _ensureConfigured();
      if (_isAndroid) {
        if (await isHealthConnectAvailable()) {
          granted = await _androidBridge.requestMindfulnessPermissions();
        }
      } else {
        granted = await health.requestAuthorization(
          [HealthDataType.MINDFULNESS],
          permissions: [HealthDataAccess.READ_WRITE],
        );
        // On iOS requestAuthorization reports that the sheet completed, not
        // whether access was granted. Check the observable write grant.
        granted = granted && await isHealthSyncPermitted() == true;
      }
    } catch (error) {
      AppLogger.e('HEALTH', 'Health permission request failed', error);
    }
    await prefs.setBool(_syncEnabledKey, granted);
    return granted;
  }

  Future<bool> isSessionSynced(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedSessions = prefs.getStringList('syncedSessions') ?? [];

    return syncedSessions.contains(timestamp.toString());
  }

  Future<void> markSessionAsSynced(int timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    final syncedSessions = prefs.getStringList('syncedSessions') ?? [];
    syncedSessions.add(timestamp.toString());
    await prefs.setStringList('syncedSessions', syncedSessions);
  }

  Future<bool> writeMindfulnessData(DateTime start, DateTime end) async {
    try {
      if (!await isSyncEnabled()) return false;
      if (await isHealthSyncPermitted() != true) {
        AppLogger.w(
          'HEALTH',
          'Skipping sync: Health permission is unavailable',
        );
        return false;
      }
      if (_isAndroid) {
        final written = await _androidBridge.writeMindfulnessSession(
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
        );
        if (!written) AppLogger.w('HEALTH', 'Health write failed');
        return written;
      }

      final written = await health.writeHealthData(
        value: 0,
        type: HealthDataType.MINDFULNESS,
        startTime: start,
        endTime: end,
        unit: HealthDataUnit.NO_UNIT,
        recordingMethod: RecordingMethod.automatic,
      );
      if (!written) AppLogger.w('HEALTH', 'Health write failed');
      return written;
    } catch (error) {
      AppLogger.e('HEALTH', 'Health write failed', error);
      return false;
    }
  }
}
