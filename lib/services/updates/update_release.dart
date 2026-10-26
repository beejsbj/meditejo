/// What the updater knows about one published Meditejo release.
///
/// A release on `beejsbj/meditejo` carries `meditejo-release.json` next to the
/// APK (see docs/fork/UPDATES.md). The manifest holds what the GitHub API
/// does not: the `versionCode`, the APK's SHA-256 and its size. The APK's URL
/// comes from the API's asset list, and must sit under [kReleaseDownloadPrefix].
library;

const kReleaseRepo = 'beejsbj/meditejo';
const kReleaseDownloadPrefix =
    'https://github.com/$kReleaseRepo/releases/download/';
const kReleaseManifestName = 'meditejo-release.json';

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final _apkNamePattern = RegExp(r'^meditejo-[A-Za-z0-9._+-]+\.apk$');

/// What `release.sh` tags an app release: `v<MAJOR.MINOR.PATCH>`. The repository
/// holds other releases too (`catalogue-YYYYMMDD`, the bundled Dharma Seed
/// snapshot), which are prereleases and are never an update.
final _appTagPattern = RegExp(r'^v\d+\.\d+\.\d+$');

/// The release data as GitHub's `releases/latest` endpoint returns it, before
/// the manifest is read.
class ReleaseListing {
  const ReleaseListing({
    required this.tag,
    required this.notes,
    required this.publishedAt,
    required this.assetUrls,
  });

  final String tag;
  final String notes;
  final DateTime? publishedAt;

  /// Asset name to `browser_download_url`.
  final Map<String, String> assetUrls;

  String? get manifestUrl => assetUrls[kReleaseManifestName];

  factory ReleaseListing.fromApi(Object? json) {
    if (json is! Map) throw const FormatException('Release is not an object');
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('Release has no tag');
    }
    if (json['draft'] == true || json['prerelease'] == true) {
      throw const FormatException('Release is not published');
    }
    // GitHub's `releases/latest` already leaves prereleases out; this keeps a
    // catalogue release that was published by mistake from ever passing for
    // an app update, whatever its date.
    if (!_appTagPattern.hasMatch(tag)) {
      throw FormatException('Release $tag is not an app release');
    }
    final assets = <String, String>{};
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final asset in rawAssets) {
        if (asset is! Map) continue;
        final name = asset['name'];
        final url = asset['browser_download_url'];
        if (name is String && url is String) assets[name] = url;
      }
    }
    final body = json['body'];
    final published = json['published_at'];
    return ReleaseListing(
      tag: tag,
      notes: body is String ? body.trim() : '',
      publishedAt: published is String ? DateTime.tryParse(published) : null,
      assetUrls: assets,
    );
  }
}

class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.versionName,
    required this.versionCode,
    required this.apkName,
    required this.apkUrl,
    required this.size,
    required this.sha256,
    required this.notes,
    this.publishedAt,
  });

  final String tag;
  final String versionName;
  final int versionCode;
  final String apkName;
  final String apkUrl;
  final int size;

  /// Lower-case hex SHA-256 of the APK, as published.
  final String sha256;
  final String notes;
  final DateTime? publishedAt;

  /// Android only installs a higher `versionCode`, so this is the whole test.
  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode;

  /// Joins a listing with its manifest. Throws [FormatException] when either
  /// is incomplete or points outside this repository's release downloads.
  factory UpdateRelease.fromManifest(ReleaseListing listing, Object? json) {
    if (json is! Map) throw const FormatException('Manifest is not an object');
    if (json['schema'] != 1) {
      throw const FormatException('Unsupported manifest schema');
    }
    final name = _string(json, 'versionName');
    final code = json['versionCode'];
    if (code is! int || code <= 0) {
      throw const FormatException('Manifest has no versionCode');
    }
    final apkName = _string(json, 'apk');
    if (!_apkNamePattern.hasMatch(apkName)) {
      throw const FormatException('Manifest names an unexpected file');
    }
    final size = json['size'];
    if (size is! int || size <= 0) {
      throw const FormatException('Manifest has no size');
    }
    final sha = _string(json, 'sha256').toLowerCase();
    if (!_sha256Pattern.hasMatch(sha)) {
      throw const FormatException('Manifest has a malformed SHA-256');
    }
    final url = listing.assetUrls[apkName];
    if (url == null || !url.startsWith(kReleaseDownloadPrefix)) {
      throw const FormatException('The release has no APK in this repository');
    }
    return UpdateRelease(
      tag: listing.tag,
      versionName: name,
      versionCode: code,
      apkName: apkName,
      apkUrl: url,
      size: size,
      sha256: sha,
      notes: listing.notes,
      publishedAt: listing.publishedAt,
    );
  }

  factory UpdateRelease.fromJson(Map<String, Object?> json) => UpdateRelease(
    tag: json['tag'] as String,
    versionName: json['versionName'] as String,
    versionCode: json['versionCode'] as int,
    apkName: json['apkName'] as String,
    apkUrl: json['apkUrl'] as String,
    size: json['size'] as int,
    sha256: json['sha256'] as String,
    notes: json['notes'] as String? ?? '',
    publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
  );

  Map<String, Object?> toJson() => {
    'tag': tag,
    'versionName': versionName,
    'versionCode': versionCode,
    'apkName': apkName,
    'apkUrl': apkUrl,
    'size': size,
    'sha256': sha256,
    'notes': notes,
    'publishedAt': publishedAt?.toIso8601String(),
  };

  static String _string(Map json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Manifest has no $key');
    }
    return value.trim();
  }
}

/// `PackageInfo.buildNumber` is the `versionCode` as text. Anything else is
/// read as 0, so a broken value can only ever offer an update, never hide one.
int parseBuildNumber(String? buildNumber) =>
    int.tryParse(buildNumber?.trim() ?? '') ?? 0;
