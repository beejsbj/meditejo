import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';
import 'package:medito/services/categories/entry_labels.dart';

final _catalogue = CategoryCatalogue.parse('''
{"format": 1, "version": 1, "updated": "x",
 "categories": [
  {"id": "metta", "name": "Metta"},
  {"id": "jhana", "name": "Jhāna"},
  {"id": "body", "name": "Body"}],
 "curated": [], "rules": []}
''');

void main() {
  const rule = CategorySource.rule;

  test('without the user, the guesses stand', () {
    final labels = resolveLabels(
      _catalogue,
      automatic: const [CategoryAssignment('metta', rule)],
    );
    expect(labels.categories, [const CategoryAssignment('metta', rule)]);
    expect(labels.custom, isEmpty);
  });

  test('an excluded category comes off, whatever the source', () {
    final labels = resolveLabels(
      _catalogue,
      automatic: const [
        CategoryAssignment('metta', rule),
        CategoryAssignment('body', CategorySource.curated),
      ],
      user: const UserLabels(excluded: {'metta', 'body'}),
    );
    expect(labels.categories, isEmpty);
  });

  test('an added category outranks the guess for the same one', () {
    final labels = resolveLabels(
      _catalogue,
      automatic: const [CategoryAssignment('jhana', rule)],
      user: const UserLabels(added: {'jhana': '', 'body': ''}),
    );
    expect(labels.categories, [
      const CategoryAssignment('jhana', CategorySource.user),
      const CategoryAssignment('body', CategorySource.user),
    ]);
    expect(labels.userChose('jhana'), isTrue);
    expect(labels.userChose('metta'), isFalse);
  });

  test('a label of the user\'s own is kept as typed, in order', () {
    final labels = resolveLabels(
      _catalogue,
      user: UserLabels(
        added: {
          customLabelKey('retreat prep'): 'Retreat prep',
          customLabelKey('Evening'): 'Evening',
        },
      ),
    );
    expect(labels.custom, ['Evening', 'Retreat prep']);
    expect(labels.hasCustom('retreat  PREP!'), isTrue);
    expect(labels.hasCustom('morning'), isFalse);
  });

  test('categories stay in the catalogue\'s order', () {
    final labels = resolveLabels(
      _catalogue,
      automatic: const [CategoryAssignment('body', rule)],
      user: const UserLabels(added: {'metta': ''}),
    );
    expect(labels.categories.map((c) => c.id), ['metta', 'body']);
  });

  test('customLabelKey folds case, marks and spacing', () {
    expect(customLabelKey('Mettā  Practice!'), 'metta-practice');
    expect(customLabelKey('  '), '');
    expect(customLabelKey(' ध्यान '), 'ध्यान');
  });
}
