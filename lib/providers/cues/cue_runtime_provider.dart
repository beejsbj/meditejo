import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native session time is separate from the recording playhead during holds.
class CueRuntimeState {
  const CueRuntimeState({
    this.phase = 'idle',
    this.countdownMs = 0,
    this.extensionMs = 0,
    this.holdMs = 0,
    this.extensionLeftMs,
    this.paused = false,
  });
  final String phase;
  final int countdownMs, extensionMs;

  /// Time left of the rest in a pause under way (phase `hold`).
  final int holdMs;

  /// Extend time still to come wherever it will be spent: this rest, the ones
  /// ahead, and the end. Null before the native side has said.
  final int? extensionLeftMs;
  final bool paused;

  /// The voice is resting inside the recording, in one of its pauses.
  bool get isResting => phase == 'hold';
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
      holdMs: (map['holdRemainingMs'] as num?)?.toInt() ?? 0,
      extensionLeftMs: (map['extensionLeftMs'] as num?)?.toInt(),
      paused: map['paused'] as bool? ?? false,
    );
  }

  void reset() => state = const CueRuntimeState();
}

/// Whether the player screen should read the native cue state: only in the
/// foreground, while a countdown, a rest in a pause or the extension runs or
/// may be about to (a countdown at the start, a rest when Extend is placed in
/// the pauses and the recording has any, an extension once the voice reaches
/// its end).
bool shouldPollCueState({
  required bool foreground,
  required String phase,
  required bool countdownExpected,
  required bool voiceAtEnd,
  bool holdsPlanned = false,
}) =>
    foreground &&
    (phase == 'countdown' ||
        phase == 'extension' ||
        phase == 'hold' ||
        countdownExpected ||
        holdsPlanned ||
        (voiceAtEnd && phase != 'ended'));
