import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/repositories/pack/packs_repository.dart';
import 'package:medito/services/local_catalogue.dart';

class _Stats extends StatsNotifier {
  _Stats(this.checked);
  final List<String> checked;

  @override
  Future<LocalAllStats> build() async =>
      LocalAllStats.empty().copyWith(tracksChecked: checked);
}

class _PackCatalogue extends LocalCatalogue {
  _PackCatalogue(this.packTrackIds);

  @override
  final Map<String, List<String>> packTrackIds;
}

class _FakeRepo implements PackRepositoryImpl {
  _FakeRepo({this.packTracks = const {}, this.pack, this.error});
  final Map<String, List<String>> packTracks;
  final PackModel? pack;
  final Object? error;

  @override
  Future<Map<String, List<String>>> fetchPackTrackIds() async {
    if (error != null) throw error!;
    return packTracks;
  }

  @override
  Future<PackModel> fetchPacks(String packId) async => pack!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeRepo repo, List<String> checked) {
  final container = ProviderContainer(
    overrides: [
      packRepositoryProvider.overrideWithValue(repo),
      statsProvider.overrideWith(() => _Stats(checked)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<Set<String>> _completed(ProviderContainer container) async {
  container.listen(completedPackIdsProvider, (_, _) {});
  await container.read(packTrackIdsProvider.future);
  await container.read(statsProvider.future);
  return container.read(completedPackIdsProvider);
}

void main() {
  group('completedPackIdsProvider', () {
    test('ticks a pack only when all its tracks are checked', () async {
      final container = _container(
        _FakeRepo(
          packTracks: {
            'sleep': ['a', 'b'],
            'focus': ['b', 'c'],
          },
        ),
        ['a', 'b'],
      );

      expect(await _completed(container), {'sleep'});
    });

    test('a shared track counts towards every pack that has it', () async {
      final container = _container(
        _FakeRepo(
          packTracks: {
            'sleep': ['shared'],
            'rest': ['shared'],
          },
        ),
        ['shared'],
      );

      expect(await _completed(container), {'sleep', 'rest'});
    });

    test('never ticks a pack with no tracks', () async {
      final container = _container(_FakeRepo(packTracks: {'empty': []}), ['a']);

      expect(await _completed(container), isEmpty);
    });

    test('shows no ticks when the catalogue fails', () async {
      final container = _container(
        _FakeRepo(error: Exception('catalogue unavailable')),
        ['a'],
      );

      expect(await _completed(container), isEmpty);
    });
  });

  test('packProvider marks completed sub-pack rows', () async {
    final container = _container(
      _FakeRepo(
        packTracks: {
          'done': ['a'],
          'todo': ['b'],
        },
        pack: const PackModel(
          id: 'parent',
          title: 'Parent',
          items: [
            PackItemsModel(
              type: TypeConstants.pack,
              id: 'done',
              title: 'Done',
              path: '/packs/done',
            ),
            PackItemsModel(
              type: TypeConstants.pack,
              id: 'todo',
              title: 'Todo',
              path: '/packs/todo',
            ),
            PackItemsModel(
              type: TypeConstants.track,
              id: 'a',
              title: 'A',
              path: '/tracks/a',
            ),
          ],
        ),
      ),
      ['a'],
    );
    container.listen(packProvider(packId: 'parent'), (_, _) {});
    await container.read(packDataProvider(packId: 'parent').future);
    await _completed(container);

    final items = container.read(packProvider(packId: 'parent')).value!.items;
    expect(items.map((i) => i.isCompleted), [true, false, true]);
  });

  test('fetchPackTrackIds uses the injected local catalogue map', () async {
    final catalogue = _PackCatalogue({
      'lib-course': ['lib-session-a', 'lib-session-b'],
      'lib-empty': [],
    });
    final repo = PackRepositoryImpl(catalogue: catalogue);

    expect(await repo.fetchPackTrackIds(), {
      'lib-course': ['lib-session-a', 'lib-session-b'],
      'lib-empty': [],
    });
  });
}
