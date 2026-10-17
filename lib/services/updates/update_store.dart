import 'dart:convert';

import 'package:medito/services/updates/update_release.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the updater remembers between launches: when it last asked GitHub,
/// the ETag and release that answer carried, the version whose Home notice was
/// dismissed, and whether the install-permission explanation was shown.
class UpdateStore {
  UpdateStore(this._prefs);

  final SharedPreferences _prefs;

  static const _lastCheckedKey = 'update_last_checked_ms';
  static const _etagKey = 'update_etag';
  static const _releaseKey = 'update_release';
  static const _dismissedKey = 'update_dismissed_version_code';
  static const _explainedKey = 'update_permission_explained';

  DateTime? get lastCheckedAt {
    final ms = _prefs.getInt(_lastCheckedKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastCheckedAt(DateTime time) =>
      _prefs.setInt(_lastCheckedKey, time.millisecondsSinceEpoch);

  /// The ETag is only meaningful together with [release]; without a cached
  /// release a `304` would have nothing to reuse.
  String? get etag => release == null ? null : _prefs.getString(_etagKey);

  UpdateRelease? get release {
    final raw = _prefs.getString(_releaseKey);
    if (raw == null) return null;
    try {
      return UpdateRelease.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveRelease(UpdateRelease release, String? etag) async {
    await _prefs.setString(_releaseKey, jsonEncode(release.toJson()));
    if (etag == null) {
      await _prefs.remove(_etagKey);
    } else {
      await _prefs.setString(_etagKey, etag);
    }
  }

  Future<void> clearRelease() async {
    await _prefs.remove(_releaseKey);
    await _prefs.remove(_etagKey);
  }

  int? get dismissedVersionCode => _prefs.getInt(_dismissedKey);

  Future<void> dismissNotice(int versionCode) =>
      _prefs.setInt(_dismissedKey, versionCode);

  bool get permissionExplained => _prefs.getBool(_explainedKey) ?? false;

  Future<void> markPermissionExplained() => _prefs.setBool(_explainedKey, true);
}
