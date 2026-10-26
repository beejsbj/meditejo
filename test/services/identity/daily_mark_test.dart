import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';

/// The exploration page's own daily picks for the first 40 days of 2026
/// (`Marks.daily`, round 2): day, seed, palette and the kind it draws.
const _page = <(String, String, String, String)>[
  ('2026-01-01', 'g-2026-01-01', 'clay', 'doorway'),
  ('2026-01-02', 'm-2026-01-02', 'tide', 'cushion'),
  ('2026-01-03', 'g-2026-01-03', 'riso', 'horizon'),
  ('2026-01-04', 'g-2026-01-04', 'dusk', 'doorway'),
  ('2026-01-05', 'g-2026-01-05', 'saffron', 'hearth'),
  ('2026-01-06', 'g-2026-01-06', 'ember', 'cushion'),
  ('2026-01-07', 'g-2026-01-07', 'sumi', 'path'),
  ('2026-01-08', 'g-2026-01-08', 'lagoon', 'enso'),
  ('2026-01-09', 'm-2026-01-09', 'forest', 'clearing'),
  ('2026-01-10', 'a-2026-01-10', 'clay', 'shoreline'),
  ('2026-01-11', 'g-2026-01-11', 'tide', 'window'),
  ('2026-01-12', 'g-2026-01-12', 'riso', 'horizon'),
  ('2026-01-13', 'a-2026-01-13', 'dusk', 'shoreline'),
  ('2026-01-14', 'm-2026-01-14', 'saffron', 'window'),
  ('2026-01-15', 'g-2026-01-15', 'ember', 'path'),
  ('2026-01-16', 'm-2026-01-16', 'sumi', 'split'),
  ('2026-01-17', 'g-2026-01-17', 'lagoon', 'path'),
  ('2026-01-18', 'g-2026-01-18', 'forest', 'cushion'),
  ('2026-01-19', 'm-2026-01-19', 'clay', 'hearth'),
  ('2026-01-20', 'm-2026-01-20', 'tide', 'shelter'),
  ('2026-01-21', 'm-2026-01-21', 'riso', 'split'),
  ('2026-01-22', 'm-2026-01-22', 'dusk', 'shelter'),
  ('2026-01-23', 'g-2026-01-23', 'saffron', 'cushion'),
  ('2026-01-24', 'g-2026-01-24', 'ember', 'hearth'),
  ('2026-01-25', 'a-2026-01-25', 'sumi', 'dawn'),
  ('2026-01-26', 'm-2026-01-26', 'lagoon', 'window'),
  ('2026-01-27', 'g-2026-01-27', 'forest', 'shelter'),
  ('2026-01-28', 'g-2026-01-28', 'clay', 'cushion'),
  ('2026-01-29', 'a-2026-01-29', 'tide', 'shoreline'),
  ('2026-01-30', 'm-2026-01-30', 'riso', 'window'),
  ('2026-01-31', 'm-2026-01-31', 'dusk', 'cushion'),
  ('2026-02-01', 'm-2026-02-01', 'saffron', 'crescent'),
  ('2026-02-02', 'm-2026-02-02', 'ember', 'hearth'),
  ('2026-02-03', 'g-2026-02-03', 'sumi', 'horizon'),
  ('2026-02-04', 'm-2026-02-04', 'lagoon', 'window'),
  ('2026-02-05', 'g-2026-02-05', 'forest', 'window'),
  ('2026-02-06', 'a-2026-02-06', 'clay', 'dawn'),
  ('2026-02-07', 'g-2026-02-07', 'tide', 'doorway'),
  ('2026-02-08', 'm-2026-02-08', 'riso', 'hearth'),
  ('2026-02-09', 'm-2026-02-09', 'dusk', 'cushion'),
];

DateTime _day(String key) => DateTime.parse(key);

void main() {
  test('every day picks the seed and palette the page picks', () {
    for (final (key, seed, palette, kind) in _page) {
      final pick = DailyMark.forDay(_day(key));
      expect(pick.key, key);
      expect(pick.seed, seed, reason: key);
      expect(pick.paletteId, palette, reason: key);
      expect(MarkGenerator.build(pick.seed).type, kind, reason: key);
    }
  });

  test('the date is the local calendar day, whatever the hour', () {
    final morning = DailyMark.forDay(DateTime(2026, 10, 26, 0, 0, 1));
    final night = DailyMark.forDay(DateTime(2026, 10, 26, 23, 59, 59));
    expect(morning.seed, 'm-2026-10-26');
    expect(night.seed, morning.seed);
    expect(morning.paletteId, 'tide');
  });

  test('the pick changes at local midnight', () {
    final before = DateTime(2026, 10, 26, 23, 59, 59, 999);
    final after = DateTime(2026, 10, 27);
    expect(DailyMark.forDay(before).seed, 'm-2026-10-26');
    expect(DailyMark.forDay(after).seed, 'g-2026-10-27');
    // Across a month and a year end.
    expect(DailyMark.dayKey(DateTime(2026, 11, 1)), '2026-11-01');
    expect(
      DailyMark.forDay(DateTime(2027, 1, 1)).key,
      isNot(DailyMark.forDay(DateTime(2026, 12, 31, 23, 59)).key),
    );
  });

  test('no palette repeats within nine days', () {
    final start = DateTime(2026, 3, 1);
    for (var d = 0; d < 60; d++) {
      final window = {
        for (var i = 0; i < 9; i++)
          DailyMark.forDay(start.add(Duration(days: d + i))).paletteId,
      };
      expect(window, hasLength(9));
    }
  });

  test('the double loop is retired from the daily pool', () {
    // On the page, 2026-02-17's gesture draws the double loop.
    expect(MarkGenerator.build('g-2026-02-17').type, 'loops');
    final pick = DailyMark.forDay(DateTime(2026, 2, 17));
    expect(pick.seed, 'g-2026-02-17-b');
    expect(MarkGenerator.build(pick.seed).type, 'shelter');
    for (var d = 0; d < 3000; d++) {
      final seed = DailyMark.forDay(DateTime(2026, 1, 1 + d)).seed;
      expect(MarkGenerator.build(seed).type, isNot('loops'), reason: seed);
    }
  });
}
