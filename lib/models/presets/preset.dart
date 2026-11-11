import 'package:flutter/foundation.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/soundscape/sound_mix.dart';

/// The four things a preset can hold (#64). A preset keeps only the slots
/// that were set; an empty slot leaves whatever is there as it is.
enum PresetSlot { sound, bells, rhythm, length }

/// A slice of [CueSettings]: the fields one slot holds, read and written
/// through [CueSettings] so a bell id follows the same rules as a cue's.
///
/// Stored canonically, so two slices that sound the same are equal: an
/// interval bell or a pulse that is off is off, whatever rate it remembers.
@immutable
class PresetCues {
  const PresetCues._(this._values);

  /// The three bells, with the countdown before the starting bell and how
  /// often the interval bell rings. Not a preset's: the volume all bells
  /// share, and the silence before the ending bell, which (like Extend)
  /// makes a recording longer, and a recording owns its length.
  static const bellKeys = [
    'startSound',
    'countdownSeconds',
    'endSound',
    'intervalSound',
    'intervalMinutes',
    'randomWindowMinutes',
    'intervalHalfway',
  ];

  static const rhythmKeys = [
    'pulseSound',
    'pulseBpm',
    'pulseEndBpm',
    'pulseRampMinutes',
    'pulseVolume',
  ];

  factory PresetCues.bells(CueSettings s) {
    const d = CueSettings();
    final ringing = s.hasIntervalBell;
    final every = ringing && !s.intervalHalfway;
    return PresetCues._({
      'startSound': s.startSound,
      'countdownSeconds': s.countdownSeconds,
      'endSound': s.endSound,
      'intervalSound': ringing ? s.intervalSound : d.intervalSound,
      'intervalMinutes': every ? s.intervalMinutes : 0,
      'randomWindowMinutes': every ? s.randomWindowMinutes : 0,
      'intervalHalfway': ringing && s.intervalHalfway,
    });
  }

  factory PresetCues.rhythm(CueSettings s) {
    const d = CueSettings();
    final on = s.pulseSound.isNotEmpty;
    final ramp = on && s.pulseRampMinutes > 0;
    return PresetCues._({
      'pulseSound': s.pulseSound,
      'pulseBpm': on ? s.pulseBpm : d.pulseBpm,
      'pulseEndBpm': ramp ? s.pulseEndBpm : d.pulseEndBpm,
      'pulseRampMinutes': ramp ? s.pulseRampMinutes : 0,
      'pulseVolume': on ? s.pulseVolume : d.pulseVolume,
    });
  }

  /// A stored slice; null when [json] is not one. Missing or damaged fields
  /// read as [CueSettings] reads them.
  static PresetCues? _tryFromJson(Object? json, {required bool bells}) {
    if (json is! Map) return null;
    final settings = CueSettings.fromJson({
      for (final key in bells ? bellKeys : rhythmKeys)
        if (json.containsKey(key)) key: json[key],
    });
    return bells ? PresetCues.bells(settings) : PresetCues.rhythm(settings);
  }

  final Map<String, Object?> _values;

  Map<String, Object?> toJson() => {..._values};

  /// [settings] with this slot's fields put in.
  CueSettings applyTo(CueSettings settings) =>
      CueSettings.fromJson({...settings.toJson(), ..._values});

  /// These fields as settings of their own (the rest at their defaults), to
  /// read a bell's or the pulse's name from.
  CueSettings get asSettings => CueSettings.fromJson(_values);

  @override
  bool operator ==(Object other) =>
      other is PresetCues && mapEquals(other._values, _values);

  @override
  int get hashCode => Object.hashAll(_values.values);
}

/// How long a sit is: so many minutes, or open-ended (∞, counting up).
@immutable
class PresetLength {
  const PresetLength.minutes(int this.minutes);
  const PresetLength.openEnded() : minutes = null;

  /// Null when open-ended.
  final int? minutes;

  bool get openEnded => minutes == null;

  Map<String, Object?> toJson() =>
      openEnded ? {'openEnded': true} : {'minutes': minutes};

  static PresetLength? tryFromJson(Object? json) {
    if (json is! Map) return null;
    if (json['openEnded'] == true) return const PresetLength.openEnded();
    final minutes = json['minutes'];
    if (minutes is! num || !minutes.isFinite) return null;
    return PresetLength.minutes(minutes.toInt().clamp(1, 299));
  }

  @override
  bool operator ==(Object other) =>
      other is PresetLength && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;
}

/// Values for the four slots; null where a slot is empty. A preset's
/// content, and also how the settings on screen are read to compare with
/// one or to save as one.
@immutable
class PresetSlots {
  const PresetSlots({this.sound, this.bells, this.rhythm, this.length});

  static const none = PresetSlots();

