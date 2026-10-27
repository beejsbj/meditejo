import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pauses/media_spans.dart';
import 'package:medito/services/pauses/pause_map_service.dart';
import 'package:medito/services/pauses/pause_map_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PauseMapService service;
  late List<MethodCall> calls;
  Object? Function(MethodCall call) answer = (_) => null;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pause_map_service');
    calls = [];
    answer = (_) => null;
    const channel = MethodChannel('meditejo/pauses');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final result = answer(call);
          if (result is PlatformException) throw result;
          return result;
        });
    service = PauseMapService(PauseMapStore(() async => dir));
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('meditejo/pauses'), null);
    await dir.delete(recursive: true);
  });

  Map<String, Object?> found() => {
    'durationMs': 2640000,
    'spans': [
      {'start': 1375000, 'end': 1405000},
      {'start': 1500000, 'end': 1512000},
    ],
  };

  test('reads a recording once and keeps what it found', () async {
    answer = (_) => found();
    final map = await service.analyse('k', '/files/talk.mp3');
    expect(map!.durationMs, 2640000);
    expect(map.spans.map((s) => s.kind), everyElement(MediaSpanKind.silence));
    expect(map.spans.length, 2);
    expect(calls.single.method, 'analyze');
    expect(calls.single.arguments, {'source': '/files/talk.mp3'});
    // Kept: the next session does not read it again.
    final again = await service.cached('k');
    expect(again!.spans.length, 2);
    expect(calls.length, 1);
  });

  test('callers for one recording share one reading', () async {
    answer = (_) => found();
    final both = await Future.wait([
      service.analyse('k', 'a.mp3'),
      service.analyse('k', 'a.mp3'),
    ]);
    expect(both.every((m) => m != null), isTrue);
    expect(calls.length, 1);
  });

  test('a recording of another length is not the cached one', () async {
    answer = (_) => found();
    await service.analyse('k', 'a.mp3');
    expect(await service.cached('k', durationMs: 2642000), isNotNull);
    expect(await service.cached('k', durationMs: 1800000), isNull);
    expect(await service.cached('k', durationMs: 0), isNotNull);
  });

  test('a metered connection reads nothing and is not retried', () async {
    answer = (_) => PlatformException(code: 'METERED');
    expect(await service.analyse('k', 'https://example.org/a.mp3'), isNull);
    expect(await service.analyse('k', 'https://example.org/a.mp3'), isNull);
    expect(calls.length, 1);
    expect(await service.cached('k'), isNull);
  });

  test('a recording the phone cannot decode is not retried either', () async {
    answer = (_) => PlatformException(code: 'ANALYSIS_FAILED');
    expect(await service.analyse('k', 'a.mp3'), isNull);
    expect(await service.analyse('k', 'a.mp3'), isNull);
    expect(calls.length, 1);
  });

  test('a cancelled reading may be tried again', () async {
    answer = (_) => PlatformException(code: 'CANCELLED');
    expect(await service.analyse('k', 'a.mp3'), isNull);
    answer = (_) => found();
    expect(await service.analyse('k', 'a.mp3'), isNotNull);
  });

  test('a recording with no pauses is remembered as such', () async {
    answer = (_) => {'durationMs': 600000, 'spans': <Object>[]};
    final map = await service.analyse('k', 'a.mp3');
    expect(map!.spans, isEmpty);
    expect((await service.cached('k'))!.spans, isEmpty);
  });

  test('YouTube is never read; neither is nothing', () {
    expect(PauseMapService.canAnalyse('yt-video-abc', 'https://x/y'), isFalse);
    expect(PauseMapService.canAnalyse('ds-9985', ''), isFalse);
    expect(PauseMapService.canAnalyse('ds-9985', 'https://x/y.mp3'), isTrue);
    expect(PauseMapService.canAnalyse('my-1', '/files/a.mp3'), isTrue);
  });

  test(
    'holdsFor spreads Extend over the recording, or nothing without a map',
    () {
      expect(PauseMapService.holdsFor(null, 10), isEmpty);
      const map = MediaSpanMap(
        durationMs: 2640000,
        spans: [MediaSpan(1375000, 1405000, MediaSpanKind.silence)],
      );
      expect(PauseMapService.holdsFor(map, 0), isEmpty);
      final holds = PauseMapService.holdsFor(map, 3);
      expect(holds.single.atMs, 1390000);
      expect(holds.single.holdMs, 180000);
    },
  );

  test('the key is the track and its file', () {
    expect(
      PauseMapService.keyFor('ds-1', 'f'),
      isNot(PauseMapService.keyFor('ds-1', 'g')),
    );
  });
}
