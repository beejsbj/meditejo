import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/categories/category_text.dart';

void main() {
  group('foldWords', () {
    test('drops diacritics and case, and splits on punctuation', () {
      expect(foldWords('Jhāna & Insight — Day 3'), [
        'jhana',
        'insight',
        'day',
        '3',
      ]);
      expect(foldWords('Mettā/Lovingkindness'), ['metta', 'lovingkindness']);
      expect(foldWords('Ānāpānasati'), ['anapanasati']);
      expect(foldWords('Saṃsāra, Dhammapāda'), ['samsara', 'dhammapada']);
      expect(foldWords('Śūnyatā'), ['sunyata']);
    });

    test('treats hyphens and apostrophes as breaks', () {
      expect(foldWords('loving-kindness'), ['loving', 'kindness']);
    });

    test('empty and symbol-only text has no words', () {
      expect(foldWords(''), isEmpty);
      expect(foldWords('— & —'), isEmpty);
    });
  });

  group('CategoryTerm', () {
    bool hit(String term, String text) =>
        CategoryTerm.parse(term)!.matches(foldWords(text));

    test('matches whole words only', () {
      expect(hit('body', 'Mindfulness of the Body'), isTrue);
      expect(hit('body', 'Nobody knows'), isFalse);
      expect(hit('breath', 'Breathing like a Buddha'), isFalse);
    });

    test('matches a phrase across spellings and hyphens', () {
      expect(hit('loving kindness', 'Loving-Kindness Retreat'), isTrue);
      expect(hit('loving kindness', 'A loving, quiet kindness'), isFalse);
    });

    test('a trailing star makes the last word a prefix', () {
      expect(hit('jhan*', 'Jhānas and Insight'), isTrue);
      expect(hit('jhan*', 'Jhanna Retreat'), isTrue);
      expect(hit('jhan*', 'Who is John?'), isFalse);
      expect(hit('brahma vihara*', 'The Brahma Viharas'), isTrue);
    });

    test('a term with no words is not a term', () {
      expect(CategoryTerm.parse('*'), isNull);
      expect(CategoryTerm.parse('  '), isNull);
    });

    test('writes itself as an FTS5 phrase', () {
      expect(CategoryTerm.parse('Loving kindness')!.ftsPhrase,
          '"loving kindness"');
      expect(CategoryTerm.parse('Jhān*')!.ftsPhrase, '"jhan"*');
    });
  });
}
