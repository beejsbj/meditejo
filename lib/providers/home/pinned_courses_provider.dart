import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/home/favourites_migration.dart';

/// What the user pinned to Home, oldest pin first: courses and playlists, and
/// single sessions. Home shows the first [PinnedCoursesNotifier.homeLimit];
/// the rest are under its "See all".
final pinnedCoursesProvider =
    NotifierProvider<PinnedCoursesNotifier, List<String>>(
      PinnedCoursesNotifier.new,
    );

class PinnedCoursesNotifier extends Notifier<List<String>> {
  /// How many pins Home shows before "See all".
  static const homeLimit = 3;

  /// The pins that are single sessions, not courses. Kept beside the list
  /// because a bundled catalogue's IDs do not say which they are.
  Set<String> _sessions = {};

  /// Titles kept from the favourites the pins were, for content now gone.
  Map<String, String> _titles = {};

  @override
  List<String> build() {
    final prefs = ref.read(sharedPreferencesProvider);
    _sessions = {
      ...?prefs.getStringList(SharedPreferenceConstants.pinnedSessionIds),
    };
    _titles = readPinnedTitles(prefs);
    final saved = prefs.getStringList(
      SharedPreferenceConstants.pinnedCourseIds,
    );
    if (saved != null) return saved.toSet().toList();
    // The one course Home used to continue becomes the first pin.
    final legacy = prefs.getString(SharedPreferenceConstants.upNextPackId);
    return legacy == null || legacy.isEmpty ? const [] : [legacy];
  }

  bool isPinned(String id) => state.contains(id);

  /// Whether the pin [id] is a single session rather than a course.
  bool isSession(String id) => _sessions.contains(id);

  /// The title [id] had when it was saved, if one was kept.
  String? savedTitle(String id) => _titles[id];

  /// Pins [id] last; [session] when it is a single session.
  Future<void> pin(String id, {bool session = false}) async {
    if (state.contains(id)) return;
    await _set([...state, id], session: session ? id : null);
  }

  /// Undo of [unpin]: pins [id] back before the first of the pins that
  /// followed it in [before] that is still pinned, else last. Undoing several
  /// unpins, in either order, restores the order they had.
  Future<void> pinBack(
    String id,
    List<String> before, {
    bool session = false,
  }) async {
    if (state.contains(id)) return;
    final after = before.skip(before.indexOf(id) + 1);
    final at = state.indexWhere(after.contains);
    await _set(
      [...state]..insert(at < 0 ? state.length : at, id),
      session: session ? id : null,
    );
  }

  Future<void> unpin(String id) => unpinAll([id]);

  /// Unpins every one of [ids] that is pinned, as when their content is
  /// deleted.
  Future<void> unpinAll(Iterable<String> ids) async {
    final gone = ids.toSet();
    if (!state.any(gone.contains)) return;
    await _set([
      for (final p in state)
        if (!gone.contains(p)) p,
    ]);
  }

  Future<void> _set(List<String> ids, {String? session}) async {
    _sessions = {
      for (final s in _sessions)
        if (ids.contains(s)) s,
      ?session,
    };
    final hadTitles = _titles.length;
    _titles = {
      for (final MapEntry(:key, :value) in _titles.entries)
        if (ids.contains(key)) key: value,
    };
    state = ids;
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setStringList(SharedPreferenceConstants.pinnedCourseIds, ids);
    await prefs.setStringList(
      SharedPreferenceConstants.pinnedSessionIds,
      _sessions.toList(),
    );
    if (_titles.length != hadTitles) {
      await prefs.setString(
        SharedPreferenceConstants.pinnedTitles,
        jsonEncode(_titles),
      );
    }
  }
}
