import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/models/favorites/favorite_item.dart';
import 'package:medito/providers/favorites/favorites_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/repositories/favorites/favorites_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

FavoriteItem _item(String id, int timestamp) => FavoriteItem(
  id: id,
  title: 'Title $id',
  type: FavoriteItemType.track,
  timestamp: timestamp,
);

/// Controls local write completion so the optimistic state can be observed.
class _FakeRepository implements FavoritesRepository {
  _FakeRepository({required this.local});

  List<FavoriteItem> local;
  bool failSaves = false;
  int saves = 0;
  Completer<void>? holdSave;

  @override
  Future<List<FavoriteItem>> loadFavorites() async => [...local];

  @override
  Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    saves++;
    if (holdSave != null) await holdSave!.future;
    if (failSaves) throw StateError('Local storage unavailable');
    local = [...favorites];
  }
}

class _FailingPreferences extends Fake implements SharedPreferences {
  _FailingPreferences(this.prefs, {this.throwOnSave = false});

  final SharedPreferences prefs;
  final bool throwOnSave;
  String? _cachedFailedValue;

  @override
  String? getString(String key) => _cachedFailedValue ?? prefs.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    // The plugin updates its in-memory cache even when the disk write fails.
    _cachedFailedValue = value;
    if (throwOnSave) throw StateError('Local storage unavailable');
    return false;
  }

  @override
  Future<void> reload() async {
    await prefs.reload();
    _cachedFailedValue = null;
  }
}

