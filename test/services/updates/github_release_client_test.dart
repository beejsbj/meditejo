import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/services/updates/github_release_client.dart';
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';

const _sha = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const _base = '${kReleaseDownloadPrefix}v0.1.1/';

String _release() => jsonEncode({
  'tag_name': 'v0.1.1',
  'draft': false,
  'prerelease': false,
  'body': 'Calmer timer',
  'assets': [
    {
      'name': 'meditejo-0.1.1.apk',
      'browser_download_url': '${_base}meditejo-0.1.1.apk',
    },
    {
      'name': kReleaseManifestName,
      'browser_download_url': '$_base$kReleaseManifestName',
    },
  ],
});

String _manifest() => jsonEncode({
  'schema': 1,
  'versionName': '0.1.1',
  'versionCode': 26101702,
  'apk': 'meditejo-0.1.1.apk',
  'size': 1234,
  'sha256': _sha,
});

GithubReleaseClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => GithubReleaseClient(httpClient: MockClient(handler));

void main() {
  test('reads the latest release and its manifest', () async {
    final seen = <http.Request>[];
    final client = _client((request) async {
      seen.add(request);
      if (request.url.host == 'api.github.com') {
        return http.Response(_release(), 200, headers: {'etag': 'W/"abc"'});
      }
      return http.Response(_manifest(), 200);
    });

    final result = await client.latest();

    expect(result, isA<LatestFound>());
    final found = result as LatestFound;
    expect(found.release.versionCode, 26101702);
    expect(found.release.notes, 'Calmer timer');
    expect(found.etag, 'W/"abc"');
    expect(seen.first.url.path, '/repos/beejsbj/meditejo/releases/latest');
    expect(seen.first.headers['If-None-Match'], isNull);
    expect(seen.first.headers['Accept'], 'application/vnd.github+json');
    expect(seen.first.headers['User-Agent'], contains('Meditejo'));
    expect(seen.first.headers.containsKey('Authorization'), isFalse);
    expect(seen.length, 2);
  });

  test('sends the stored ETag and treats 304 as unchanged, with no manifest fetch', () async {
    final seen = <http.Request>[];
    final client = _client((request) async {
      seen.add(request);
      return http.Response('', 304);
    });

    final result = await client.latest(etag: 'W/"abc"');

    expect(result, isA<LatestUnchanged>());
    expect(seen.single.headers['If-None-Match'], 'W/"abc"');
  });

  test('a repository without releases is not an error', () async {
    final client = _client((_) async => http.Response('{}', 404));
    expect(await client.latest(), isA<LatestNone>());
  });

  test('maps rate limiting', () async {
    final limited = _client(
      (_) async => http.Response(
        '{}',
        403,
        headers: {'x-ratelimit-remaining': '0'},
      ),
    );
    await expectLater(
      limited.latest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.rateLimited,
        ),
      ),
    );
    final tooMany = _client((_) async => http.Response('{}', 429));
    await expectLater(
      tooMany.latest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.rateLimited,
        ),
      ),
    );
  });

  test('other 403s and server errors are unavailable, not rate limits', () async {
    for (final status in [403, 500, 502]) {
      final client = _client((_) async => http.Response('{}', status));
      await expectLater(
        client.latest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.unavailable,
          ),
        ),
        reason: 'HTTP $status',
      );
    }
  });

  test('network failures read as offline', () async {
    for (final error in <Object>[
      const SocketException('no route'),
      http.ClientException('connection closed'),
    ]) {
      final client = _client((_) async => throw error);
      await expectLater(
        client.latest(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.offline,
          ),
        ),
      );
    }
  });

  test('a release without a manifest is unavailable', () async {
    final client = _client(
      (_) async => http.Response(
        jsonEncode({'tag_name': 'v1', 'assets': <Object>[]}),
        200,
      ),
    );
    await expectLater(
      client.latest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.unavailable,
        ),
      ),
    );
  });

  test('a malformed manifest is unavailable', () async {
    final client = _client((request) async {
      if (request.url.host == 'api.github.com') {
        return http.Response(_release(), 200);
      }
      return http.Response('{"schema":1}', 200);
    });
    await expectLater(
      client.latest(),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.unavailable,
        ),
      ),
    );
  });
}
