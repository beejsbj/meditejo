import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The native cue state the player reads: the countdown, and the silence of
/// Extend (which the session's own position already runs through).
class CueRuntimeState {
  const CueRuntimeState({
    this.phase = 'idle',
    this.countdownMs = 0,
    this.extensionMs = 0,
    this.paused = false,
  });
  final String phase;
  final int countdownMs, extensionMs;
  final bool paused;
}

final cueRuntimeProvider =
    NotifierProvider<CueRuntimeNotifier, CueRuntimeState>(
      CueRuntimeNotifier.new,
    );

class CueRuntimeNotifier extends Notifier<CueRuntimeState> {
  @override
  CueRuntimeState build() => const CueRuntimeState();
  void updateFromMap(Map<Object?, Object?> map) {
    state = CueRuntimeState(
      phase: map['phase'] as String? ?? 'idle',
      countdownMs: (map['countdownRemainingMs'] as num?)?.toInt() ?? 0,
      extensionMs: (map['extensionRemainingMs'] as num?)?.toInt() ?? 0,
      paused: map['paused'] as bool? ?? false,
    );
  }

  void reset() => state = const CueRuntimeState();
}

/// Whether the player screen should read the native cue state: only in the
/// foreground, while a countdown or the extension runs or may be about to (a
/// countdown at the start, an extension once the session reaches its end).
bool shouldPollCueState({
  required bool foreground,
  required String phase,
  required bool countdownExpected,
  required bool voiceAtEnd,
}) =>
    foreground &&
    (phase == 'countdown' ||
        phase == 'extension' ||
        countdownExpected ||
        (voiceAtEnd && phase != 'ended'));