Future<ProviderContainer> _start(FavoritesRepository repo) async {
  final container = ProviderContainer(
    overrides: [favoritesRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  await container.read(favoritesNotifierProvider.future);
  return container;
}

List<String> _ids(ProviderContainer container) => container
    .read(favoritesNotifierProvider)
    .value!
    .map((item) => item.id)
    .toList();

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  Future<ProviderContainer> startWithPreferences() async {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await container.read(favoritesNotifierProvider.future);
    return container;
  }

  test(
    'first launch has no favorites and does not write preferences',
    () async {
      final container = await startWithPreferences();

      expect(_ids(container), isEmpty);
      expect(prefs.getKeys(), isEmpty);
    },
  );

  test('saves full track and pack records and reloads them locally', () async {
    final container = await startWithPreferences();
    final notifier = container.read(favoritesNotifierProvider.notifier);
    final track = _item('ds-1', 1);
    const pack = FavoriteItem(
      id: 'lib-course',
      title: 'Metta course',
      subtitle: 'Six sessions',
      coverUrl: 'https://example.org/cover.jpg',
      path: '/packs/lib-course',
      type: FavoriteItemType.pack,
      timestamp: 2,
    );

    await notifier.addToFavorites(track);
    await notifier.addToFavorites(pack);
    final expected = [track.toJson(), pack.toJson()];
    expect(
      jsonDecode(prefs.getString(SharedPreferenceConstants.favorites)!),
      expected,
    );
    expect(prefs.getKeys(), {SharedPreferenceConstants.favorites});

    await prefs.reload();
    final nextLaunch = await startWithPreferences();
    expect(
      nextLaunch
          .read(favoritesNotifierProvider)
          .value!
          .map((item) => item.toJson()),
      expected,
    );
  });

  test('loads existing favorites without rewriting local records', () async {
    final existing = jsonEncode([_item('ds-existing', 10).toJson()]);
    await prefs.setString(SharedPreferenceConstants.favorites, existing);

    final container = await startWithPreferences();

    expect(_ids(container), ['ds-existing']);
    expect(prefs.getString(SharedPreferenceConstants.favorites), existing);
  });

  test(
    'removal persists across reload and does not write tombstones',
    () async {
      final container = await startWithPreferences();
      final notifier = container.read(favoritesNotifierProvider.notifier);
      await notifier.addToFavorites(_item('a', 1));
      await notifier.addToFavorites(_item('b', 2));

      await notifier.removeFromFavorites('a');
      expect(_ids(container), ['b']);

      await prefs.reload();
      final nextLaunch = await startWithPreferences();
      expect(_ids(nextLaunch), ['b']);
      expect(prefs.getKeys(), {SharedPreferenceConstants.favorites});
    },
  );

  test('removing the last favorite stays empty after reload', () async {
    final container = await startWithPreferences();
    final notifier = container.read(favoritesNotifierProvider.notifier);
    await notifier.addToFavorites(_item('a', 1));

    await notifier.removeFromFavorites('a');
    expect(_ids(container), isEmpty);
    expect(prefs.getString(SharedPreferenceConstants.favorites), '[]');

    await prefs.reload();
    final nextLaunch = await startWithPreferences();
    expect(_ids(nextLaunch), isEmpty);
  });

  test('a removed favorite can be added again and reloaded', () async {
    final container = await startWithPreferences();
    final notifier = container.read(favoritesNotifierProvider.notifier);
    await notifier.addToFavorites(_item('a', 1));
    await notifier.removeFromFavorites('a');
    await notifier.addToFavorites(_item('a', 3));

    await prefs.reload();
    final nextLaunch = await startWithPreferences();
    expect(_ids(nextLaunch), ['a']);
    expect(
      nextLaunch.read(favoritesNotifierProvider).value!.single.timestamp,
      3,
    );
  });

  test('refresh reloads local preferences', () async {
    final container = await startWithPreferences();
    await prefs.setString(
      SharedPreferenceConstants.favorites,
      jsonEncode([_item('saved-locally', 5).toJson()]),
    );

    await container.read(favoritesNotifierProvider.notifier).refresh();

    expect(_ids(container), ['saved-locally']);
  });

  test('refresh can recover from invalid local data', () async {
    await prefs.setString(SharedPreferenceConstants.favorites, 'invalid json');
    final container = ProviderContainer(
      // Riverpod retries build failures by default, keeping .future pending.
      // Observe the failed load directly, then exercise the explicit retry.
      retry: (_, _) => null,
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(favoritesNotifierProvider.future),
      throwsA(isA<FormatException>()),
    );
    expect(container.read(favoritesNotifierProvider).hasError, isTrue);
    expect(
      container.read(favoritesNotifierProvider).error,
      isA<FormatException>(),
    );
    expect(
      prefs.getString(SharedPreferenceConstants.favorites),
      'invalid json',
      reason: 'A failed read must not overwrite the saved data',
    );

    await prefs.setString(
      SharedPreferenceConstants.favorites,
      jsonEncode([_item('recovered', 6).toJson()]),
    );
    await container.read(favoritesNotifierProvider.notifier).refresh();

    expect(_ids(container), ['recovered']);
    expect(container.read(favoritesNotifierProvider).hasError, isFalse);
    expect(
      container.read(favoritesNotifierProvider).value!.single.toJson(),
      _item('recovered', 6).toJson(),
    );
  });

  test('duplicate adds and missing removals do not save', () async {
    final repo = _FakeRepository(local: [_item('a', 1)]);
    final container = await _start(repo);
    final notifier = container.read(favoritesNotifierProvider.notifier);

    await notifier.addToFavorites(_item('a', 2));
    await notifier.removeFromFavorites('missing');

    expect(_ids(container), ['a']);
    expect(
      container.read(favoritesNotifierProvider).value!.single.timestamp,
      1,
    );
    expect(repo.saves, 0);
  });

  for (final remove in [false, true]) {
    final operation = remove ? 'remove' : 'add';

    test('$operation updates the UI before local save finishes', () async {
      final repo = _FakeRepository(local: [_item('a', 1)])
        ..holdSave = Completer<void>();
      final container = await _start(repo);
      final notifier = container.read(favoritesNotifierProvider.notifier);

      final pending = remove
          ? notifier.removeFromFavorites('a')
          : notifier.addToFavorites(_item('b', 2));
      expect(_ids(container), remove ? isEmpty : ['a', 'b']);
      expect(repo.local.map((item) => item.id), ['a']);

      repo.holdSave!.complete();
      await pending;
      expect(repo.local.map((item) => item.id), remove ? isEmpty : ['a', 'b']);
    });

    test('$operation rolls back when local persistence throws', () async {
      final repo = _FakeRepository(local: [_item('a', 1)])
        ..holdSave = Completer<void>()
        ..failSaves = true;
      final container = await _start(repo);
      final notifier = container.read(favoritesNotifierProvider.notifier);

      final pending = remove
          ? notifier.removeFromFavorites('a')
          : notifier.addToFavorites(_item('b', 2));
      expect(_ids(container), remove ? isEmpty : ['a', 'b']);

      repo.holdSave!.complete();
      await pending;
      expect(_ids(container), ['a']);
      expect(repo.local.map((item) => item.id), ['a']);

      final nextLaunch = await _start(repo);
      expect(_ids(nextLaunch), ['a']);
    });

    for (final throwOnSave in [false, true]) {
      final failure = throwOnSave ? 'throws' : 'returns false';
      test('$operation rolls back when SharedPreferences $failure', () async {
        await prefs.setString(
          SharedPreferenceConstants.favorites,
          jsonEncode([_item('a', 1).toJson()]),
        );
        final repo = FavoritesRepositoryImpl(
          prefs: _FailingPreferences(prefs, throwOnSave: throwOnSave),
        );
        final container = await _start(repo);
        final notifier = container.read(favoritesNotifierProvider.notifier);

        if (remove) {
          await notifier.removeFromFavorites('a');
        } else {
          await notifier.addToFavorites(_item('b', 2));
        }

        expect(_ids(container), ['a']);
        await notifier.refresh();
        expect(_ids(container), ['a']);
        await prefs.reload();
        final nextLaunch = await startWithPreferences();
        expect(_ids(nextLaunch), ['a']);
      });
    }
  }
}
