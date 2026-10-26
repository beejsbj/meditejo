import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/identity/seeded_random.dart';

/// Today's mark and today's palette, from the local date alone (`marks.js`
/// `daily`). Nothing is stored: every day knows its own.
class DailyPick {
  const DailyPick({
    required this.key,
    required this.seed,
    required this.paletteId,
  });

  /// The local day, `YYYY-MM-DD`.
  final String key;

  /// The mark's seed: the family's prefix and the date, e.g. `m-2026-10-26`
  /// (see [DailyMark.forDay] for the one exception).
  final String seed;
  final String paletteId;
}

abstract final class DailyMark {
  /// The family's weights on a given day, as on the page.
  static const familyWeights = {'gesture': 0.45, 'minimal': 0.4, 'atmos': 0.15};

  /// Local `YYYY-MM-DD` of [d].
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Days since the epoch of [d]'s local calendar date.
  static int dayNumber(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

  /// The pick for [d]'s local day.
  static DailyPick forDay(DateTime d) {
    final key = dayKey(d);
    final family = SeededRandom('day:$key').weighted(familyWeights);
    final prefix = MarkFamily.values.byName(family).prefix;
    return DailyPick(
      key: key,
      seed: _retireLoops('$prefix-$key'),
      paletteId: paletteFor(d).id,
    );
  }

  /// The daily palette: one fixed shuffle of the palettes, walked a day at a
  /// time, so none repeats within nine days.
  static IdentityPalette paletteFor(DateTime d) {
    const palettes = IdentityPalettes.all;
    final order = [for (var i = 0; i < palettes.length; i++) i];
    final r = SeededRandom('palette-order');
    for (var i = order.length - 1; i > 0; i--) {
      final j = (r.next() * (i + 1)).floor();
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    return palettes[order[dayNumber(d) % palettes.length]];
  }

  /// The double loop (round 1's Duet-like mark) is retired from the daily
  /// pool (decision 21). A day whose gesture would draw it takes the seed
  /// with `-b` added instead, still a valid page seed, so the page can show
  /// it too. Explicit seeds still draw loops.
  static String _retireLoops(String seed) {
    var s = seed;
    while (MarkFamily.ofSeed(s) == MarkFamily.gesture &&
        MarkGenerator.build(s).type == 'loops') {
      s = '$s-b';
    }
    return s;
  }

  /// The next local midnight after [now], when today's pick changes.
  static DateTime nextMidnight(DateTime now) =>
      DateTime(now.year, now.month, now.day + 1);
}
