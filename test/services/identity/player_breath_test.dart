import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/services/identity/mark_moments.dart';

void main() {
  group('PlayerBreath.periodSeconds', () {
    test('with no pulse it breathes six times a minute', () {
      final cues = CueSettings.defaults(CueKind.practice);
      expect(cues.pulseSound, isEmpty);
      expect(PlayerBreath.periodSeconds(cues), 10);
    });

    double period(double bpm) => PlayerBreath.periodSeconds(
      // The constructor, not copyWith: the latter holds a pulse to 20-120.
      CueSettings(pulseSound: cuePulseSounds['Soft click']!, pulseBpm: bpm),
    )!;

    test('a breath spans a whole number of beats, nearest ten seconds', () {
      expect(period(60), closeTo(10, 1e-9)); // 10 beats
      expect(period(120), closeTo(10, 1e-9)); // 20 beats
      expect(period(40), closeTo(10.5, 1e-9)); // 7 beats
      expect(period(6), closeTo(10, 1e-9)); // 1 beat
      expect(period(20), closeTo(9, 1e-9)); // 3 beats
    });

    test('every pulse the settings allow stays a calm breath', () {
      for (var bpm = 20.0; bpm <= 120; bpm++) {
        final p = period(bpm);
        expect(p, inInclusiveRange(PlayerBreath.minSeconds, 15));
        final beats = p / (60 / bpm);
        expect((beats - beats.round()).abs(), lessThan(1e-9));
        expect((p - 10).abs(), lessThanOrEqualTo(1.5));
      }
    });

    test('a very slow pulse is one beat, within the bounds', () {
      expect(period(2), PlayerBreath.maxSeconds);
    });

    test('a pulse rate with no pulse sound is not used', () {
      final cues = CueSettings.defaults(
        CueKind.practice,
      ).copyWith(pulseBpm: 30);
      expect(PlayerBreath.periodSeconds(cues), 10);
    });

    test('reduced motion is a still mark', () {
      final cues = CueSettings.defaults(CueKind.practice);
      expect(PlayerBreath.periodSeconds(cues, reducedMotion: true), isNull);
      expect(
        PlayerBreath.periodSeconds(
          cues.copyWith(pulseSound: cuePulseSounds['Heartbeat']),
          reducedMotion: true,
        ),
        isNull,
      );
    });
  });
}
