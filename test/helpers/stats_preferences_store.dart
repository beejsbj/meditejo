import 'package:shared_preferences/shared_preferences.dart';
// Exercise the real legacy preferences cache against controlled platform writes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class StatsPreferencesStore extends InMemorySharedPreferencesStore {
  StatsPreferencesStore(Map<String, Object> values)
    : super.withData({
        for (final entry in values.entries) 'flutter.${entry.key}': entry.value,
      });

  Future<bool> Function(
    String key,
    Object value,
    Future<bool> Function() persist,
  )?
  onWrite;
  Future<bool> Function(String key, Future<bool> Function() persist)? onRemove;
  bool failReads = false;

  static StatsPreferencesStore install(Map<String, Object> values) {
    SharedPreferences.setMockInitialValues({});
    final store = StatsPreferencesStore(values);
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final override = onWrite;
    if (override != null) {
      return override(key, value, () => super.setValue(valueType, key, value));
    }
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) {
    final override = onRemove;
    if (override != null) return override(key, () => super.remove(key));
    return super.remove(key);
  }

  @override
  Future<Map<String, Object>> getAll() {
    if (failReads) throw StateError('Platform read failed');
    return super.getAll();
  }
}
