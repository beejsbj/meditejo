import 'package:medito/services/dhammatalks/dhammatalks_catalogue.dart';

/// A small dhammatalks.org snapshot in the bundled format: three evening
/// talks over two years, one morning talk, a guided-meditations course and a
/// Basics course (one of whose files the archive also holds).
Map<String, Object?> dhammatalksJson({
  String asOf = '2026-10-27T12:00:00Z',
}) => {
  'schema': 1,
  'asOf': asOf,
  'talks': [
    [
      'm',
      '261018-the-perfection-of-equanimity',
      'The Perfection of Equanimity',
      '2026-10-18',
      '/Archive/shorttalks/y2026/261018(short)_The_Perfection_of_Equanimity.mp3',
    ],
    [
      'e',
      '251231-an-auspicious-night',
      'An Auspicious Night',
      '2025-12-31',
      '/Archive/y2025/251231_An_Auspicious_Night.mp3',
    ],
    [
      'e',
      '251229-samadhi-and-mindfulness',
      'Samādhi & Mindfulness',
      '2025-12-29',
      '/Archive/y2025/251229_Samadhi_&_Mindfulness.mp3',
    ],
    [
      'e',
      '0308n3-anger',
      'Anger',
      '2003-08',
      '/Archive/y2003/0308n3a1 Anger.mp3',
    ],
  ],
  'courses': [
    {
      'id': 'guided',
      'title': 'Guided meditations',
      'description': 'Guided breath and metta meditations.',
      'group': 'practice',
      'page': '/mp3_guidedMed_index.html',
      'anchor': '',
      'items': [
        [
          'guided-01guidedmetta-4min',
          'Metta',
          '/Archive/guided_meditations/01GuidedMetta(4min).mp3',
          240,
        ],
        [
          'guided-05-guided-breath',
          'Breath (short version)',
          '/Archive/guided_meditations/05_Guided_Breath.mp3',
          720,
        ],
      ],
    },
    {
      'id': 'basics',
      'title': 'Basics',
      'description': 'A graduated series of talks for meditators.',
      'group': 'talks',
      'page': '/mp3_collections_index.html',
      'anchor': 'basics',
      'items': [
        [
          'basics-01-strength',
          'Strength from the Basics',
          '/Archive/basics_collection/01%20Strength.mp3',
          0,
        ],
        ['basics-anger', 'Anger', '/Archive/y2003/0308n3a1 Anger.mp3', 0],
      ],
    },
  ],
};

DtCatalogue dhammatalksCatalogue({String asOf = '2026-10-27T12:00:00Z'}) =>
    DtCatalogue.fromJson(dhammatalksJson(asOf: asOf));

/// A source with nothing in it, for tests of other screens.
DtCatalogue emptyDhammatalks() => DtCatalogue.fromJson({
  'schema': 1,
  'asOf': '2026-10-27T12:00:00Z',
  'talks': <Object?>[],
  'courses': <Object?>[],
});
