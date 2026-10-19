import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Native session time is separate from the recording playhead during holds.
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
