import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';

sealed class LatestRelease {
  const LatestRelease();
}

/// The cached release is still the latest (`304`).
class LatestUnchanged extends LatestRelease {
  const LatestUnchanged();
}

/// The repository has no published release.
class LatestNone extends LatestRelease {
  const LatestNone();
}

class LatestFound extends LatestRelease {
  const LatestFound(this.release, this.etag);

  final UpdateRelease release;
  final String? etag;
}

/// Reads the newest published release, unauthenticated.
///
/// `GET /repos/beejsbj/meditejo/releases/latest` with `If-None-Match`: a `304`
/// does not count against GitHub's 60-requests-an-hour limit. Only when the
/// release changed is the manifest fetched too.
class GithubReleaseClient {
  GithubReleaseClient({
    http.Client? httpClient,
    Uri? latestUri,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient ?? http.Client(),
       latestUri =
           latestUri ??
           Uri.parse('https://api.github.com/repos/$kReleaseRepo/releases/latest');

  static const userAgent =
      'Meditejo (personal meditation app; +https://github.com/$kReleaseRepo)';

  final http.Client _http;
  final Uri latestUri;
  final Duration timeout;

  Future<LatestRelease> latest({String? etag}) async {
    final response = await _get(latestUri, {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'If-None-Match': ?etag,
    });
    switch (response.statusCode) {
      case 304:
        return const LatestUnchanged();
      case 404:
        return const LatestNone();
      case 200:
        break;
      case 429:
        throw const UpdateException(UpdateFailure.rateLimited);
      case 403:
        throw UpdateException(
          response.headers['x-ratelimit-remaining'] == '0'
              ? UpdateFailure.rateLimited
              : UpdateFailure.unavailable,
          'HTTP 403',
        );
      default:
        throw UpdateException(
          UpdateFailure.unavailable,
          'HTTP ${response.statusCode}',
        );
    }

    try {
      final listing = ReleaseListing.fromApi(_json(response));
      final manifestUrl = listing.manifestUrl;
      if (manifestUrl == null || !manifestUrl.startsWith(kReleaseDownloadPrefix)) {
        throw const FormatException('The release has no update manifest');
      }
      final manifest = await _get(Uri.parse(manifestUrl), {
        'Accept': 'application/json',
      });
      if (manifest.statusCode != 200) {
        throw UpdateException(
          manifest.statusCode == 429
              ? UpdateFailure.rateLimited
              : UpdateFailure.unavailable,
          'Manifest HTTP ${manifest.statusCode}',
        );
      }
      return LatestFound(
        UpdateRelease.fromManifest(listing, _json(manifest)),
        response.headers['etag'],
      );
    } on FormatException catch (e) {
      throw UpdateException(UpdateFailure.unavailable, e.message);
    }
  }

  Object? _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes));

  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    try {
      return await _http
          .get(uri, headers: {'User-Agent': userAgent, ...headers})
          .timeout(timeout);
    } on UpdateException {
      rethrow;
    } on TimeoutException {
      throw const UpdateException(UpdateFailure.offline, 'Timed out');
    } on SocketException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    } on HandshakeException catch (e) {
      throw UpdateException(UpdateFailure.offline, e.message);
    }
  }

  void close() => _http.close();
}
