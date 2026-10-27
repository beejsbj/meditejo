import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';

void main() {
  bool poll({
    bool foreground = true,
    String phase = 'playing',
    bool countdownExpected = false,
    bool voiceAtEnd = false,
    bool holdsPlanned = false,
  }) => shouldPollCueState(
    foreground: foreground,
    phase: phase,
    countdownExpected: countdownExpected,
    voiceAtEnd: voiceAtEnd,
    holdsPlanned: holdsPlanned,
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
    'a rest in a pause is read, and watched for when Extend is in the pauses',
    () {
      expect(poll(phase: 'hold'), isTrue);
      expect(poll(phase: 'playing', holdsPlanned: true), isTrue);
      expect(poll(phase: 'idle', holdsPlanned: true), isTrue);
      expect(poll(phase: 'playing', holdsPlanned: false), isFalse);
      expect(poll(foreground: false, phase: 'hold'), isFalse);
      expect(poll(foreground: false, holdsPlanned: true), isFalse);
    },
  );

  test('the runtime state carries the rest and what Extend has left', () {
    const state = CueRuntimeState(
      phase: 'hold',
      holdMs: 45000,
      extensionLeftMs: 300000,
    );
    expect(state.isResting, isTrue);
    expect(const CueRuntimeState().isResting, isFalse);
    expect(const CueRuntimeState().extensionLeftMs, isNull);
    expect(state.holdMs, 45000);
  });

  test('the native map fills the rest and the Extend time left', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(cueRuntimeProvider.notifier).updateFromMap({
      'phase': 'hold',
      'holdRemainingMs': 30000,
      'extensionLeftMs': 120000,
      'paused': false,
    });
    final state = container.read(cueRuntimeProvider);
    expect(state.isResting, isTrue);
    expect(state.holdMs, 30000);
    expect(state.extensionLeftMs, 120000);
    container.read(cueRuntimeProvider.notifier).updateFromMap({
      'phase': 'idle',
    });
    expect(container.read(cueRuntimeProvider).extensionLeftMs, isNull);
  });
}
