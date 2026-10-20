import 'package:flutter/foundation.dart';

/// One layer of a mix: a sound from the library at its own volume.
@immutable
class SoundLayer {
  const SoundLayer({
    required this.soundId,
    this.volume = kDefaultLayerVolume,
    this.animate = false,
    this.params = const {},
  });

  static const kDefaultLayerVolume = 0.6;

  final String soundId;

  /// Slider position, 0–1. The engine squares it into a gain.
  final double volume;

  /// Slow drift of this layer's level, so a long sit doesn't sound static.
  final bool animate;

  /// Settings for a generated layer (noise bands, drone root, …). Empty for
  /// recordings. Kept as plain JSON so presets survive new kinds of layer.
  final Map<String, Object?> params;

  SoundLayer copyWith({
    double? volume,
    bool? animate,
    Map<String, Object?>? params,
  }) => SoundLayer(
    soundId: soundId,
    volume: volume ?? this.volume,
    animate: animate ?? this.animate,
    params: params ?? this.params,
  );

  Map<String, Object?> toJson() => {
    'soundId': soundId,
    'volume': volume,
    if (animate) 'animate': true,
    if (params.isNotEmpty) 'params': params,
  };

  static SoundLayer? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['soundId'];
    if (id is! String || id.isEmpty) return null;
    final volume = (json['volume'] as num?)?.toDouble() ?? kDefaultLayerVolume;
    final params = json['params'];
    return SoundLayer(
      soundId: id,
      volume: volume.clamp(0.0, 1.0),
      animate: json['animate'] == true,
      params: params is Map ? params.cast<String, Object?>() : const {},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SoundLayer &&
      other.soundId == soundId &&
      other.volume == volume &&
      other.animate == animate &&
      paramsEqual(other.params, params);

  @override
  int get hashCode =>
      Object.hash(soundId, volume, animate, _paramsHash(params));

  /// Settings compared by value: a preset read back from storage holds new
  /// lists, which must still match the mix it was saved from.
  static bool paramsEqual(Map<String, Object?> a, Map<String, Object?> b) =>
      _deepEquals(a, b);
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  // JSON numbers: 1 and 1.0 are the same setting.
  if (a is num && b is num) return a == b;
  return a == b;
}

int _paramsHash(Object? v) => switch (v) {
  Map() => Object.hashAllUnordered(
    v.entries.map((e) => Object.hash(e.key, _paramsHash(e.value))),
  ),
  List() => Object.hashAll(v.map(_paramsHash)),
  num() => v.toDouble().hashCode,
  _ => v.hashCode,
};

/// Layers playing together. At most one layer per sound.
@immutable
class SoundMix {
  const SoundMix([this.layers = const []]);

  static const empty = SoundMix();

  /// How many layers can play at once. Each recording is decoded into
  /// memory (about 22 MiB a minute of 48 kHz stereo; DECISIONS has the
  /// worst case), so this bounds memory too.
  static const kMaxLayers = 6;

  final List<SoundLayer> layers;

  bool get isEmpty => layers.isEmpty;

  bool contains(String soundId) => layers.any((l) => l.soundId == soundId);

  SoundLayer? layer(String soundId) {
    for (final l in layers) {
      if (l.soundId == soundId) return l;
    }
    return null;
  }

  /// Adds [layer], or replaces the layer for the same sound in place.
  SoundMix put(SoundLayer layer) {
    final i = layers.indexWhere((l) => l.soundId == layer.soundId);
    if (i == -1) return SoundMix([...layers, layer]);
    return SoundMix([...layers]..[i] = layer);
  }

  SoundMix remove(String soundId) => SoundMix([
    for (final l in layers)
      if (l.soundId != soundId) l,
  ]);

  /// Keeps only layers whose sound [isKnown] (a preset made with a sound a
  /// later build dropped still plays the rest).
  SoundMix where(bool Function(String soundId) isKnown) => SoundMix([
    for (final l in layers)
      if (isKnown(l.soundId)) l,
  ]);

  List<Object?> toJson() => [for (final l in layers) l.toJson()];

  static SoundMix fromJson(Object? json) {
    if (json is! List) return empty;
    final seen = <String>{};
    final layers = <SoundLayer>[];
    for (final item in json) {
      final layer = SoundLayer.tryFromJson(item);
      if (layer != null && seen.add(layer.soundId)) layers.add(layer);
    }
    return SoundMix(layers.take(kMaxLayers).toList());
  }

