import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/providers/library/library_providers.dart';
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
    library: ref.watch(libraryStoreProvider),
  ),
);

/// Every built-in or imported source, consulted by ID prefix. Later sources
/// (`yt-`) join this list.
final contentSourcesProvider = Provider<List<ContentSource>>(
  (ref) => [ref.watch(dharmaSeedSourceProvider), ref.watch(libSourceProvider)],
);

/// Live sync state for the settings row (in progress, last synced, failed).
final dharmaSeedSyncStatusProvider =
    NotifierProvider<
      ValueListenableNotifier<DharmaSeedSyncStatus>,
      DharmaSeedSyncStatus
    >(
      () => ValueListenableNotifier(
        (ref) => ref.watch(dharmaSeedSyncProvider).status,
      ),
    );

/// Changes after a sync pass alters stored records; watch it to re-query.
final dharmaSeedRevisionProvider =
    NotifierProvider<ValueListenableNotifier<int>, int>(
      () => ValueListenableNotifier(
        (ref) => ref.watch(dharmaSeedSyncProvider).revision,
      ),
    );

/// Exposes a [ValueListenable] owned by a service as provider state.
class ValueListenableNotifier<T> extends Notifier<T> {
  ValueListenableNotifier(this._select);

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

/// At launch: reads the catalogue's state, which unpacks the catalogue bundled
/// with the app on the first run. Nothing here uses the network; the sync that
/// fetches what changed since the bundle waits for the user to open Search or
/// Explore ([catchUpDharmaSeed]).
Future<void> prepareDharmaSeed(WidgetRef ref) async {
  try {
    await ref.read(dharmaSeedSyncProvider).loadStatus();
  } catch (e, st) {
    AppLogger.e('DHARMA_SEED', 'Could not read the catalogue state', e, st);
  }
}

/// Called when the user opens Search or Explore: fetches what Dharma Seed
/// changed since the bundled catalogue (or the last time), a few small
/// requests, without waiting for them. Skipped when the last sync is under 12
/// hours old; offline, it fails quietly and the stored catalogue is used.
void catchUpDharmaSeed(WidgetRef ref) {
  unawaited(ref.read(dharmaSeedSyncProvider).sync());
}
