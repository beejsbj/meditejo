import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/home/continue_rules.dart';

/// What the user took off Home's Continue, and when. An item stays off until
/// it is played again after that: a course by its id (it shows once, whatever
/// session it is up to), a lone session by its own.
final continueDismissedProvider =
    NotifierProvider<ContinueDismissedNotifier, Map<String, int>>(
      ContinueDismissedNotifier.new,
    );

String continueKeyOf(ContinueItem item) => item.courseId ?? item.trackId;

class ContinueDismissedNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    final saved = ref
        .read(sharedPreferencesProvider)
        .getStringList(SharedPreferenceConstants.continueDismissed);
    return {
      for (final entry in saved ?? const <String>[])
        if (entry.lastIndexOf('|') > 0)
          entry.substring(0, entry.lastIndexOf('|')):
              int.tryParse(entry.substring(entry.lastIndexOf('|') + 1)) ?? 0,
    };
  }

  /// The most remembered: the oldest go first, so the list cannot grow for
  /// ever.
  static const maxKept = 50;

  Future<void> dismiss(String key, {DateTime? now}) {
    final next = {...state}..remove(key);
    next[key] = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (next.length > maxKept) {
      final oldest = next.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in oldest.take(next.length - maxKept)) {
        next.remove(e.key);
      }
    }
    return _set(next);
  }

  /// Undo of [dismiss]: puts back what [key] was before, or forgets it.
  Future<void> restore(String key, int? before) {
    final next = {...state}..remove(key);
    if (before != null) next[key] = before;
    return _set(next);
  }

  Future<void> _set(Map<String, int> next) async {
    state = next;
    await ref.read(sharedPreferencesProvider).setStringList(
      SharedPreferenceConstants.continueDismissed,
      [for (final e in next.entries) '${e.key}|${e.value}'],
    );
  }
}
