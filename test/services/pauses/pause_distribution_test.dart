import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pauses/media_spans.dart';
import 'package:medito/services/pauses/pause_distribution.dart';

MediaSpan _silence(int startS, int lengthS) =>
    MediaSpan(startS * 1000, (startS + lengthS) * 1000, MediaSpanKind.silence);

void main() {
  const minute = 60000;

  group('usablePauses', () {
    test('keeps silence of at least ten seconds, in order', () {
      final map = MediaSpanMap(
        durationMs: 600000,
        spans: [_silence(300, 12), _silence(100, 9), _silence(60, 10)],
      );
      expect(usablePauses(map).map((p) => p.startMs), [60000, 300000]);
    });

    test('ignores the quiet at the very start and end of the file', () {
      final map = MediaSpanMap(
        durationMs: 600000,
        spans: [_silence(0, 20), _silence(200, 15), _silence(580, 20)],
      );
      expect(usablePauses(map).map((p) => p.startMs), [200000]);
    });
  });

  group('distributeExtension', () {
    test('with no pause everything goes to the end', () {
      final d = distributeExtension(totalMs: 10 * minute, pauses: const []);
      expect(d.holds, isEmpty);
      expect(d.remainderMs, 10 * minute);
    });

    test('pauses under the threshold are not used', () {
      final d = distributeExtension(
        totalMs: 5 * minute,
        pauses: [_silence(100, 9), _silence(200, 5)],
      );
      expect(d.holds, isEmpty);
      expect(d.remainderMs, 5 * minute);
    });

    test('nothing to extend gives nothing', () {
      final d = distributeExtension(totalMs: 0, pauses: [_silence(100, 20)]);
      expect(d.holds, isEmpty);
      expect(d.remainderMs, 0);
    });

    test('is weighted by pause length and holds at the midpoint', () {
      final d = distributeExtension(
        totalMs: 4 * minute,
        pauses: [_silence(100, 10), _silence(200, 30)],
      );
      expect(d.holds, [
        const PauseHold(105000, 60000),
        const PauseHold(215000, 180000),
      ]);
      expect(d.remainderMs, 0);
    });

    test('the sum of holds and remainder is always the total', () {
      for (final total in [1, 10, 17, 90, 333, 600, 3600]) {
        final d = distributeExtension(
          totalMs: total * 1000,
          pauses: [
            for (var i = 0; i < 23; i++) _silence(1300 + i * 60, 10 + i),
          ],
        );
        expect(d.heldMs + d.remainderMs, total * 1000, reason: '$total s');
        for (final h in d.holds) {
          expect(h.holdMs % 1000, 0);
          expect(h.holdMs, greaterThanOrEqualTo(defaultMinHoldMs));
        }
      }
    });

    test('a few minutes go to the longest pauses only', () {
      // 30 s of extension: room for three 10 s holds, in the three longest.
      final d = distributeExtension(
        totalMs: 30000,
        pauses: [
          _silence(100, 10),
          _silence(200, 40),
          _silence(300, 11),
          _silence(400, 30),
          _silence(500, 20),
        ],
      );
      expect(d.holds.map((h) => h.atMs), [220000, 415000, 510000]);
      for (final h in d.holds) {
        expect(h.holdMs, greaterThanOrEqualTo(10000));
      }
      expect(d.heldMs + d.remainderMs, 30000);
    });

    test('a pause whose share is too small is dropped, not squeezed', () {
      // 25 s: two holds are allowed, but by weight the 10 s pause would
      // get ~5 s, so it drops and the 90 s one takes it all.
      final d = distributeExtension(
        totalMs: 25000,
        pauses: [_silence(100, 10), _silence(200, 90)],
      );
      expect(d.holds, [const PauseHold(245000, 25000)]);
      expect(d.remainderMs, 0);
    });

    test('under ten seconds of extension stays at the end', () {
      final d = distributeExtension(
        totalMs: 9000,
        pauses: [_silence(100, 30)],
      );
      expect(d.holds, isEmpty);
      expect(d.remainderMs, 9000);
    });

    test('no pause takes more than the cap; the rest is shared again', () {
      final d = distributeExtension(
        totalMs: 12 * minute,
        pauses: [_silence(100, 10), _silence(200, 300)],
        maxHoldMs: 5 * minute,
      );
      // The long pause would get ~11.6 min: it takes 5, the other the rest.
      expect(d.holds.last.holdMs, 5 * minute);
      expect(d.holds.first.holdMs, 7 * minute);
      expect(d.remainderMs, 0);
    });

    test('when every pause is capped the remainder goes to the end', () {
      final d = distributeExtension(
        totalMs: 60 * minute,
        pauses: [_silence(100, 20), _silence(200, 20)],
        maxHoldMs: 5 * minute,
      );
      expect(d.holds.map((h) => h.holdMs), [5 * minute, 5 * minute]);
      expect(d.remainderMs, 50 * minute);
    });

    test('is deterministic: the same input gives the same plan', () {
      final pauses = [for (var i = 0; i < 9; i++) _silence(100 + i * 70, 10 + i)];
      final a = distributeExtension(totalMs: 7 * minute, pauses: pauses);
      final b = distributeExtension(totalMs: 7 * minute, pauses: pauses);
      expect(a.holds, b.holds);
      expect(a.remainderMs, b.remainderMs);
    });
  });
}
