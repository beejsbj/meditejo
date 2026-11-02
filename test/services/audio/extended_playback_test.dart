import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/audio/extended_playback.dart';

void main() {
  const minute = 60000;

  test('the length is the recording plus its silence', () {
    final r = extendedIosPlayback(
      positionMs: 3 * minute,
      mediaDurationMs: 20 * minute,
      extensionMs: 10 * minute,
    );
    expect(r.durationMs, 30 * minute);
    expect(r.positionMs, 3 * minute);
  });

  test('during the silence the position runs on from the voice end', () {
    final r = extendedIosPlayback(
      positionMs: 20 * minute,
      mediaDurationMs: 20 * minute,
      extensionMs: 10 * minute,
      extensionRemainingMs: 4 * minute,
    );
    expect(r.positionMs, 26 * minute);
    expect(r.durationMs, 30 * minute);
  });

  test('a timer or no Extend reads as the player', () {
    final r = extendedIosPlayback(
      positionMs: 5 * minute,
      mediaDurationMs: 10 * minute,
      extensionMs: 0,
    );
    expect(r.positionMs, 5 * minute);
    expect(r.durationMs, 10 * minute);
    // Before the length is known nothing is added to it.
    expect(
      extendedIosPlayback(
        positionMs: 0,
        mediaDurationMs: 0,
        extensionMs: minute,
      ).durationMs,
      0,
    );
  });

  test('a stale clock reading never runs past the ends', () {
    expect(
      extendedIosPlayback(
        positionMs: 20 * minute,
        mediaDurationMs: 20 * minute,
        extensionMs: 10 * minute,
        extensionRemainingMs: 15 * minute,
      ).positionMs,
      20 * minute,
    );
    expect(
      extendedIosPlayback(
        positionMs: 20 * minute,
        mediaDurationMs: 20 * minute,
        extensionMs: 10 * minute,
        extensionRemainingMs: -5,
      ).positionMs,
      30 * minute,
    );
  });
}
