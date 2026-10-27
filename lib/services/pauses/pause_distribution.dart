import 'package:medito/models/pauses/media_spans.dart';

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

/// Where the Extend minutes go: [holds] in the guide's pauses, and
/// [remainderMs] after the recording as "At the end" has always done.
/// `sum(holds) + remainderMs` is always the minutes asked for.
class PauseDistribution {
  const PauseDistribution(this.holds, this.remainderMs);

  final List<PauseHold> holds;
  final int remainderMs;

  int get heldMs => holds.fold(0, (sum, h) => sum + h.holdMs);
}

/// The pauses of [map] worth holding in: silence of at least [minPauseMs],
/// not the quiet at the very start or end of the file (a hold there is just
/// the start or the end). In recording order.
List<MediaSpan> usablePauses(
  MediaSpanMap map, {
  int minPauseMs = defaultMinPauseMs,
  int edgeMs = defaultEdgeMs,
}) => [
  for (final s in map.ofKind(MediaSpanKind.silence))
    if (s.lengthMs >= minPauseMs &&
        s.startMs >= edgeMs &&
        s.endMs <= map.durationMs - edgeMs)
      s,
];

/// A pause must last this long to be worth holding in.
const defaultMinPauseMs = 10000;

/// Silence this close to either end of the file is not a pause.
const defaultEdgeMs = 3000;

/// A hold shorter than this is not worth interrupting the voice for.
const defaultMinHoldMs = 10000;

/// No single pause takes more than this.
const defaultMaxHoldMs = 5 * 60000;

/// Shares [totalMs] of extension across [pauses], each at its midpoint.
///
/// Weighted by pause length, so the long pauses of a guided sit take more
/// than a breath between instructions. Few minutes go to the longest pauses
/// only (a hold is at least [minHoldMs]); no pause takes more than
/// [maxHoldMs] (what the others cannot take is shared among them again).
/// Holds are whole seconds. What no pause takes is the remainder: all of it
/// when there is no usable pause.
PauseDistribution distributeExtension({
  required int totalMs,
  required List<MediaSpan> pauses,
  int minPauseMs = defaultMinPauseMs,
  int minHoldMs = defaultMinHoldMs,
  int maxHoldMs = defaultMaxHoldMs,
}) {
  if (totalMs <= 0) return const PauseDistribution([], 0);
  final candidates = [
    for (final p in pauses)
      if (p.kind == MediaSpanKind.silence && p.lengthMs >= minPauseMs) p,
  ];
  if (candidates.isEmpty || totalMs < minHoldMs) {
    return PauseDistribution(const [], totalMs);
  }

  // Few minutes: only as many pauses as can each have a worthwhile hold, the
  // longest first (the earlier one on a tie).
  final byLength = [...candidates]
    ..sort((a, b) {
      final byLen = b.lengthMs.compareTo(a.lengthMs);
      return byLen != 0 ? byLen : a.startMs.compareTo(b.startMs);
    });
  var chosen = byLength.take(totalMs ~/ minHoldMs).toList();

  // Weighted shares with a ceiling per pause, redistributing what the capped
  // ones cannot take. A share that comes out under the minimum drops the
  // shortest pause and starts again.
  Map<MediaSpan, double> shares;
  while (true) {
    shares = _share(totalMs.toDouble(), chosen, maxHoldMs.toDouble());
    final small = chosen.where((p) => shares[p]! < minHoldMs).toList();
    if (small.isEmpty || chosen.length == 1) break;
    chosen.remove(small.last); // chosen is longest-first: the last is shortest
  }

  final holds = <PauseHold>[
    for (final p in chosen)
      PauseHold(p.midpointMs, (shares[p]! / 1000).floor() * 1000),
  ]..sort((a, b) => a.atMs.compareTo(b.atMs));
  final held = holds.fold(0, (sum, h) => sum + h.holdMs);
  return PauseDistribution(holds, totalMs - held);
}

/// [total] split by length over [pauses], none above [cap]. What the capped
/// ones leave is split again among the rest; if all are capped, the rest is
/// simply not shared (the caller's remainder).
Map<MediaSpan, double> _share(
  double total,
  List<MediaSpan> pauses,
  double cap,
) {
  final result = <MediaSpan, double>{};
  var open = [...pauses];
  var left = total;
  while (open.isNotEmpty) {
    final weight = open.fold<double>(0, (sum, p) => sum + p.lengthMs);
    final capped = open.where((p) => left * p.lengthMs / weight > cap).toList();
    if (capped.isEmpty) {
      for (final p in open) {
        result[p] = left * p.lengthMs / weight;
      }
      return result;
    }
    for (final p in capped) {
      result[p] = cap;
      left -= cap;
    }
    open = open.where((p) => !capped.contains(p)).toList();
  }
  return result;
}
