import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

/// Courses pinned to Home, oldest pin first. At most [maxPinned].
final pinnedCoursesProvider =
    NotifierProvider<PinnedCoursesNotifier, List<String>>(
      PinnedCoursesNotifier.new,
    );

class PinnedCoursesNotifier extends Notifier<List<String>> {
  static const maxPinned = 3;

  @override
  List<String> build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final saved = prefs.getStringList(SharedPreferenceConstants.pinnedCourseIds);
    if (saved != null) return saved.toSet().take(maxPinned).toList();
    // The one course Home used to continue becomes the first pin.
    final legacy = prefs.getString(SharedPreferenceConstants.upNextPackId);
    return legacy == null || legacy.isEmpty ? const [] : [legacy];
  }

  bool isPinned(String id) => state.contains(id);

  /// Pins [id]. False, changing nothing, when three are already pinned.
  Future<bool> pin(String id) async {
    if (state.contains(id)) return true;
    if (state.length >= maxPinned) return false;
    await _set([...state, id]);
    return true;
  }

  Future<void> unpin(String id) => _set([
    for (final p in state)
      if (p != id) p,
  ]);

  Future<void> _set(List<String> ids) async {
    state = ids;
    await ref
        .read(sharedPreferencesProvider)
        .setStringList(SharedPreferenceConstants.pinnedCourseIds, ids);
  }
}
