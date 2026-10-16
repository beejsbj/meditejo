import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/tags/tag_model.dart';
import 'package:medito/repositories/tags/tags_repository.dart';
import 'package:medito/services/local_catalogue.dart';

class _TagCatalogue extends LocalCatalogue {
  @override
  final tags = TagCatalog(
    tags: const [TagModel(id: 'rest', group: 'goal', description: 'Rest')],
    trackTags: const {
      'lib-session': ['rest'],
    },
  );
}

void main() {
  test('tags and tag tracks are empty without a backend', () async {
    final repo = TagsRepositoryImpl();
    final catalog = await repo.fetchCatalog();
    expect(catalog.tags, isEmpty);
    expect(catalog.trackTags, isEmpty);
    expect(await repo.fetchTracksForTag('sleep'), isEmpty);
    expect(await repo.fetchTracksForTag(''), isEmpty);
  });

  test('tags come from the injected local catalogue', () async {
    final repo = TagsRepositoryImpl(catalogue: _TagCatalogue());
    final catalog = await repo.fetchCatalog();
    expect(catalog.tags.single.id, 'rest');
    expect(catalog.tagsForTrack('lib-session').single.id, 'rest');
  });
}
