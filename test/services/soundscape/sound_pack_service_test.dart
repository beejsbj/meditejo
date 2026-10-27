import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/services/soundscape/sound_pack_service.dart';

SoundEntry _entry(List<int> data, {String id = 'rain-car'}) => SoundEntry(
  id: id,
  title: id,
  category: SoundCategory.rain,
  asset: 'assets/sounds/$id.opus',
  license: SoundLicense.cc0,
  author: 'A',
  sourceUrl: 'https://example.org',
  file: '$id.opus',
  bundled: false,
  bytes: data.length,
  sha256: sha256.convert(data).toString(),
);

const _pin = SoundPackPin('sounds-20261027');

void main() {
  late Directory dir;
  late SoundPackFiles files;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('sound_pack_test');
    files = SoundPackFiles(Directory('${dir.path}/pack'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  SoundPackDownloader downloader(MockClientHandler handler) =>
      SoundPackDownloader(client: MockClient(handler));

  SoundPackDownloader streaming(
    Future<http.StreamedResponse> Function() answer,
  ) => SoundPackDownloader(
    client: MockClient.streaming((request, body) => answer()),
  );

  group('a download is checked against the library', () {
    test('the pinned bytes are kept, and progress ends at the total', () async {
      final data = List.generate(4096, (i) => i % 251);
      final sound = _entry(data);
      final seen = <int>[];
      await downloader((request) async {
        expect(
          request.url.toString(),
          'https://github.com/beejsbj/meditejo/releases/download/'
          'sounds-20261027/rain-car.opus',
        );
        return http.Response.bytes(data, 200);
      }).download(
        sound,
        _pin.urlFor(sound),
        files,
        onProgress: (received, total) => seen.add(received),
      );
      expect(files.fileFor(sound).readAsBytesSync(), data);
      expect(seen.last, data.length);
      expect(files.partFor(sound).existsSync(), isFalse);
      expect(await files.scan([sound]), {sound.id});
    });

    test('a changed byte is refused and nothing is kept', () async {
      final data = List.filled(2048, 7);
      final sound = _entry(data);
      final tampered = [...data]..[100] = 8;
      await expectLater(
        downloader(
          (_) async => http.Response.bytes(tampered, 200),
        ).download(sound, _pin.urlFor(sound), files),
        throwsA(
          isA<SoundDownloadException>().having(
            (e) => e.failure,
            'failure',
            SoundDownloadFailure.integrity,
          ),
        ),
      );
      expect(files.fileFor(sound).existsSync(), isFalse);
      expect(files.partFor(sound).existsSync(), isFalse);
      expect(await files.scan([sound]), isEmpty);
    });

    test('too short and too long are both refused', () async {
      final data = List.filled(2048, 7);
      final sound = _entry(data);
      for (final body in [
        data.sublist(0, 2000),
        [...data, 1],
      ]) {
        await expectLater(
          downloader(
            (_) async => http.Response.bytes(body, 200),
          ).download(sound, _pin.urlFor(sound), files),
          throwsA(isA<SoundDownloadException>()),
        );
        expect(files.fileFor(sound).existsSync(), isFalse);
        expect(files.partFor(sound).existsSync(), isFalse);
      }
    });

    test(
      'a bad answer is a server failure, a dropped line a network one',
      () async {
        final sound = _entry(List.filled(64, 1));
        await expectLater(
          downloader(
            (_) async => http.Response('nope', 404),
          ).download(sound, _pin.urlFor(sound), files),
          throwsA(
            isA<SoundDownloadException>().having(
              (e) => e.failure,
              'failure',
              SoundDownloadFailure.server,
            ),
          ),
        );
        await expectLater(
          downloader(
            (_) async => throw const SocketException('offline'),
          ).download(sound, _pin.urlFor(sound), files),
          throwsA(
            isA<SoundDownloadException>().having(
              (e) => e.failure,
              'failure',
              SoundDownloadFailure.network,
            ),
          ),
        );
      },
    );

    test('a connection that breaks part-way leaves no partial file', () async {
      final data = List.filled(4096, 3);
      final sound = _entry(data);
      Stream<List<int>> broken() async* {
        yield data.sublist(0, 1000);
        throw const SocketException('reset');
      }

      await expectLater(
        streaming(
          () async => http.StreamedResponse(broken(), 200),
        ).download(sound, _pin.urlFor(sound), files),
        throwsA(
          isA<SoundDownloadException>().having(
            (e) => e.failure,
            'failure',
            SoundDownloadFailure.network,
          ),
        ),
      );
      expect(files.partFor(sound).existsSync(), isFalse);
      expect(files.fileFor(sound).existsSync(), isFalse);
    });

    test('only release downloads of this repository are fetched', () async {
      final sound = _entry(List.filled(64, 1));
      var asked = false;
      await expectLater(
        downloader((_) async {
          asked = true;
          return http.Response.bytes(List.filled(64, 1), 200);
        }).download(sound, Uri.parse('https://example.org/x.opus'), files),
        throwsA(isA<SoundDownloadException>()),
      );
      expect(asked, isFalse);
    });

    test('cancelling stops a stalled download and removes its part', () async {
      final data = List.filled(4096, 3);
      final sound = _entry(data);
      final cancel = SoundDownloadCancel();
      final stalled = StreamController<List<int>>();
      stalled.add(data.sublist(0, 500));
      final future = streaming(
        () async => http.StreamedResponse(stalled.stream, 200),
      ).download(sound, _pin.urlFor(sound), files, cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      cancel.cancel();
      await future;
      expect(files.fileFor(sound).existsSync(), isFalse);
      expect(files.partFor(sound).existsSync(), isFalse);
      await stalled.close();
    });
  });

  group('the files on disk', () {
    test('scan keeps whole files and tidies stale and partial ones', () async {
      final a = _entry(List.filled(100, 1), id: 'a-sound');
      final b = _entry(List.filled(100, 2), id: 'b-sound');
      files.directory.createSync(recursive: true);
      files.fileFor(a).writeAsBytesSync(List.filled(100, 1));
      // Right name, wrong size: whole files are the only ones that count.
      files.fileFor(b).writeAsBytesSync(List.filled(40, 2));
      File(
        '${files.directory.path}/gone-0123456789ab.opus',
      ).writeAsBytesSync([1]);
      File('${files.directory.path}/c.opus.part').writeAsBytesSync([1]);
      expect(await files.scan([a, b]), {'a-sound'});
      expect(files.directory.listSync(), hasLength(4));
      expect(await files.scan([a, b], tidy: true), {'a-sound'});
      expect(files.directory.listSync().map((e) => e.path), [
        files.fileFor(a).path,
      ]);
      expect(await files.usedBytes(), 100);
    });

    test('a changed pack is a different file, so the old one is stale', () {
      final before = _entry(List.filled(100, 1));
      final after = _entry(List.filled(100, 2));
      expect(files.fileFor(before).path, isNot(files.fileFor(after).path));
    });

    test('deleteAll frees everything', () async {
      final a = _entry(List.filled(100, 1));
      files.directory.createSync(recursive: true);
      files.fileFor(a).writeAsBytesSync(List.filled(100, 1));
      await files.deleteAll();
      expect(await files.scan([a]), isEmpty);
      expect(await files.usedBytes(), 0);
    });
  });
}
