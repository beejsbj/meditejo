import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';

void main() {
  test('Drift deepens a moving drone voice and keeps its period', () {
    final drift = LayerMotion.forSound(kSynthDroneId);
    final voice = const DroneParams(movement: 0.5).partials().first;
    final swell = LayerMotion(
      period: voice.swellPeriod!,
      floor: voice.swellFloor,
    );
    final both = LayerMotion.combine(swell, drift)!;
    expect(both.period, swell.period, reason: 'voices stay out of step');
    expect(both.floor, closeTo(swell.floor * drift.floor, 1e-12));
    expect(both.floor, lessThan(swell.floor), reason: 'the toggle is heard');
  });

  test('either motion alone is itself; neither is none', () {
    const swell = LayerMotion(period: Duration(seconds: 47), floor: 0.7);
    const drift = LayerMotion(period: Duration(seconds: 60));
    expect(LayerMotion.combine(swell, null), swell);
    expect(LayerMotion.combine(null, drift), drift);
    expect(LayerMotion.combine(null, null), isNull);
  });
}
