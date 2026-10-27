import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/services/updates/update_downloader.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';

final _bytes = utf8.encode('pretend this is a 41 MB apk' * 40);
final _hash = sha256.convert(_bytes).toString();

UpdateRelease _release({String? hash, int? size, int code = 26101702}) =>
    UpdateRelease(
      tag: 'v0.1.1',
      versionName: '0.1.1',
      versionCode: code,
      apkName: 'meditejo-0.1.1.apk',
      apkUrl: '${kReleaseDownloadPrefix}v0.1.1/meditejo-0.1.1.apk',
      size: size ?? _bytes.length,
      sha256: hash ?? _hash,
      notes: '',
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('downloader_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  UpdateDownloader downloaderFor(MockClient client) =>
      UpdateDownloader(directory: () async => dir, httpClient: client);

  MockClient serving(
    List<int> body, {
    int status = 200,
    void Function()? onRequest,
  }) => MockClient.streaming((request, _) async {
    onRequest?.call();
    // Two chunks, so progress is reported more than once.
    final half = body.length ~/ 2;
    return http.StreamedResponse(
      Stream.fromIterable([body.sublist(0, half), body.sublist(half)]),
      status,
      contentLength: body.length,
    );
  });

  group('sha256Matches', () {
    test('compares full digests ignoring case and space', () {
      expect(sha256Matches(_hash, _hash.toUpperCase()), isTrue);
      expect(sha256Matches(' $_hash\n', _hash), isTrue);
    });

    test('rejects a different, truncated or empty digest', () {
      expect(sha256Matches(_hash, 'b' * 64), isFalse);
      expect(
        sha256Matches(_hash.substring(0, 32), _hash.substring(0, 32)),
        isFalse,
      );
      expect(sha256Matches('', ''), isFalse);
    });
  });

  test('downloads, reports progress and keeps a verified file', () async {
    final progress = <double>[];
    final file = await downloaderFor(
      serving(_bytes),
    ).download(_release(), onProgress: progress.add);

    expect(await file.readAsBytes(), _bytes);
    expect(file.path, '${dir.path}/meditejo-26101702.apk');
    expect(progress.first, lessThan(1));
    expect(progress.last, 1);
    expect(dir.listSync().whereType<File>().map((f) => f.path), [file.path]);
  });

  test(
    'a download that does not match the published hash is deleted',
    () async {
      await expectLater(
        downloaderFor(serving(_bytes)).download(_release(hash: 'b' * 64)),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.hashMismatch,
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'a download longer than announced stops and leaves nothing behind',
    () async {
      await expectLater(
        downloaderFor(serving(_bytes)).download(_release(size: 50)),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.downloadFailed,
          ),
        ),
      );
      expect(dir.listSync(), isEmpty);
    },
  );

  test('a short download is a failed download, not a hash mismatch', () async {
    await expectLater(
      downloaderFor(serving(_bytes.sublist(0, 50))).download(_release()),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.downloadFailed,
        ),
      ),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('an HTTP error fails without leaving a file', () async {
    await expectLater(
      downloaderFor(serving(const [], status: 404)).download(_release()),
      throwsA(isA<UpdateException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  test('a dropped connection reads as offline', () async {
    final client = MockClient.streaming(
      (_, _) async => throw const SocketException('gone'),
    );
    await expectLater(
      downloaderFor(client).download(_release()),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.offline,
        ),
      ),
    );
  });

  test('a file already downloaded and verified is reused', () async {
    var requests = 0;
    final downloader = downloaderFor(
      serving(_bytes, onRequest: () => requests++),
    );
    await downloader.download(_release());
    await downloader.download(_release());
    expect(requests, 1);
  });

  test('a stored file that no longer matches is fetched again', () async {
    var requests = 0;
    final downloader = downloaderFor(
      serving(_bytes, onRequest: () => requests++),
    );
    final file = await downloader.download(_release());
    await file.writeAsBytes([...(_bytes), 1]);
    expect(await downloader.verifiedExisting(_release()), isNull);
    await downloader.download(_release());
    expect(requests, 2);
  });

  test(
    'deleteStale removes leftovers and installed or older builds only',
    () async {
      for (final name in [
        'meditejo-26101701.apk',
        'meditejo-26101702.apk',
        'meditejo-26101703.apk',
        'meditejo-26101704.apk.part',
        'notes.txt',
      ]) {
        File('${dir.path}/$name').writeAsBytesSync(const [1]);
      }
      await downloaderFor(
        serving(const []),
      ).deleteStale(installedVersionCode: 26101702);
      final left = dir.listSync().map((e) => e.uri.pathSegments.last).toList()
        ..sort();
      expect(left, ['meditejo-26101703.apk', 'notes.txt']);
    },
  );

  test('sha256OfFile matches the crypto digest', () async {
    final file = File('${dir.path}/x')..writeAsBytesSync(_bytes);
    expect(await sha256OfFile(file), _hash);
  });
}
