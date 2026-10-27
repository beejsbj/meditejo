/// The bundled sound library, read from `assets/sounds/sounds.json`.
///
/// The JSON is written by `tools/meditejo/sounds/process_sounds.py`, which
/// also writes `assets/sounds/NOTICE`. Each sound keeps its own licence: the
/// recordings are data aggregated with the app, outside the AGPL.
///
/// A sound is either **bundled** (its file is an asset in the APK) or part of
/// the **sound pack**, a release of `beejsbj/meditejo` the app downloads from
/// on request. The library lists both, so the Sounds screen, the credits and
/// the mixer know every sound whether or not its file is on the phone.
library;

import '../../services/updates/update_release.dart' show kReleaseDownloadPrefix;

const kSoundLibraryAsset = 'assets/sounds/sounds.json';

/// Shelves of the Sounds screen, in display order.
enum SoundCategory {
  rain,
  water,
  wind,
  forest,
  fire,
  room,
  night;

  static SoundCategory? tryParse(String? value) {
    for (final c in values) {
      if (c.name == value) return c;
    }
    return null;
  }
}

/// A licence a bundled sound may carry. Anything else is refused at build
/// time by the processing script, and ignored here.
enum SoundLicense {
  cc0(
    'CC0-1.0',
    'CC0 1.0',
    'https://creativecommons.org/publicdomain/zero/1.0/',
  ),
  ccBy3(
    'CC-BY-3.0',
    'CC BY 3.0',
    'https://creativecommons.org/licenses/by/3.0/',
  ),
  ccBy4(
    'CC-BY-4.0',
    'CC BY 4.0',
    'https://creativecommons.org/licenses/by/4.0/',
  ),
  publicDomain('PD', 'Public domain', '');

  const SoundLicense(this.spdx, this.label, this.url);

  final String spdx;
  final String label;
  final String url;

  /// CC BY sounds must be credited, with their modifications indicated.
  bool get requiresAttribution => this == ccBy3 || this == ccBy4;

  static SoundLicense? tryParse(String? spdx) {
    for (final l in values) {
      if (l.spdx == spdx) return l;
    }
    return null;
  }
}

class SoundEntry {
  const SoundEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.asset,
    required this.license,
    required this.author,
    required this.sourceUrl,
    this.originalTitle = '',
    this.authorUrl = '',
    this.durationMs = 0,
    this.channels = 2,
    this.modifications = '',
    this.file = '',
    this.bundled = true,
    this.sha256 = '',
    this.bytes = 0,
  });

  final String id;
  final String title;
  final SoundCategory category;

  /// Flutter asset path of the loop (Ogg Opus). Only a [bundled] sound has
  /// one in the APK; for a pack sound it names where the file would be.
  final String asset;

  /// The file's name, here and on the pack release (`<id>.opus`).
  final String file;

  /// In the APK, as opposed to a download from the sound pack.
  final bool bundled;

  /// Lower-case hex SHA-256 and size of the file: what a download must be.
  final String sha256;
  final int bytes;
  final SoundLicense license;
  final String author;
  final String authorUrl;
  final String originalTitle;
  final String sourceUrl;
  final int durationMs;

  /// 1 or 2: the engine plays stereo loops at unity in both channels.
  final int channels;

  /// What was changed from the original, for the credit line.
  final String modifications;

  /// `null` for an entry this build can't use (unknown category or
  /// licence), so a hand-edited JSON can't put an unvetted sound on screen.
  static SoundEntry? tryFromJson(Map<String, Object?> json) {
    final category = SoundCategory.tryParse(json['category'] as String?);
    final license = SoundLicense.tryParse(
      (json['license'] as Map?)?['spdx'] as String?,
    );
    final id = json['id'];
    if (category == null || license == null || id is! String) return null;
    final file = json['file'] as String? ?? '$id.opus';
    final asset = json['asset'] as String? ?? 'assets/sounds/$file';
    final bundled = json['bundled'] != false;
    final sha256 = json['sha256'] as String? ?? '';
    final bytes = (json['bytes'] as num?)?.toInt() ?? 0;
    // A download is only ever accepted against a pinned hash and size.
    if (!bundled && (!_sha256.hasMatch(sha256) || bytes <= 0)) return null;
    return SoundEntry(
      id: id,
      title: json['title'] as String? ?? id,
      category: category,
      asset: asset,
      license: license,
      author: json['author'] as String? ?? '',
      authorUrl: json['authorUrl'] as String? ?? '',
      originalTitle: json['originalTitle'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      channels: (json['channels'] as num?)?.toInt() == 1 ? 1 : 2,
      modifications: json['modifications'] as String? ?? '',
      file: file,
      bundled: bundled,
      sha256: sha256,
      bytes: bytes,
    );
  }
}

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
final _packTag = RegExp(r'^sounds-\d{8}(-\d+)?$');

/// The release the sound pack is published as: the library's `pack` section.
class SoundPackPin {
  const SoundPackPin(this.release);

  /// `sounds-YYYYMMDD[-n]`, a prerelease of `beejsbj/meditejo`.
  final String release;

  static SoundPackPin? tryFromJson(Object? json) {
    final release = json is Map ? json['release'] : null;
    if (release is! String || !_packTag.hasMatch(release)) return null;
    return SoundPackPin(release);
  }

  /// Where [sound]'s file is published. Under the repository's release
  /// downloads and nowhere else; the updater never reads this release.
  Uri urlFor(SoundEntry sound) =>
      Uri.parse('$kReleaseDownloadPrefix$release/${sound.file}');
}

class SoundLibrary {
  SoundLibrary(List<SoundEntry> sounds, {this.pack})
    : sounds = List.unmodifiable(sounds),
      _byId = {for (final s in sounds) s.id: s};

  static final empty = SoundLibrary(const []);

  factory SoundLibrary.fromJson(Map<String, Object?> json) {
    final raw = json['sounds'];
    final sounds = <SoundEntry>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final entry = SoundEntry.tryFromJson(item.cast<String, Object?>());
          if (entry != null) sounds.add(entry);
        }
      }
    }
    return SoundLibrary(sounds, pack: SoundPackPin.tryFromJson(json['pack']));
  }

  final List<SoundEntry> sounds;

  /// Where the downloadable sounds are published; null when none is pinned,
  /// in which case they can't be fetched.
  final SoundPackPin? pack;

  /// The sounds that are a download, not part of the APK.
  List<SoundEntry> get packSounds => [
    for (final s in sounds)
      if (!s.bundled) s,
  ];
  final Map<String, SoundEntry> _byId;

  SoundEntry? operator [](String id) => _byId[id];

  bool contains(String id) => _byId.containsKey(id);

  List<SoundEntry> inCategory(SoundCategory category) => [
    for (final s in sounds)
      if (s.category == category) s,
  ];

  /// Categories that hold at least one sound, in display order.
  List<SoundCategory> get categories => [
    for (final c in SoundCategory.values)
      if (sounds.any((s) => s.category == c)) c,
  ];
}
