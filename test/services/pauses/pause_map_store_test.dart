import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/pauses/media_spans.dart';
import 'package:medito/services/pauses/pause_map_store.dart';

void main() {
  late Directory dir;
  late PauseMapStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pause_map_store');
    store = PauseMapStore(() async => dir);
  });
  tearDown(() => dir.delete(recursive: true));

  const map = MediaSpanMap(
    durationMs: 600000,
    spans: [MediaSpan(60000, 75000, MediaSpanKind.silence)],
  );

  test('a recording read once is read back', () async {
    expect(await store.read('ds-9985|file'), isNull);
    await store.write('ds-9985|file', map);
    final back = await store.read('ds-9985|file');
    expect(back!.durationMs, 600000);
    expect(back.spans, map.spans);
    // Another recording is another entry.
    expect(await store.read('ds-9986|file'), isNull);
  });

  test('keys with slashes and colons stay inside the folder', () async {
    await store.write('my-course/../x:y|f', map);
    expect(await store.read('my-course/../x:y|f'), isNotNull);
    expect(dir.listSync().whereType<File>().length, 1);
    expect(dir.listSync().whereType<File>().single.parent.path, dir.path);
  });

  test('a damaged file reads as absent', () async {
    await store.write('a|b', map);
    final file = dir.listSync().whereType<File>().single;
    await file.writeAsString('{ not json');
    expect(await store.read('a|b'), isNull);
    await file.writeAsString('{"version": 9}');
    expect(await store.read('a|b'), isNull);
  });

  test('a long key is kept under a shorter file name', () async {
    final key = 'x' * 400;
    await store.write(key, map);
    expect(await store.read(key), isNotNull);
    expect(
      dir.listSync().whereType<File>().single.uri.pathSegments.last.length,
      lessThan(200),
    );
  });

  test('the oldest are dropped beyond the limit', () async {
    for (var i = 0; i < PauseMapStore.maxEntries + 3; i++) {
      await store.write('k$i', map);
    }
    final files = dir.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.json'),
    );
    expect(files.length, PauseMapStore.maxEntries);
  });
}
