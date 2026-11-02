/// A silent hold the player takes at [atMs] of the recording.
class PauseHold {
  const PauseHold(this.atMs, this.holdMs);

  final int atMs, holdMs;

  Map<String, Object?> toJson() => {'atMs': atMs, 'holdMs': holdMs};

  @override
  bool operator ==(Object other) =>
      other is PauseHold && atMs == other.atMs && holdMs == other.holdMs;

  @override
  int get hashCode => Object.hash(atMs, holdMs);

  @override
  String toString() => 'PauseHold($atMs +$holdMs)';
}
