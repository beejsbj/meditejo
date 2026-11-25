import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/cues/cue_runtime_provider.dart';

void main() {
  bool poll({
    bool foreground = true,
    String phase = 'playing',
    bool countdownExpected = false,
    bool voiceAtEnd = false,
    bool silenceExpected = false,
  }) => shouldPollCueState(
    foreground: foreground,
    phase: phase,
    countdownExpected: countdownExpected,
    voiceAtEnd: voiceAtEnd,
    silenceExpected: silenceExpected,
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

  test('a hold in the guide\'s pauses is read while it runs', () {
    expect(poll(phase: 'hold'), isTrue);
    expect(poll(foreground: false, phase: 'hold'), isFalse);
  });

  test('a session with added silence is read all through, to see its holds '
      'come and go', () {
    expect(poll(silenceExpected: true), isTrue);
    expect(poll(phase: 'idle', silenceExpected: true), isTrue);
    expect(poll(phase: 'ended', silenceExpected: true), isFalse);
    expect(poll(foreground: false, silenceExpected: true), isFalse);
  });

  test('a hold and the tail are silence; the voice and the countdown are '
      'not', () {
    bool silent(String phase) => CueRuntimeState(phase: phase).inSilence;
    expect(silent('hold'), isTrue);
    expect(silent('extension'), isTrue);
    expect(silent('playing'), isFalse);
    expect(silent('countdown'), isFalse);
    expect(silent('ended'), isFalse);
  });

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
