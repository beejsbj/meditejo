import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';

void main() {
  bool poll({
    bool foreground = true,
    String phase = 'playing',
    bool countdownExpected = false,
    bool voiceAtEnd = false,
  }) => shouldPollCueState(
    foreground: foreground,
    phase: phase,
    countdownExpected: countdownExpected,
    voiceAtEnd: voiceAtEnd,
  );

  test('the cue state is read only while a countdown or extension runs', () {
    expect(poll(phase: 'countdown'), isTrue);
    expect(poll(phase: 'extension'), isTrue);
    expect(poll(phase: 'playing'), isFalse);
    expect(poll(phase: 'idle'), isFalse);
    expect(poll(phase: 'ended'), isFalse);
  });

  test('or while one may be about to begin', () {
    expect(poll(phase: 'idle', countdownExpected: true), isTrue);
    expect(poll(voiceAtEnd: true), isTrue);
    expect(poll(phase: 'ended', voiceAtEnd: true), isFalse);
  });

  test('never in the background', () {
    expect(poll(foreground: false, phase: 'countdown'), isFalse);
    expect(poll(foreground: false, phase: 'extension'), isFalse);
    expect(poll(foreground: false, voiceAtEnd: true), isFalse);
  });
}
