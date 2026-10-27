/// What a stretch of a recording is. Only silence is detected today; section
/// markers (practice, talk) can add kinds here and reuse the same store.
enum MediaSpanKind {
  silence;

  static MediaSpanKind? tryParse(Object? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// A time range of a recording, in media milliseconds.
class MediaSpan {
  const MediaSpan(this.startMs, this.endMs, this.kind);

  final int startMs, endMs;
  final MediaSpanKind kind;

  int get lengthMs => endMs - startMs;
  int get midpointMs => startMs + lengthMs ~/ 2;

  Map<String, Object?> toJson() => {
    'start': startMs,
    'end': endMs,
    'kind': kind.name,
  };

  static MediaSpan? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final start = json['start'];
    final end = json['end'];
    final kind = MediaSpanKind.tryParse(json['kind']);
    if (start is! int || end is! int || kind == null) return null;
    if (start < 0 || end <= start) return null;
    return MediaSpan(start, end, kind);
  }

  @override
  bool operator ==(Object other) =>
      other is MediaSpan &&
      startMs == other.startMs &&
      endMs == other.endMs &&
      kind == other.kind;

  @override
  int get hashCode => Object.hash(startMs, endMs, kind);

  @override
  String toString() => 'MediaSpan(${kind.name} $startMs-$endMs)';
}

/// The spans found in one recording, kept so the recording is read once.
/// Stored as JSON; a value a newer app wrote, or one that does not parse,
/// reads as absent and the recording is simply analysed again.
class MediaSpanMap {
  const MediaSpanMap({
    required this.durationMs,
    required this.spans,
    this.analyzer = analyzerVersion,
  });

  /// Bumped when the detection changes, so older results are redone.
  static const analyzerVersion = 1;
  static const formatVersion = 1;

  /// Length of the recording that was read.
  final int durationMs;
  final List<MediaSpan> spans;
  final int analyzer;

  Iterable<MediaSpan> ofKind(MediaSpanKind kind) =>
      spans.where((s) => s.kind == kind);

  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'analyzer': analyzer,
    'durationMs': durationMs,
    'spans': [for (final s in spans) s.toJson()],
  };

  static MediaSpanMap? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    final analyzer = json['analyzer'];
    final duration = json['durationMs'];
    final raw = json['spans'];
    if (version is! int || version > formatVersion) return null;
    if (analyzer is! int || analyzer != analyzerVersion) return null;
    if (duration is! int || duration <= 0 || raw is! List) return null;
    final spans = [
      for (final item in raw)
        if (MediaSpan.tryFromJson(item) case final span?) span,
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    return MediaSpanMap(durationMs: duration, spans: spans, analyzer: analyzer);
  }
}
