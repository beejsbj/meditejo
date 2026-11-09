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

    test('a pulse sets the rate: one breath a beat', () {
      final cues = CueSettings.defaults(
        CueKind.practice,
      ).copyWith(pulseSound: cuePulseSounds['Soft click'], pulseBpm: 30);
      expect(PlayerBreath.periodSeconds(cues), 2);
      expect(PlayerBreath.periodSeconds(cues.copyWith(pulseBpm: 60)), 1);
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
