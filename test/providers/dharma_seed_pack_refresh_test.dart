import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/pack/pack_provider.dart';
import 'package:medito/repositories/repositories.dart';

class _CountingRepository extends PackRepositoryImpl {
  final fetched = <String>[];

  @override
  Future<PackModel> fetchPacks(String packId) async {
    fetched.add(packId);
    return PackModel(id: packId, title: 'Pack', items: const []);
  }
}

void main() {
  test('a Dharma Seed pack is read again after a catalogue sync', () async {
    final revision = ValueNotifier(0);
    final repository = _CountingRepository();
    final container = ProviderContainer(
      overrides: [
        packRepositoryProvider.overrideWithValue(repository),
        dharmaSeedRevisionProvider.overrideWith(
          () => ValueListenableNotifier((ref) => revision),
        ),
      ],
    );
    addTearDown(container.dispose);
    final dharma = packDataProvider(packId: 'ds-retreat-1');
    final other = packDataProvider(packId: 'x-course-a');
    container.listen(dharma, (_, _) {});
    container.listen(other, (_, _) {});
    await container.read(dharma.future);
    await container.read(other.future);

    revision.value = 1;
    await container.pump();
    await container.read(dharma.future);
    await container.read(other.future);

    expect(
      repository.fetched.where((id) => id == 'ds-retreat-1'),
      hasLength(2),
    );
    expect(repository.fetched.where((id) => id == 'x-course-a'), hasLength(1));
  });
}
