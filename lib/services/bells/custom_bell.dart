import 'package:medito/services/bells/bell_recipe.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell_id.dart';

export 'package:medito/services/bells/custom_bell_id.dart';

/// The longest name a bell takes.
const maxCustomBellNameLength = 40;

/// A name as it is stored: whitespace collapsed, trimmed and cut short. Null
/// when nothing is left.
String? cleanBellName(String? name) {
  final text = (name ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  return text.length <= maxCustomBellNameLength
      ? text
      : text.substring(0, maxCustomBellNameLength).trimRight();
}

/// A bell the user made: a shipped bell to start from ([preset]) and the
/// five controls moved from it, which is all it takes to make its sound
/// again. The WAV itself is a cache of [spec]'s render.
class CustomBell {
  const CustomBell({
    required this.id,
    required this.name,
    required this.preset,
    required this.knobs,
    required this.createdAtMs,
  });

  /// `custom-bell:<token>`: what a cue stores.
  final String id;
  final String name, preset;
  final BellKnobs knobs;
  final int createdAtMs;

  BellSpec get spec => BellSpec(preset, knobs);

  /// The token in [id], which names the bell's file.
  String get token => id.substring(customBellPrefix.length);

  CustomBell copyWith({String? name}) => CustomBell(
    id: id,
    name: name ?? this.name,
    preset: preset,
    knobs: knobs,
    createdAtMs: createdAtMs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'preset': preset,
    'knobs': knobs.toJson(),
    'createdAt': createdAtMs,
  };

  /// Null for anything that is not a bell this version can make.
  static CustomBell? tryFromJson(Object? json) {
    try {
      if (json is! Map) return null;
      final id = json['id'];
      final name = cleanBellName(json['name'] as String?);
      final preset = json['preset'];
      if (id is! String || !isCustomBellId(id) || name == null) return null;
      if (preset is! String) return null;
      final knobs = BellKnobs.fromJson(
        (json['knobs']! as Map).cast<String, Object?>(),
      );
      // Throws for a preset this version doesn't have.
      final spec = BellSpec(preset, knobs);
      final created = json['createdAt'];
      return CustomBell(
        id: id,
        name: name,
        preset: preset,
        knobs: spec.knobs,
        createdAtMs: created is num ? created.toInt() : 0,
      );
    } catch (_) {
      return null;
    }
  }
}
