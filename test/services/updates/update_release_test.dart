import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/updates/update_release.dart';

const _sha = 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';
const _base = '${kReleaseDownloadPrefix}v0.1.1/';

Map<String, Object?> _api({Map<String, Object?> extra = const {}}) => {
  'tag_name': 'v0.1.1',
  'draft': false,
  'prerelease': false,
  'body': '  - Calmer timer  ',
  'published_at': '2026-10-17T12:00:00Z',
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
  ...extra,
};

Map<String, Object?> _manifest({Map<String, Object?> extra = const {}}) => {
  'schema': 1,
  'versionName': '0.1.1',
  'versionCode': 26101702,
  'apk': 'meditejo-0.1.1.apk',
  'size': 41875546,
  'sha256': _sha,
  ...extra,
};

UpdateRelease _parse({
  Map<String, Object?> api = const {},
  Map<String, Object?> manifest = const {},
}) => UpdateRelease.fromManifest(
  ReleaseListing.fromApi(_api(extra: api)),
  _manifest(extra: manifest),
);

void main() {
  group('version comparison', () {
    test('only a higher versionCode is newer', () {
      final release = _parse();
      expect(release.isNewerThan(26101701), isTrue);
      expect(release.isNewerThan(26101702), isFalse);
      expect(release.isNewerThan(26101703), isFalse);
    });

    test('any Meditejo code is above the inherited Medito build', () {
      expect(_parse().isNewerThan(302473), isTrue);
    });

    test('parseBuildNumber reads the code and never throws', () {
      expect(parseBuildNumber('26101701'), 26101701);
      expect(parseBuildNumber(' 26101701 '), 26101701);
      expect(parseBuildNumber(''), 0);
      expect(parseBuildNumber(null), 0);
      expect(parseBuildNumber('1.2.3'), 0);
    });
  });

  group('release parsing', () {
    test('joins the API listing with the manifest', () {
      final release = _parse();
      expect(release.tag, 'v0.1.1');
      expect(release.versionName, '0.1.1');
      expect(release.versionCode, 26101702);
      expect(release.size, 41875546);
      expect(release.sha256, _sha);
      expect(release.apkUrl, '${_base}meditejo-0.1.1.apk');
      expect(release.notes, '- Calmer timer');
      expect(release.publishedAt, DateTime.utc(2026, 10, 17, 12));
    });

    test('lower-cases the published digest', () {
      expect(_parse(manifest: {'sha256': _sha.toUpperCase()}).sha256, _sha);
    });

    test('survives a JSON round trip', () {
      final release = _parse();
      final again = UpdateRelease.fromJson(release.toJson());
      expect(again.toJson(), release.toJson());
    });

    test('reads a release with no notes', () {
      expect(_parse(api: {'body': null}).notes, '');
    });

    test('exposes the manifest URL from the assets', () {
      expect(
        ReleaseListing.fromApi(_api()).manifestUrl,
        '$_base$kReleaseManifestName',
      );
    });

    test('refuses drafts and pre-releases', () {
      expect(
        () => ReleaseListing.fromApi(_api(extra: {'draft': true})),
        throwsFormatException,
      );
      expect(
        () => ReleaseListing.fromApi(_api(extra: {'prerelease': true})),
        throwsFormatException,
      );
    });

    test('refuses a release that is not tagged as an app release', () {
      // The catalogue snapshot lives on `catalogue-YYYYMMDD` releases.
      for (final tag in [
        'catalogue-20261019',
        'catalogue-20261019-2',
        'v1',
        'v0.1',
        'v0.1.1-rc1',
        '0.1.1',
      ]) {
        expect(
          () => ReleaseListing.fromApi(_api(extra: {'tag_name': tag})),
          throwsFormatException,
          reason: tag,
        );
      }
    });

    test('refuses malformed manifests', () {
      for (final bad in <Map<String, Object?>>[
        {'schema': 2},
        {'versionCode': '26101702'},
        {'versionCode': 0},
        {'versionName': ''},
        {'size': 0},
        {'sha256': 'abc'},
        {'sha256': 'z' * 64},
        {'apk': '../evil.apk'},
        {'apk': 'other.apk'},
      ]) {
        expect(() => _parse(manifest: bad), throwsFormatException, reason: '$bad');
      }
      expect(
        () => UpdateRelease.fromManifest(ReleaseListing.fromApi(_api()), 'text'),
        throwsFormatException,
      );
    });

    test('refuses an APK URL outside this repository\'s releases', () {
      final listing = ReleaseListing.fromApi(
        _api(
          extra: {
            'assets': [
              {
                'name': 'meditejo-0.1.1.apk',
                'browser_download_url': 'https://example.com/meditejo-0.1.1.apk',
              },
            ],
          },
        ),
      );
      expect(
        () => UpdateRelease.fromManifest(listing, _manifest()),
        throwsFormatException,
      );
    });
  });
}
