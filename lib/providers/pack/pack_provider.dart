import 'package:medito/constants/constants.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/services/dharma_seed/dharma_seed_ids.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/repositories/repositories.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pack_provider.g.dart';

@Riverpod(keepAlive: true)
Future<List<PackItemsModel>> fetchAllPacks(Ref ref) {
  var packRepository = ref.watch(packRepositoryProvider);
  return packRepository.fetchAllPacks().then(
    (packs) => packs.expand((pack) => pack.items).toList(),
  );
}

/// Track IDs of the packs that can show a completion tick, including
/// sub-packs: the whole local catalogue, plus each source's saved packs and
/// packs containing a completed track. Never a large source's every pack.
/// Empty on failure: a pack then simply shows no tick, never a wrong one.
@Riverpod(keepAlive: true)
Future<Map<String, List<String>>> packTrackIds(Ref ref) async {
  final checked = ref.watch(statsProvider).value?.tracksChecked;
  try {
    return await ref
        .read(packRepositoryProvider)
        .fetchPackTrackIds(startedTrackIds: {...?checked});
  } catch (_) {
    return const {};
  }
}

/// Ids of packs whose tracks are all completed. Completion is per track, so a
/// track shared by several packs counts towards each of them.
@Riverpod(keepAlive: true)
Set<String> completedPackIds(Ref ref) {
  final packTracks = ref.watch(packTrackIdsProvider).value ?? const {};
  final checked = ref.watch(statsProvider).value?.tracksChecked;
  if (packTracks.isEmpty || checked == null || checked.isEmpty) return const {};

  final completed = checked.toSet();
  return {
    for (final entry in packTracks.entries)
      if (entry.value.isNotEmpty && entry.value.every(completed.contains))
        entry.key,
  };
}

/// Raw pack read from the content repository. Refresh this provider for pull-to-refresh
/// or error-retry; it doesn't watch stats, so completion changes don't
/// trigger a re-fetch.
@Riverpod(keepAlive: true)
Future<PackModel> packData(Ref ref, {required String packId}) {
  if (packId.startsWith('yt-playlist-')) {
    ref.watch(youtubeContentRevisionProvider);
  } else if (packId.startsWith(dharmaSeedPrefix)) {
    ref.watch(dharmaSeedRevisionProvider);
  }
  return ref.read(packRepositoryProvider).fetchPacks(packId);
}

/// View-facing pack with per-item completion derived from local stats.
/// `build` returns an `AsyncValue` directly (synchronous notifier), so when
/// [statsProvider] fires the provider rebuilds without dropping into
/// `AsyncLoading` — the pack screen no longer flickers on return from the
/// player.
@Riverpod(keepAlive: true)
class Pack extends _$Pack {
  @override
  AsyncValue<PackModel> build({required String packId}) {
    final rawPack = ref.watch(packDataProvider(packId: packId));
    final stats = ref.watch(statsProvider);
    final completed = stats.value?.tracksChecked ?? const <String>[];
    final completedPacks = ref.watch(completedPackIdsProvider);

    PackModel withCompletion(PackModel pack) => pack.copyWith(
      items: pack.items
          .map(
            (item) => item.copyWith(
              isCompleted: item.type == TypeConstants.pack
                  ? completedPacks.contains(item.id)
                  : completed.contains(item.id),
            ),
          )
          .toList(),
    );

    // A background refresh re-reads the pack while the page is open. Keep
    // showing what is there rather than dropping to the loading placeholder,
    // which would rebuild the page and lose the scroll position.
    if (rawPack.isLoading && rawPack.hasValue) {
      return AsyncData(withCompletion(rawPack.requireValue));
    }
    return rawPack.whenData(withCompletion);
  }

  /// Sets a track's completion to an absolute value in local stats, then asks
  /// the stats provider to refresh from local. The refresh propagates here
  /// automatically via the [statsProvider] watch above.
  ///
  /// Returns `true` when the change was persisted, `false` on failure — the
  /// caller (the row's optimistic toggle) uses this to revert its UI.
  /// Taking an absolute `complete` rather than toggling keeps rapid repeated
  /// taps deterministic: each call states the desired end state outright.
  Future<bool> setIsComplete({
    required String trackId,
    required bool complete,
  }) async {
    try {
      final statsManager = ref.read(statsManagerProvider);
      await statsManager.initialize();
      if (!ref.mounted) return false;

      if (complete) {
        await statsManager.addTrackChecked(trackId);
      } else {
        await statsManager.removeTrackChecked(trackId);
      }
      if (!ref.mounted) return true;

      try {
        await ref.read(statsProvider.notifier).refreshFromLocal();
      } catch (_) {
        // Best-effort: even if stats refresh fails, the local change stuck.
      }
      // upNextProvider rebuilds reactively via packProvider <- statsProvider,
      // so no explicit refresh is needed here.
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marks every track in the pack complete (or clears them all) in one
  /// stats write. Backs the "mark all complete/incomplete" button.
  Future<void> markAll({required bool complete}) async {
    final pack = state.value;
    if (pack == null) return;

    final trackIds = pack.items
        .where((item) => item.type == TypeConstants.track)
        .map((item) => item.id)
        .toList();
    if (trackIds.isEmpty) return;

    final statsManager = ref.read(statsManagerProvider);
    await statsManager.initialize();
    if (!ref.mounted) return;

    await statsManager.setTracksChecked(trackIds, checked: complete);
    if (!ref.mounted) return;

    try {
      await ref.read(statsProvider.notifier).refreshFromLocal();
    } catch (_) {
      // Best-effort: the local toggle stuck even if the refresh failed.
    }
  }
}
