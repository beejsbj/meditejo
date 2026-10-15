import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/models.dart';
import 'package:medito/providers/home/up_next_provider.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/services/local_catalogue.dart';
import 'package:medito/views/previews/preview_support.dart';

class _FakePack extends Pack {
  _FakePack(this.initial);
  final AsyncValue<PackModel> initial;

  @override
  AsyncValue<PackModel> build({required String packId}) => initial;

  void update(AsyncValue<PackModel> value) => state = value;
}

PackModel _pack({int completed = 0, int total = 2}) => PackModel(
  id: 'lib-course',
  title: 'My course',
  items: List.generate(
    total,
    (i) => PackItemsModel(
      type: 'track',
      id: 'lib-session-$i',
      title: 'Session $i',
      path: '/tracks/lib-session-$i',
      isCompleted: i < completed,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer(AsyncValue<PackModel> pack) {
    final container = ProviderContainer(
      overrides: [
        upNextPackIdProvider.overrideWithValue('lib-course'),
        packProvider(packId: 'lib-course').overrideWith(() => _FakePack(pack)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('no saved pin means an empty home without requesting any pack', () {
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(MemoryPrefs({}))],
    );
    addTearDown(container.dispose);
    expect(container.read(upNextPackIdProvider), isEmpty);
    final data = container.read(upNextProvider).requireValue;
    expect(data.nextSession, isNull);
    expect(data.totalCount, 0);
    expect(data.isCompleted, isFalse);
  });

  test('resumes the first unfinished session of the pinned source course', () {
    final container = makeContainer(AsyncData(_pack(completed: 1)));
    final data = container.read(upNextProvider).requireValue;
    expect(data.nextSession?.id, 'lib-session-1');
    expect(data.completedCount, 1);
    expect(data.progressPercentage, 50);
  });

  test('completed courses do not seed a successor from the old catalogue', () {
    final data = makeContainer(
      AsyncData(_pack(completed: 2)),
    ).read(upNextProvider).requireValue;
    expect(data.isCompleted, isTrue);
    expect(data.nextSession, isNull);
    expect(data.nextPackId, isNull);
    expect(data.isEndOfPath, isFalse);
  });

  test('an empty source course does not dereference first', () {
    final data = makeContainer(
      AsyncData(_pack(total: 0)),
    ).read(upNextProvider).requireValue;
    expect(data.totalCount, 0);
    expect(data.nextSession, isNull);
    expect(data.isCompleted, isFalse);
  });

  test(
    'missing saved entries collapse to empty while sources are unavailable',
    () {
      final data = makeContainer(
        AsyncError(
          const CatalogueEntryUnavailable('pack', 'old-pin'),
          StackTrace.current,
        ),
      ).read(upNextProvider).requireValue;
      expect(data.nextSession, isNull);
      expect(data.totalCount, 0);
    },
  );

  test('loading and unexpected failures remain distinguishable', () {
    expect(
      makeContainer(const AsyncLoading()).read(upNextProvider).isLoading,
      isTrue,
    );
    final error = StateError('local read failed');
    expect(
      makeContainer(
        AsyncError(error, StackTrace.current),
      ).read(upNextProvider).error,
      same(error),
    );
  });

  test('completion updates reactively from local pack state', () {
    final container = makeContainer(AsyncData(_pack()));
    expect(
      container.read(upNextProvider).requireValue.nextSession?.id,
      'lib-session-0',
    );
    (container.read(packProvider(packId: 'lib-course').notifier) as _FakePack)
        .update(AsyncData(_pack(completed: 1)));
    expect(
      container.read(upNextProvider).requireValue.nextSession?.id,
      'lib-session-1',
    );
  });
}
