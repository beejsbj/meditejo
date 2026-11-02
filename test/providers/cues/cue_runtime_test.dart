import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  test(
    'silence inside the recording needs no polling: the position runs through it',
    () {
      expect(poll(phase: 'hold'), isFalse);
    },
  );

  test('the native map fills the phase and the tail left', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(cueRuntimeProvider.notifier).updateFromMap({
      'phase': 'hold',
      'holdRemainingMs': 30000,
      'extensionRemainingMs': 120000,
      'paused': true,
    });
    final state = container.read(cueRuntimeProvider);
    expect(state.phase, 'hold');
    expect(state.extensionMs, 120000);
    expect(state.paused, isTrue);
    container.read(cueRuntimeProvider.notifier).updateFromMap({
      'phase': 'idle',
    });
    expect(container.read(cueRuntimeProvider).extensionMs, 0);
  });
}
