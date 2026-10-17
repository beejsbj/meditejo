import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/services/content/content_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:medito/utils/logger.dart';

final dharmaSeedDatabaseProvider = Provider<DharmaSeedDatabase>((ref) {
  final db = DharmaSeedDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final dharmaSeedClientProvider = Provider<DharmaSeedClient>((ref) {
  final client = DharmaSeedClient();
  ref.onDispose(client.close);
  return client;
});

final dharmaSeedSyncProvider = Provider<DharmaSeedSync>((ref) {
  final sync = DharmaSeedSync(
    db: ref.watch(dharmaSeedDatabaseProvider),
    client: ref.watch(dharmaSeedClientProvider),
  );
  ref.onDispose(sync.dispose);
  return sync;
});

final dharmaSeedSourceProvider = Provider<DharmaSeedSource>(
  (ref) => DharmaSeedSource(
    db: ref.watch(dharmaSeedDatabaseProvider),
    sync: ref.watch(dharmaSeedSyncProvider),
  ),
);

/// Every built-in or imported source, consulted by ID prefix. Later sources
/// (`lib-`, `yt-`) join this list.
final contentSourcesProvider = Provider<List<ContentSource>>(
  (ref) => [ref.watch(dharmaSeedSourceProvider)],
);

/// Live sync state for the settings row (in progress, last synced, failed).
final dharmaSeedSyncStatusProvider =
    NotifierProvider<_ValueListenableNotifier<DharmaSeedSyncStatus>, DharmaSeedSyncStatus>(
      () => _ValueListenableNotifier(
        (ref) => ref.watch(dharmaSeedSyncProvider).status,
      ),
    );

/// Changes after a sync pass alters stored records; watch it to re-query.
final dharmaSeedRevisionProvider =
    NotifierProvider<_ValueListenableNotifier<int>, int>(
      () => _ValueListenableNotifier(
        (ref) => ref.watch(dharmaSeedSyncProvider).revision,
      ),
    );

class _ValueListenableNotifier<T> extends Notifier<T> {
  _ValueListenableNotifier(this._select);

  final ValueListenable<T> Function(Ref ref) _select;

  @override
  T build() {
    final listenable = _select(ref);
    void listener() => state = listenable.value;
    listenable.addListener(listener);
    ref.onDispose(() => listenable.removeListener(listener));
    return listenable.value;
  }
}

/// Starts a background sync shortly after launch, without blocking startup.
/// Skipped when the last sync is recent and nothing is pending; offline, it
/// fails quietly and the app uses what is already stored.
Future<void> startDharmaSeedSync(
  WidgetRef ref, {
  Duration delay = const Duration(seconds: 3),
}) async {
  final sync = ref.read(dharmaSeedSyncProvider);
  try {
    await sync.loadStatus();
    await Future<void>.delayed(delay);
    await sync.sync();
  } catch (e, st) {
    AppLogger.e('DHARMA_SEED', 'Background sync did not start', e, st);
  }
}
