import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/widgets/art/engine/compose.dart';

/// What a piece of art stands for: a sound, a preset or mix, a course,
/// playlist, single or teacher, or a bell (as a card or as an icon).
///
/// Art is keyed by **id**, never by title, so an item keeps its art when
/// it's renamed (decision 22: what users add is generated, seeded by id).
@immutable
sealed class ArtSubject {
  const ArtSubject();

  const factory ArtSubject.sound(String id, [Map<String, Object?> params]) =
      SoundArt;
  const factory ArtSubject.layers(String id, List<SoundLayer> layers) = MixArt;
  const factory ArtSubject.cover(ArtCoverKind kind, String id) = CoverArt;
  const factory ArtSubject.bell(String asset, {bool icon}) = BellArt;

  /// Stable across runs: the raster cache's key.
  String get key;
}

/// One sound from the library, or a generated layer with its settings.
final class SoundArt extends ArtSubject {
  const SoundArt(this.id, [this.params = const {}]);

  final String id;
  final Map<String, Object?> params;

  @override
  String get key => 'sound:${artSoundId(id, params)}';

  @override
  bool operator ==(Object other) => other is SoundArt && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A preset, or the current mix: the loudest layer's ground and figure,
/// the next layer's figure as its accent. [id] is the preset's id, or
/// [current] for a mix that matches no preset.
final class MixArt extends ArtSubject {
  const MixArt(this.id, this.layers);

  /// The id of the current mix when it matches no preset.
  static const current = 'mix';

  final String id;
  final List<SoundLayer> layers;

  /// The art ids of the two loudest layers, in order: all a mix's art
  /// depends on.
  List<String> get leading {
    final sorted = [for (var i = 0; i < layers.length; i++) (i, layers[i])]
      ..sort((a, b) {
        final c = b.$2.volume.compareTo(a.$2.volume);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    return [
      for (final (_, l) in sorted.take(2)) artSoundId(l.soundId, l.params),
    ];
  }

  @override
  String get key => 'mix:$id:${leading.join('+')}';

  @override
  bool operator ==(Object other) => other is MixArt && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

enum ArtCoverKind { course, playlist, single, teacher }

/// A course, playlist, single or teacher's cover.
final class CoverArt extends ArtSubject {
  const CoverArt(this.kind, this.id);

  final ArtCoverKind kind;
  final String id;

  @override
  String get key => 'cover:${kind.name}:$id';

  @override
  bool operator ==(Object other) => other is CoverArt && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// A bell, by its sound's asset path: its card, or its icon.
final class BellArt extends ArtSubject {
  const BellArt(this.asset, {this.icon = false});

  final String asset;
  final bool icon;

  @override
  String get key => 'bell:${icon ? 'icon' : 'card'}:$asset';

  @override
  bool operator ==(Object other) => other is BellArt && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// The id the meaning map knows a mix layer by. Generated layers are named
/// for what they are: the noise by its colour (`noise-brown`), the drone
/// and binaural beats by their kind.
String artSoundId(String soundId, Map<String, Object?> params) =>
    switch (soundId) {
      kSynthNoiseId => 'noise-${NoiseParams.fromJson(params).colour.name}',
      kSynthDroneId => 'drone',
      kSynthBinauralId => 'binaural',
      _ => soundId,
    };

/// The shipped art (`assets/art/curated_art.json`, frozen on
/// `fork/mark-explore` in identity round 5): every built-in sound, preset,
/// starter item and bell has a hand-picked composition, drawn from its
/// frozen params and never rebuilt, so later engine changes can't move it
/// (decision 22). Everything else is built from its id by [Compose].
class CuratedArt extends ChangeNotifier {
  CuratedArt._();

  static final instance = CuratedArt._();

  static const asset = 'assets/art/curated_art.json';

  Map<String, Map<String, Object?>>? _items;
  Future<void>? _loading;
  final _resolved = <String, ArtComposition?>{};

  bool get loaded => _items != null;

  /// Starts reading the asset, once; listeners hear when it's in.
  Future<void> load([AssetBundle? bundle]) =>
      _loading ??= (bundle ?? rootBundle)
          .loadString(asset)
          .then((text) {
            useJson(text);
          })
          .catchError((Object e) {
            _loading = null;
            AppLogger.e('ART', 'Curated art failed to load', e);
          });

  /// Uses [text] as the curated file (the asset's contents).
  void useJson(String text) {
    final items = (jsonDecode(text) as Map)['items'] as Map;
    _items = {
      for (final e in items.entries)
        e.key as String: (e.value as Map).cast<String, Object?>(),
    };
    _resolved.clear();
    notifyListeners();
  }

  /// The curated entry for [id], if there is one.
  Map<String, Object?>? entry(String id) => _items?[id];

  /// Ids with a curated entry.
  Iterable<String> get ids => _items?.keys ?? const [];

  /// [subject]'s composition: its frozen entry when it ships, else built
  /// from its id. Null when the meaning map has nothing for it (a sound it
  /// doesn't know), or before the curated file is in, for subjects that
  /// may be curated.
  ArtComposition? resolve(ArtSubject subject) {
    if (_items == null) return null;
    final key = subject.key;
    if (_resolved.containsKey(key)) return _resolved[key];
    return _resolved[key] = _resolve(subject);
  }

  ArtComposition? _resolve(ArtSubject subject) {
    switch (subject) {
      case SoundArt(:final id, :final params):
        final artId = artSoundId(id, params);
        return _frozen(artId) ?? Compose.buildFor(artId, 'sound');
      case MixArt(:final id, :final layers):
        final frozen = _frozen(id);
        final leading = subject.leading;
        // A preset that ships keeps its card while its two loudest layers
        // are still the ones it was curated with.
        if (frozen != null && _sameLeading(id, leading)) return frozen;
        // A user's preset is seeded by its id, like anything a user makes.
        // The current mix, which has no id of its own, by its leading pair,
        // so the same blend always reads the same.
        return Compose.buildPreset((
          id: id == MixArt.current ? 'mix:${leading.join('+')}' : id,
          layers: [
            for (final l in layers) (artSoundId(l.soundId, l.params), l.volume),
          ],
        ));
      case CoverArt(:final kind, :final id):
        return _frozen(id) ??
            Compose.buildFor(id, switch (kind) {
              ArtCoverKind.course => 'course',
              ArtCoverKind.playlist => 'playlist',
              ArtCoverKind.single => 'single',
              ArtCoverKind.teacher => 'teacher',
            });
      case BellArt(:final asset, :final icon):
        // Every shipped bell is curated, and its entry names its asset.
        final e = _items!.values
            .where((v) => v['kind'] == 'bell' && v['asset'] == asset)
            .firstOrNull;
        if (e == null) return null;
        return ArtComposition.thaw(
          (e[icon ? 'icon' : 'card']! as Map).cast<String, Object?>(),
        );
    }
  }

  ArtComposition? _frozen(String id) {
    final e = entry(id);
    if (e == null || e['kind'] == 'bell') return null;
    return ArtComposition.thaw(e);
  }

  // The leading pair the curated preset was frozen from (shipped.js).
  static const _curatedLeading = {
    'starter-rain-forest': ['rain-terrace', 'forest-birds'],
    'starter-night': ['night-meadow', 'stream'],
    'starter-hearth': ['fire-stove', 'fire-crackle'],
    'starter-shore': ['waves', 'wind-grass'],
    'starter-stillness': ['noise-brown', 'drone'],
  };

  static bool _sameLeading(String id, List<String> leading) {
    final want = _curatedLeading[id];
    return want == null || listEquals(want, leading);
  }
}
