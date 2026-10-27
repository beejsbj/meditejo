import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/content/catalogue_merge.dart';
import 'package:medito/services/content/catalogue_source.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/utils/logger.dart';

/// The Explore chip in effect: Practice, Talks, or null for both. Tapping the
/// chosen chip again clears it.
final exploreGroupProvider =
    NotifierProvider<ExploreGroupNotifier, ContentGroup?>(
      ExploreGroupNotifier.new,
    );

class ExploreGroupNotifier extends Notifier<ContentGroup?> {
  @override
  ContentGroup? build() => null;

  void toggle(ContentGroup group) => state = state == group ? null : group;
}

/// Routes saves to the source that owns an ID.
final contentRouterProvider = Provider<ContentRouter>(
  (ref) => ContentRouter(sources: ref.watch(contentSourcesProvider)),
);

/// Whether a course, talk or teacher is in the library, with an optimistic
/// toggle.
final savedProvider = AsyncNotifierProvider.autoDispose
    .family<SavedNotifier, bool, String>(SavedNotifier.new);

class SavedNotifier extends AsyncNotifier<bool> {
  SavedNotifier(this.id);

  final String id;

  @override
  Future<bool> build() {
    // Re-read when the library changes elsewhere (a removal from its screen).
    ref.watch(libraryRevisionProvider);
    return ref.read(contentRouterProvider).isSaved(id);
  }

  Future<void> toggle() async {
    final saved = !(state.value ?? false);
    state = AsyncData(saved);
    try {
      await ref.read(contentRouterProvider).setSaved(id, saved: saved);
    } catch (_) {
      if (ref.mounted) state = AsyncData(!saved);
    }
  }
}

/// The built-in catalogues, in the order the source filter lists them.
final catalogueSourcesProvider = Provider<List<CatalogueSource>>(
  (ref) =>
      ref.watch(contentSourcesProvider).whereType<CatalogueSource>().toList(),
);

/// The source Explore is narrowed to: its ID prefix (`ds-`), or null for all
/// of them. Tapping the chosen source again clears it.
final exploreSourceProvider = NotifierProvider<ExploreSourceNotifier, String?>(
  ExploreSourceNotifier.new,
);

class ExploreSourceNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? prefix) => state = prefix == state ? null : prefix;
}

/// The catalogues Explore and search read now: the chosen source, or all.
final activeCataloguesProvider = Provider<List<CatalogueSource>>((ref) {
  final all = ref.watch(catalogueSourcesProvider);
  final chosen = ref.watch(exploreSourceProvider);
  final narrowed = [
    for (final source in all)
      if (source.prefix == chosen) source,
  ];
  return narrowed.isEmpty ? all : narrowed;
});

/// Changes after any catalogue lands records; watch it to re-query.
final catalogueRevisionProvider =
    NotifierProvider<CatalogueRevisionNotifier, int>(
      CatalogueRevisionNotifier.new,
    );

class CatalogueRevisionNotifier extends Notifier<int> {
  @override
  int build() {
    for (final source in ref.watch(catalogueSourcesProvider)) {
      void listener() => state = state + 1;
      source.revision.addListener(listener);
      ref.onDispose(() => source.revision.removeListener(listener));
    }
    return 0;
  }
}

/// Runs [read] on each of [sources] and keeps the answers that arrive: one
/// catalogue failing does not blank the others.
Future<List<R>> _readEach<R>(
  List<CatalogueSource> sources,
  Future<R> Function(CatalogueSource source) read,
) async {
  final parts = <R>[];
  for (final result in await Future.wait(
    sources.map((source) async {
      try {
        return await read(source);
      } catch (e) {
        AppLogger.w('EXPLORE', 'Skipped ${source.prefix}: $e');
        return null;
      }
    }),
  )) {
    if (result != null) parts.add(result);
  }
  return parts;
}

/// The Explore tab's content, from the chosen source or every catalogue,
/// merged. Re-reads when a refresh lands records or the user saves something;
/// the previous result stays on screen meanwhile.
final catalogueExploreProvider = FutureProvider.autoDispose
    .family<CatalogueExplore, ContentGroup?>((ref, group) async {
      ref.watch(catalogueRevisionProvider);
      ref.watch(libraryRevisionProvider);
      final parts = await _readEach(
        ref.watch(activeCataloguesProvider),
        (source) => source.explore(group: group),
      );
      return parts.isEmpty ? const CatalogueExplore() : mergeExplores(parts);
    });

typedef CatalogueSearchKey = ({String query, SessionLength? length});

/// Grouped local search over the chosen source or every catalogue. The query
/// is already debounced by the search field.
final catalogueSearchProvider = FutureProvider.autoDispose
    .family<CatalogueSearchResults, CatalogueSearchKey>((ref, key) async {
      // Re-run when a refresh lands records, so a search made during the
      // first sync does not stay stale.
      ref.watch(catalogueRevisionProvider);
      final parts = await _readEach(
        ref.watch(activeCataloguesProvider),
        (source) => source.search(key.query, length: key.length),
      );
      return parts.isEmpty
          ? const CatalogueSearchResults()
          : mergeSearches(parts);
    });

/// A teacher's page, from the catalogue that owns the teacher.
final catalogueTeacherProvider = FutureProvider.autoDispose
    .family<CatalogueTeacherPage, String>((ref, id) {
      ref.watch(catalogueRevisionProvider);
      return ref.watch(catalogueSourceForTeacherProvider(id)).teacherPage(id);
    });

/// The catalogue that owns teacher [id].
final catalogueSourceForTeacherProvider =
    Provider.family<CatalogueSource, String>((ref, id) {
      for (final source in ref.watch(catalogueSourcesProvider)) {
        if (source.ownsTeacher(id)) return source;
      }
      throw CatalogueEntryUnavailable('teacher', id);
    });

/// Called when the user opens Explore or Search: every catalogue fetches what
/// changed since its bundle (or the last time), without being waited for.
void catchUpCatalogues(WidgetRef ref, {bool force = false}) {
  for (final source in ref.read(catalogueSourcesProvider)) {
    unawaited(source.catchUp(force: force));
  }
}