  /// The sound layers (the mix). An empty mix is silence, chosen.
  final SoundMix? sound;
  final PresetCues? bells;
  final PresetCues? rhythm;
  final PresetLength? length;

  Object? operator [](PresetSlot slot) => switch (slot) {
    PresetSlot.sound => sound,
    PresetSlot.bells => bells,
    PresetSlot.rhythm => rhythm,
    PresetSlot.length => length,
  };

  bool has(PresetSlot slot) => this[slot] != null;

  /// The slots that hold something, in their fixed order.
  Set<PresetSlot> get filled => {
    for (final slot in PresetSlot.values)
      if (has(slot)) slot,
  };

  bool get isEmpty => filled.isEmpty;

  /// Only [slots] of these.
  PresetSlots only(Set<PresetSlot> slots) => PresetSlots(
    sound: slots.contains(PresetSlot.sound) ? sound : null,
    bells: slots.contains(PresetSlot.bells) ? bells : null,
    rhythm: slots.contains(PresetSlot.rhythm) ? rhythm : null,
    length: slots.contains(PresetSlot.length) ? length : null,
  );

  /// These with every slot [over] holds put in over them: how an empty slot
  /// falls through to what is underneath.
  PresetSlots withSlots(PresetSlots over) => PresetSlots(
    sound: over.sound ?? sound,
    bells: over.bells ?? bells,
    rhythm: over.rhythm ?? rhythm,
    length: over.length ?? length,
  );

  /// Which of [among] differ between these and [other].
  Set<PresetSlot> differing(PresetSlots other, Iterable<PresetSlot> among) => {
    for (final slot in among)
      if (this[slot] != other[slot]) slot,
  };

  @override
  bool operator ==(Object other) =>
      other is PresetSlots &&
      other.sound == sound &&
      other.bells == bells &&
      other.rhythm == rhythm &&
      other.length == length;

  @override
  int get hashCode => Object.hash(sound, bells, rhythm, length);
}

/// The saved thing: a name and up to four slots (Sound, Bells, Rhythm,
/// Length). Built-in presets ship with the app and can't be changed or
/// deleted. "Mix" is only the sound layers, one of its ingredients.
@immutable
class Preset {
  const Preset({
    required this.id,
    required this.name,
    this.slots = PresetSlots.none,
    this.builtIn = false,
    Map<String, Object?> extra = const {},
  }) : _extra = extra;

  /// A preset holding only a mix: what every preset was before #64.
  Preset.sound({
    required String id,
    required String name,
    required SoundMix mix,
    bool builtIn = false,
  }) : this(
         id: id,
         name: name,
         slots: PresetSlots(sound: mix),
         builtIn: builtIn,
       );

  final String id;
  final String name;
  final PresetSlots slots;
  final bool builtIn;

  /// Fields a newer version wrote that this one does not know: kept, so
  /// saving the list here does not drop them.
  final Map<String, Object?> _extra;

  /// Its sound layers; empty when it holds no sound.
  SoundMix get mix => slots.sound ?? SoundMix.empty;

  /// Whether it has sound layers to play.
  bool get playsSound => !mix.isEmpty;

  Preset copyWith({String? name, PresetSlots? slots}) => Preset(
    id: id,
    name: name ?? this.name,
    slots: slots ?? this.slots,
    builtIn: builtIn,
    extra: _extra,
  );

  static const _known = {'id', 'name', 'layers', 'bells', 'rhythm', 'length'};

  /// `layers` is the Sound slot, under the name a saved mix always had: a
  /// preset stored before #64 (`{id, name, layers}`) reads as one with only
  /// its sound set.
  Map<String, Object?> toJson() => {
    ..._extra,
    'id': id,
    'name': name,
    if (slots.sound case final sound?) 'layers': sound.toJson(),
    if (slots.bells case final bells?) 'bells': bells.toJson(),
    if (slots.rhythm case final rhythm?) 'rhythm': rhythm.toJson(),
    if (slots.length case final length?) 'length': length.toJson(),
  };

  /// Null when [json] has no id or name. A slot that will not parse reads
  /// as empty; the rest of the preset stands.
  static Preset? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! String || name is! String || id.isEmpty) return null;
    return Preset(
      id: id,
      name: name,
      slots: PresetSlots(
        sound: json['layers'] is List
            ? SoundMix.fromJson(json['layers'])
            : null,
        bells: PresetCues._tryFromJson(json['bells'], bells: true),
        rhythm: PresetCues._tryFromJson(json['rhythm'], bells: false),
        length: PresetLength.tryFromJson(json['length']),
      ),
      extra: {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String && !_known.contains(key)) key: value,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Preset &&
      other.id == id &&
      other.name == name &&
      other.slots == slots &&
      other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(id, name, slots, builtIn);
}
