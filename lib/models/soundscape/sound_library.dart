/// The bundled sound library, read from `assets/sounds/sounds.json`.
///
/// The JSON is written by `tools/meditejo/sounds/process_sounds.py`, which
/// also writes `assets/sounds/NOTICE`. Each sound keeps its own licence: the
/// recordings are data aggregated with the app, outside the AGPL.
library;

const kSoundLibraryAsset = 'assets/sounds/sounds.json';

/// Recordings shown as one card, with a choice of which one plays (pass 4:
/// "Metro carriage and Yamanote Line train should be one sound"). The key
/// is the card's own sound; the list is every variant, in chip order.
///
/// Each variant stays a sound of its own, in the library, in mixes and in
/// presets: a stored mix that names either id plays what it always did, and
/// nothing stored is rewritten.
const kSoundVariants = <String, List<String>>{
  'train': ['train', 'train-yamanote'],
};

/// The card [soundId] is shown under: its family's, or its own.
String soundCardId(String soundId) {
  for (final MapEntry(:key, :value) in kSoundVariants.entries) {
    if (value.contains(soundId)) return key;
  }
  return soundId;
}

/// Every variant of [soundId]'s card; just [soundId] when it has none.
List<String> soundVariants(String soundId) =>
    kSoundVariants[soundCardId(soundId)] ?? [soundId];

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
  });

  final String id;
  final String title;
  final SoundCategory category;

  /// Flutter asset path of the loop (Ogg Opus).
  final String asset;
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
    final asset = json['asset'];
    if (category == null || license == null || id is! String) return null;
    if (asset is! String) return null;
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
    );
  }
}

class SoundLibrary {
  SoundLibrary(List<SoundEntry> sounds)
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
    return SoundLibrary(sounds);
  }

  final List<SoundEntry> sounds;
  final Map<String, SoundEntry> _byId;

  SoundEntry? operator [](String id) => _byId[id];

  bool contains(String id) => _byId.containsKey(id);

  List<SoundEntry> inCategory(SoundCategory category) => [
    for (final s in sounds)
      if (s.category == category) s,
  ];

  /// The sounds of [category] that get a card: a variant other than its
  /// card's own is chosen on that card (unless this library lacks it).
  List<SoundEntry> cardsIn(SoundCategory category) => [
    for (final s in sounds)
      if (s.category == category &&
          (soundCardId(s.id) == s.id || !contains(soundCardId(s.id))))
        s,
  ];

  /// Categories that hold at least one sound, in display order.
  List<SoundCategory> get categories => [
    for (final c in SoundCategory.values)
      if (sounds.any((s) => s.category == c)) c,
  ];
}
