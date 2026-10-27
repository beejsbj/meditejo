import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/services/content/catalogue_merge.dart';

PackItemsModel item(String id, {String type = 'track'}) =>
    PackItemsModel(type: type, id: id, title: id, path: '/$id');

CatalogueTeacher teacher(String id, int talks) =>
    CatalogueTeacher(id: id, name: id, talkCount: talks);

void main() {
  test('interleave alternates and keeps each list in order', () {
    expect(
      interleave([
        ['a1', 'a2', 'a3'],
        ['b1'],
        ['c1', 'c2'],
      ]),
      ['a1', 'b1', 'c1', 'a2', 'c2', 'a3'],
    );
    expect(interleave<String>([]), isEmpty);
  });

  test('interleave drops a repeat by key', () {
    expect(
      interleave([
        ['x', 'y'],
        ['x', 'z'],
      ], key: (s) => s),
      ['x', 'y', 'z'],
    );
  });

  test(
    'explores merge: courses and talks alternate, busiest teachers lead',
    () {
      final merged = mergeExplores([
        CatalogueExplore(
          courses: [
            item('ds-1', type: 'pack'),
            item('ds-2', type: 'pack'),
          ],
          talks: [item('ds-t1')],
          teachers: [teacher('ds-a', 50), teacher('ds-b', 10)],
          savedTeachers: [teacher('ds-s', 1)],
          hasCatalogue: false,
        ),
        CatalogueExplore(
          courses: [item('dt-1', type: 'pack')],
          talks: [item('dt-t1'), item('dt-t2')],
          teachers: [teacher('dt-a', 5000)],
          archives: [item('dt-year-e-2025', type: 'pack')],
          hasCatalogue: true,
        ),
      ]);
      expect(merged.courses.map((c) => c.id), ['ds-1', 'dt-1', 'ds-2']);
      expect(merged.talks.map((c) => c.id), ['ds-t1', 'dt-t1', 'dt-t2']);
      expect(merged.teachers.map((t) => t.id), ['dt-a', 'ds-a', 'ds-b']);
      expect(merged.savedTeachers.map((t) => t.id), ['ds-s']);
      expect(merged.archives.map((a) => a.id), ['dt-year-e-2025']);
      expect(
        merged.hasCatalogue,
        isTrue,
        reason: 'one catalogue that has loaded is enough',
      );
    },
  );

  test('one source passes through untouched', () {
    final only = CatalogueExplore(courses: [item('ds-1', type: 'pack')]);
    expect(identical(mergeExplores([only]), only), isTrue);
    const hits = CatalogueSearchResults();
    expect(identical(mergeSearches([hits]), hits), isTrue);
  });

  test('searches merge group by group', () {
    final merged = mergeSearches([
      CatalogueSearchResults(
        teachers: [teacher('ds-a', 1)],
        courses: [item('ds-1', type: 'pack')],
        talks: [item('ds-t1'), item('ds-t2')],
      ),
      CatalogueSearchResults(
        teachers: [teacher('dt-a', 1)],
        talks: [item('dt-t1')],
      ),
    ]);
    expect(merged.teachers.map((t) => t.id), ['ds-a', 'dt-a']);
    expect(merged.courses.map((t) => t.id), ['ds-1']);
    expect(merged.talks.map((t) => t.id), ['ds-t1', 'dt-t1', 'ds-t2']);
  });
}
