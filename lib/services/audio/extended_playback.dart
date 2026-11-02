/// iOS has no holds: Extend is all after the recording, counted out by the
/// Swift clock. The player still reads as if the recording were longer by
/// it, as on Android: the length is the recording plus the silence, and
/// during the silence the position runs on from the voice's end.
///
/// [extensionMs] is all of a guided session's added silence (0 for a timer);
/// [extensionRemainingMs] is what the native clock has left while the silence
/// runs, null before it begins.
({int positionMs, int durationMs}) extendedIosPlayback({
  required int positionMs,
  required int mediaDurationMs,
  required int extensionMs,
  int? extensionRemainingMs,
}) {
  if (extensionMs <= 0 || mediaDurationMs <= 0) {
    return (positionMs: positionMs, durationMs: mediaDurationMs);
  }
  final duration = mediaDurationMs + extensionMs;
  final position = extensionRemainingMs == null
      ? positionMs.clamp(0, mediaDurationMs)
      : mediaDurationMs +
            (extensionMs - extensionRemainingMs).clamp(0, extensionMs);
  return (positionMs: position, durationMs: duration);
}
