import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/services/dharma_seed/dharma_seed_models.dart';

/// The Explore chip in effect: Practice, Talks, or null for both. Tapping the
/// chosen chip again clears it.
final exploreGroupProvider =
    NotifierProvider<ExploreGroupNotifier, DsContentGroup?>(
      ExploreGroupNotifier.new,
    );

class ExploreGroupNotifier extends Notifier<DsContentGroup?> {
  @override
  DsContentGroup? build() => null;

  void toggle(DsContentGroup group) => state = state == group ? null : group;
}

/// Bumps whenever the user saves or unsaves a course or teacher, so lists
/// built from saved items re-read.
final savedRevisionProvider = NotifierProvider<_Counter, int>(_Counter.new);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Routes saves to the source that owns an ID.
final contentRouterProvider = Provider<ContentRouter>(
  (ref) => ContentRouter(sources: ref.watch(contentSourcesProvider)),
);

/// Whether a course or teacher is saved, with an optimistic toggle.
final savedProvider = AsyncNotifierProvider.autoDispose
    .family<SavedNotifier, bool, String>(SavedNotifier.new);

class SavedNotifier extends AsyncNotifier<bool> {
  SavedNotifier(this.id);

  final String id;

  @override
  Future<bool> build() => ref.read(contentRouterProvider).isSaved(id);

  Future<void> toggle() async {
    final saved = !(state.value ?? false);
    state = AsyncData(saved);
    try {
      await ref.read(contentRouterProvider).setSaved(id, saved: saved);
    } catch (_) {
      if (ref.mounted) state = AsyncData(!saved);
      return;
    }
    if (ref.mounted) ref.read(savedRevisionProvider.notifier).bump();
  }
}

/// The Explore tab's content. Re-reads when a sync pass lands records or the
/// user saves something; the previous result stays on screen meanwhile.
final dharmaSeedExploreProvider = FutureProvider.autoDispose
    .family<DsExplore, DsContentGroup?>((ref, group) {
      ref.watch(dharmaSeedRevisionProvider);
      ref.watch(savedRevisionProvider);
      return ref.watch(dharmaSeedSourceProvider).explore(group: group);
    });

typedef DsSearchKey = ({String query, SessionLength? length});

/// Grouped local search. The query is already debounced by the search field.
final dharmaSeedSearchProvider = FutureProvider.autoDispose
    .family<DsSearchResults, DsSearchKey>((ref, key) {
      // Re-run when a sync pass lands records, so a search made during the
      // first sync does not stay stale.
      ref.watch(dharmaSeedRevisionProvider);
      return ref
          .watch(dharmaSeedSourceProvider)
          .search(key.query, length: key.length);
    });

final dharmaSeedTeacherProvider = FutureProvider.autoDispose
    .family<DsTeacherPage, String>((ref, id) {
      ref.watch(dharmaSeedRevisionProvider);
      return ref.watch(dharmaSeedSourceProvider).teacherPage(id);
    });
