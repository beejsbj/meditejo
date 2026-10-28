import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_catalogue.dart';

String _asset({
  List<Map<String, Object?>>? curated,
  List<Map<String, Object?>>? rules,
  Object format = 1,
}) => jsonEncode({
  'format': format,
  'version': 3,
  'updated': '2026-10-27',
  'categories': [
    {
      'id': 'metta',
      'name': 'Metta',
      'aliases': ['Loving-kindness'],
    },
    {
      'id': 'jhana',
      'name': 'Jhāna',
      'aliases': ['Jhanas'],
    },
    {'id': 'body', 'name': 'Body'},
  ],
  'curated': curated ?? [],
  'rules': rules ?? [],
});

void main() {
  group('parse', () {
    test('reads categories, curated items and rules', () {
      final catalogue = CategoryCatalogue.parse(
        _asset(
          curated: [
            {
              'id': 'ds-retreat-1',
              'categories': ['metta'],
              'name': 'Retreat',
            },
          ],
          rules: [
            {
              'category': 'metta',
              'title': ['metta'],
            },
          ],
        ),
      );
      expect(catalogue.version, 3);
      expect(catalogue.categories.map((c) => c.id), ['metta', 'jhana', 'body']);
      expect(catalogue.curatedFor('ds-retreat-1'), ['metta']);
      expect(catalogue.curatedFor('ds-retreat-2'), isNull);
      expect(catalogue.curatedNames['ds-retreat-1'], 'Retreat');
      expect(catalogue.rulesFor('metta'), hasLength(1));
    });

    test('refuses a category nothing defines', () {
      expect(
        () => CategoryCatalogue.parse(
          _asset(
            curated: [
              {
                'id': 'ds-retreat-1',
                'categories': ['nope'],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => CategoryCatalogue.parse(
          _asset(
            rules: [
              {
                'category': 'nope',
                'title': ['x'],
              },
            ],
          ),
        ),
        throwsFormatException,
      );
    });

    test('refuses a layout from the future, and a repeated item', () {
      expect(
        () => CategoryCatalogue.parse(_asset(format: categoriesFormat + 1)),
        throwsFormatException,
      );
      expect(
        () => CategoryCatalogue.parse(
          _asset(
            curated: [
              {'id': 'ds-talk-1', 'categories': <String>[]},
              {'id': 'ds-talk-1', 'categories': <String>[]},
            ],
          ),
        ),
        throwsFormatException,
      );
    });
  });

  test('refuses a name or alias that names two categories', () {
    final json = jsonDecode(_asset()) as Map<String, dynamic>;
    (json['categories'] as List).add({
      'id': 'absorption',
      'name': 'Absorption',
      'aliases': ['Jhānas'],
    });
    expect(
      () => CategoryCatalogue.parse(jsonEncode(json)),
      throwsFormatException,
    );
  });

  group('categoryNamed', () {
    final catalogue = CategoryCatalogue.parse(_asset());

    test('finds a category by id, name or alias, ignoring case and marks', () {
      expect(catalogue.categoryNamed('Jhāna')?.id, 'jhana');
      expect(catalogue.categoryNamed('JHANAS')?.id, 'jhana');
      expect(catalogue.categoryNamed('loving kindness')?.id, 'metta');
      expect(catalogue.categoryNamed('metta')?.id, 'metta');
    });

    test('a label of the user\'s own is not a category', () {
      expect(catalogue.categoryNamed('retreat prep'), isNull);
    });
  });

  group('classify', () {
    final catalogue = CategoryCatalogue.parse(
      _asset(
        curated: [
          {
            'id': 'ds-retreat-1',
            'categories': ['jhana'],
          },
          {'id': 'ds-retreat-2', 'categories': <String>[]},
        ],
        rules: [
          {
            'category': 'metta',
            'title': ['metta', 'loving kindness'],
            'description': ['metta'],
          },
          {
            'category': 'jhana',
            'title': ['jhan*'],
          },
          {
            'category': 'body',
            'title': ['body'],
          },
        ],
      ),
    );

    List<String> ids(Iterable<CategoryAssignment> a) => [
      for (final x in a) x.id,
    ];

    test('the rules read the title', () {
      final result = catalogue.classify('ds-retreat-9', title: 'Mettā Retreat');
      expect(result, [const CategoryAssignment('metta', CategorySource.rule)]);
    });

    test('the rules read the description only where a rule says to', () {
      expect(
        ids(
          catalogue.classify(
            'ds-retreat-9',
            title: 'Retreat',
            description: 'We practise metta and body scans.',
          ),
        ),
        ['metta'],
      );
    });

    test('a curated entry replaces the rules, even an empty one', () {
      expect(catalogue.classify('ds-retreat-1', title: 'Metta Retreat'), [
        const CategoryAssignment('jhana', CategorySource.curated),
      ]);
      expect(
        catalogue.classify('ds-retreat-2', title: 'Metta Retreat'),
        isEmpty,
      );
    });

    test('a talk takes its retreat\'s categories and its own', () {
      const retreat = [CategoryAssignment('jhana', CategorySource.curated)];
      final result = catalogue.classify(
        'ds-talk-9',
        title: 'Body awareness',
        inherited: retreat,
      );
      expect(result, [
        const CategoryAssignment('jhana', CategorySource.curated),
        const CategoryAssignment('body', CategorySource.rule),
      ]);
    });

    test('a curated talk ignores its retreat', () {
      final withEntry = CategoryCatalogue.parse(
        _asset(
          curated: [
            {
              'id': 'ds-talk-5',
              'categories': ['body'],
            },
          ],
        ),
      );
      expect(
        ids(
          withEntry.classify(
            'ds-talk-5',
            inherited: const [
              CategoryAssignment('jhana', CategorySource.curated),
            ],
          ),
        ),
        ['body'],
      );
    });

    test('results follow the catalogue\'s order', () {
      expect(ids(catalogue.classify('x', title: 'Body and Jhāna and Metta')), [
        'metta',
        'jhana',
        'body',
      ]);
    });

    test('nothing matches nothing', () {
      expect(catalogue.classify('x', title: 'Dependent origination'), isEmpty);
    });
  });

  group('the model pass', () {
    String pass({
      Map<String, List<int>> categories = const {},
      List<int> none = const [],
      Object format = 1,
    }) => jsonEncode({
      'format': format,
      'version': 2,
      'categories': categories,
      'none': none,
    });

    final catalogue = CategoryCatalogue.parse(
      _asset(
        curated: [
          {
            'id': 'ds-retreat-1',
            'categories': ['metta'],
          },
        ],
        rules: [
          {
            'category': 'body',
            'title': ['body'],
          },
          {
            'category': 'metta',
            'title': ['metta'],
          },
        ],
      ),
      modelPass: pass(
        categories: {
          'jhana': [1, 2, 3],
          'body': [3],
        },
        none: [4],
      ),
    );

    test('reads each retreat\'s categories and its edition', () {
      expect(catalogue.passVersion, 2);
      expect(catalogue.modelFor('ds-retreat-3'), ['jhana', 'body']);
      expect(catalogue.modelFor('ds-retreat-4'), isEmpty);
      expect(catalogue.modelFor('ds-retreat-9'), isNull);
    });

    test('outranks the rules, and a retreat read as none stays none', () {
      expect(catalogue.classify('ds-retreat-2', title: 'Body and Metta'), [
        const CategoryAssignment('jhana', CategorySource.model),
      ]);
      expect(catalogue.classify('ds-retreat-4', title: 'Metta'), isEmpty);
      // Not read by the pass: the rules decide.
      expect(catalogue.classify('ds-retreat-9', title: 'Metta'), [
        const CategoryAssignment('metta', CategorySource.rule),
      ]);
    });

    test('is outranked by a hand-picked entry', () {
      expect(catalogue.classify('ds-retreat-1'), [
        const CategoryAssignment('metta', CategorySource.curated),
      ]);
      expect(catalogue.modelIn('jhana'), ['ds-retreat-2', 'ds-retreat-3']);
    });

    test('a talk takes its retreat\'s reading and adds its own matches', () {
      final retreat = catalogue.classify('ds-retreat-2');
      expect(
        catalogue.classify('ds-talk-7', title: 'Body scan', inherited: retreat),
        [
          const CategoryAssignment('jhana', CategorySource.model),
          const CategoryAssignment('body', CategorySource.rule),
        ],
      );
    });

    test('refuses a category nothing defines, or a newer layout', () {
      expect(
        () => CategoryCatalogue.parse(
          _asset(),
          modelPass: pass(
            categories: {
              'nope': [1],
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => CategoryCatalogue.parse(
          _asset(),
          modelPass: pass(format: categoriesFormat + 1),
        ),
        throwsFormatException,
      );
    });

    test('refuses a retreat both none and in a category, or listed twice', () {
      for (final bad in [
        pass(
          categories: {
            'jhana': [1],
          },
          none: [1],
        ),
        pass(
          categories: {
            'jhana': [1, 1],
          },
        ),
        pass(none: [2, 2]),
        jsonEncode({'format': 1, 'version': '2', 'categories': {}, 'none': []}),
        jsonEncode({
          'format': 1,
          'categories': {
            'jhana': ['1'],
          },
        }),
      ]) {
        expect(
          () => CategoryCatalogue.parse(_asset(), modelPass: bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('ranks between the rules and the hand-picked mapping', () {
      expect(CategorySource.model.outranks(CategorySource.rule), isTrue);
      expect(CategorySource.curated.outranks(CategorySource.model), isTrue);
      expect(CategorySource.user.outranks(CategorySource.curated), isTrue);
    });
  });
}