  @override
  bool operator ==(Object other) =>
      other is SoundMix && listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hashAll(layers);
}

/// A named mix. Built-in presets ship with the app and can't be deleted.
@immutable
class SoundPreset {
  const SoundPreset({
    required this.id,
    required this.name,
    required this.mix,
    this.builtIn = false,
  });

  final String id;
  final String name;
  final SoundMix mix;
  final bool builtIn;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'layers': mix.toJson(),
  };

  static SoundPreset? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String || id.isEmpty) return null;
    return SoundPreset(
      id: id,
      name: name,
      mix: SoundMix.fromJson(json['layers']),
    );
  }
}

/// What to play: the grammar shared with the player's Customize sheet.
///
/// * `mix` (or the empty string): the current mix, as last left on the
///   Sounds screen;
/// * `preset:<id>`: a preset;
/// * `sound:<id>`: one sound on its own;
/// * `none`: silence.
@immutable
class SoundscapeSelection {
  const SoundscapeSelection._(this.kind, [this.id = '']);

  static const currentMix = SoundscapeSelection._(SoundscapeSelectionKind.mix);
  static const none = SoundscapeSelection._(SoundscapeSelectionKind.none);

  const SoundscapeSelection.preset(String id)
    : this._(SoundscapeSelectionKind.preset, id);

  const SoundscapeSelection.sound(String id)
    : this._(SoundscapeSelectionKind.sound, id);

  final SoundscapeSelectionKind kind;
  final String id;

  static SoundscapeSelection parse(String? value) =>
      tryParse(value) ?? currentMix;

  /// [value] in the grammar above, or null when it is not one (a damaged
  /// value, or a kind a newer version added): the caller picks the
  /// fallback. Empty is `mix`.
  static SoundscapeSelection? tryParse(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty || v == 'mix') return currentMix;
    if (v == 'none') return none;
    if (v.startsWith('preset:') && v.length > 7) {
      return SoundscapeSelection.preset(v.substring(7));
    }
    if (v.startsWith('sound:') && v.length > 6) {
      return SoundscapeSelection.sound(v.substring(6));
    }
    return null;
  }

  String encode() => switch (kind) {
    SoundscapeSelectionKind.mix => 'mix',
    SoundscapeSelectionKind.none => 'none',
    SoundscapeSelectionKind.preset => 'preset:$id',
    SoundscapeSelectionKind.sound => 'sound:$id',
  };

  @override
  bool operator ==(Object other) =>
      other is SoundscapeSelection && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => encode();
}

enum SoundscapeSelectionKind { mix, preset, sound, none }

/// Which kind of session a soundscape plays under (decision 8).
enum SoundscapeSessionKind { practice, talks }

/// What plays under one kind of session, and how loud.
@immutable
class SoundscapeSessionDefault {
  const SoundscapeSessionDefault({
    required this.enabled,
    this.selection = SoundscapeSelection.currentMix,
    this.volume = 0.5,
  });

  /// Decision 8: on for Practice, off for Talks.
  static SoundscapeSessionDefault initial(SoundscapeSessionKind kind) =>
      switch (kind) {
        SoundscapeSessionKind.practice => const SoundscapeSessionDefault(
          enabled: true,
        ),
        SoundscapeSessionKind.talks => const SoundscapeSessionDefault(
          enabled: false,
          volume: 0.35,
        ),
      };

  final bool enabled;
  final SoundscapeSelection selection;

  /// Master level under the session, 0–1.
  final double volume;

  SoundscapeSessionDefault copyWith({
    bool? enabled,
    SoundscapeSelection? selection,
    double? volume,
  }) => SoundscapeSessionDefault(
    enabled: enabled ?? this.enabled,
    selection: selection ?? this.selection,
    volume: volume ?? this.volume,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'selection': selection.encode(),
    'volume': volume,
  };

  static SoundscapeSessionDefault fromJson(
    Object? json,
    SoundscapeSessionKind kind,
  ) {
    final fallback = initial(kind);
    if (json is! Map) return fallback;
    return SoundscapeSessionDefault(
      enabled: json['enabled'] is bool
          ? json['enabled'] as bool
          : fallback.enabled,
      selection: SoundscapeSelection.parse(json['selection'] as String?),
      volume: ((json['volume'] as num?)?.toDouble() ?? fallback.volume).clamp(
        0.0,
        1.0,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SoundscapeSessionDefault &&
      other.enabled == enabled &&
      other.selection == selection &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(enabled, selection, volume);
}
