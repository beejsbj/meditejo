import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pauses/media_spans.dart';

void main() {
  test('a map survives a JSON round trip', () {
    const map = MediaSpanMap(
      durationMs: 600000,
      spans: [
        MediaSpan(60000, 75000, MediaSpanKind.silence),
        MediaSpan(200000, 230000, MediaSpanKind.silence),
      ],
    );
    final back = MediaSpanMap.tryFromJson(jsonDecode(jsonEncode(map.toJson())));
    expect(back, isNotNull);
    expect(back!.durationMs, 600000);
    expect(back.spans, map.spans);
  });

  test('spans of a kind this app does not know are left out', () {
    final back = MediaSpanMap.tryFromJson({
      'version': 1,
      'analyzer': MediaSpanMap.analyzerVersion,
      'durationMs': 1000,
      'spans': [
        {'start': 0, 'end': 10, 'kind': 'talk'},
        {'start': 20, 'end': 30, 'kind': 'silence'},
      ],
    });
    expect(back!.spans.map((s) => s.startMs), [20]);
  });

  test('a newer format, an older analyser or damage reads as absent', () {
    expect(MediaSpanMap.tryFromJson(null), isNull);
    expect(MediaSpanMap.tryFromJson('x'), isNull);
    expect(
      MediaSpanMap.tryFromJson({
        'version': 2,
        'analyzer': MediaSpanMap.analyzerVersion,
        'durationMs': 1000,
        'spans': [],
      }),
      isNull,
    );
    expect(
      MediaSpanMap.tryFromJson({
        'version': 1,
        'analyzer': MediaSpanMap.analyzerVersion - 1,
        'durationMs': 1000,
        'spans': [],
      }),
      isNull,
    );
    expect(
      MediaSpanMap.tryFromJson({
        'version': 1,
        'analyzer': MediaSpanMap.analyzerVersion,
        'durationMs': 0,
        'spans': [],
      }),
      isNull,
    );
  });

  test('damaged spans are dropped and the rest sorted', () {
    final back = MediaSpanMap.tryFromJson({
      'version': 1,
      'analyzer': MediaSpanMap.analyzerVersion,
      'durationMs': 1000,
      'spans': [
        {'start': 500, 'end': 600, 'kind': 'silence'},
        {'start': 700, 'end': 700, 'kind': 'silence'},
        {'start': 'a', 'end': 9, 'kind': 'silence'},
        {'start': 100, 'end': 200, 'kind': 'silence'},
      ],
    });
    expect(back!.spans.map((s) => s.startMs), [100, 500]);
  });
}
