import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/my_courses/my_course_models.dart';

import 'dart:convert';
import 'package:medito/constants/strings/shared_preference_constants.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';

class CueSettingsStore {
  CueSettingsStore(this.prefs);
  final SharedPreferences prefs;
  String _key(CueScope scope) => scope.courseId == null
      ? 'cues.v1.${scope.kind.name}'
      : 'cues.v1.${scope.kind.name}.course.${scope.courseId}';
  bool hasOverride(CueScope scope) =>
      scope.courseId != null && prefs.containsKey(_key(scope));
  CueSettings read(CueScope scope) {
    final own = prefs.getString(_key(scope));
    final saved = own ?? prefs.getString(_key(CueScope(scope.kind)));
    var settings = CueSettings.decode(saved, scope.kind);
    // Preserve the user's old timer length on the first Customize visit.
    if (saved == null && scope.kind == CueKind.practice) {
      final minutes = prefs.getInt(SharedPreferenceConstants.timerMinutes);
      if (minutes != null) {
        settings = settings.copyWith(durationMinutes: minutes);
      }
    }
    return settings;
  }

  Future<void> save(CueScope scope, CueSettings settings) async {
    await prefs.setString(_key(scope), jsonEncode(settings.toJson()));
  }

  /// Moves every stored scope's cues that ring bell [from] to bell [to]:
  /// what happens to the cues of a bell when it is deleted.
  Future<void> replaceSound(String from, String to) async {
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith('cues.v1.')) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) continue;
        var changed = false;
        for (final field in const ['startSound', 'intervalSound', 'endSound']) {
          if (decoded[field] == from) {
            decoded[field] = to;
            changed = true;
          }
        }
        if (changed) await prefs.setString(key, jsonEncode(decoded));
      } catch (_) {
        // A value that doesn't decode is read as defaults anyway.
      }
    }
  }

  Future<void> removeOverride(CueScope scope) async {
    if (scope.courseId != null) await prefs.remove(_key(scope));
  }
}

final cueSettingsStoreProvider = Provider<CueSettingsStore>(
  (ref) => CueSettingsStore(ref.watch(sharedPreferencesProvider)),
);
final cueSettingsProvider =
    NotifierProvider.family<CueSettingsNotifier, CueSettings, CueScope>(
      CueSettingsNotifier.new,
    );

class CueSettingsNotifier extends Notifier<CueSettings> {
  CueSettingsNotifier(this.scope);
  final CueScope scope;
  @override
  CueSettings build() => ref.watch(cueSettingsStoreProvider).read(scope);
  Future<void> update(CueSettings value, {bool courseOverride = false}) async {
    state = value;
    final target = courseOverride ? scope : CueScope(scope.kind);
    await ref.read(cueSettingsStoreProvider).save(target, value);
    ref.invalidate(cueSettingsProvider);
  }

  Future<void> clearOverride() async {
    await ref.read(cueSettingsStoreProvider).removeOverride(scope);
    state = ref.read(cueSettingsStoreProvider).read(scope);
  }
}

/// Resolved once at session start so a library refresh cannot switch defaults
/// halfway through a sit. A course classification overrides recording labels.
///
/// The course is the personal course the session was opened from, while that
/// course still lists it (a session can sit in several, and in none at its
/// source, like an imported file); else the course its source names.
final cueScopeForRequestProvider =
    FutureProvider.family<CueScope, PlaybackRequest>((ref, request) async {
      if (request.isTimer) return const CueScope(CueKind.practice);
      final sources = ref.read(contentSourcesProvider);
      final router = ContentRouter(sources: sources);
      final store = ref.read(libraryStoreProvider);
      final opened = await store.sessionContext(request.trackId);
      final inOpened =
          opened != null &&
          isMyCourseId(opened) &&
          (await ref
                  .read(myCourseSourceProvider)
                  .coursesHolding(request.trackId))
              .contains(opened);
      final parent = inOpened ? opened : await router.parentOf(request.trackId);
      final group =
          (parent == null ? null : await store.groupOf(parent)) ??
          await store.groupOf(request.trackId);
      final kind = group == null
          ? (request.hasBackgroundSound ? CueKind.practice : CueKind.talks)
          : group == LibraryGroup.practice
          ? CueKind.practice
          : CueKind.talks;
      return CueScope(kind, courseId: parent);
    });
