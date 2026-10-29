import 'dart:convert';

import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/pauses/pause_hold.dart';
import 'package:medito/services/bells/custom_bell_id.dart';

/// Playback preferences are independent of a source's audio metadata.
enum CueKind { practice, talks }

/// The bells each cue can ring, in the order the pickers list them. The value
/// is the stored id: a bundled asset path, kept stable for every existing
/// setting (`session_bell_v2.wav` is the original bell).
const cueBellSounds = <String, String>{
  'Off': '',
  'Swell bell': 'assets/audio/session_bell_v2.wav',
  'Singing bowl, small': 'assets/audio/bell_bowl_small.wav',
  'Singing bowl': 'assets/audio/bell_bowl_medium.wav',
  'Singing bowl, deep': 'assets/audio/bell_bowl_deep.wav',
  'Temple bell': 'assets/audio/bell_temple.wav',
  'Hand bell': 'assets/audio/bell_handbell.wav',
  'Chime': 'assets/audio/bell_chime.wav',
  'Tingsha': 'assets/audio/bell_tingsha.wav',
  'Wood block': 'assets/audio/bell_wood_block.wav',
  'Wooden fish': 'assets/audio/bell_wooden_fish.wav',
  'Gong': 'assets/audio/bell_gong.wav',
};

/// The bell a cue rings when nothing else is chosen, and when the bell it
/// had was deleted.
const cueDefaultBell = 'assets/audio/session_bell_v2.wav';
const cuePulseSounds = <String, String>{
  'Off': '',
  'Soft click': 'assets/audio/pulse_click.wav',
  'Heartbeat': 'assets/audio/pulse_heartbeat.wav',
  'Chirp': 'assets/audio/pulse_chirp.wav',
  'Footstep': 'assets/audio/pulse_footstep.wav',
};

/// A small versioned JSON value; no generated model or database migration.
class CueSettings {
  const CueSettings({
    this.durationMinutes = 10,
    this.extendMinutes = 0,
    this.pauseMinutes = 0,
    this.countdownSeconds = 0,
    this.startSound = cueDefaultBell,
    this.endSound = cueDefaultBell,
    this.intervalSound = cueDefaultBell,
    this.intervalMinutes = 0,
    this.randomWindowMinutes = 0,
    this.intervalHalfway = false,
    this.pulseSound = '',
    this.pulseBpm = 60,
    this.pulseEndBpm = 40,
    this.pulseRampMinutes = 0,
    this.pulseVolume = 0.25,
    this.bellVolume = 0.5,
    this.backgroundEnabled = true,
    this.backgroundSoundId = '',
    this.backgroundVolume = 50,
    this.soundscape = '',
    this.autoplay = false,
    this.interludeSeconds = 0,
    this.hideBeforePractice = false,
  });

  /// The stored format. Unversioned values are read as version 1; a value
  /// written by a newer app is not guessed at and reads as the defaults.
  static const formatVersion = 1;

  factory CueSettings.defaults(CueKind kind) =>
      CueSettings(backgroundEnabled: kind == CueKind.practice);

  final int durationMinutes, extendMinutes, countdownSeconds;

  /// Minutes of silence taken inside the guide's own long pauses, separate
  /// from [extendMinutes] (the silence after the recording, before the ending
  /// bell). What the pauses cannot take, and all of it where they cannot be
  /// used (no usable pauses, iOS, YouTube, a stream not yet read), is held
  /// after the recording too. An older app ignores the key.
  final int pauseMinutes;

  /// All the silence a guided session adds: after the recording and in its
  /// pauses. The session is this much longer than the recording either way.
  int get extraMinutes => extendMinutes + pauseMinutes;
  final String startSound, endSound, intervalSound;
  final int intervalMinutes, randomWindowMinutes;

  /// The interval bell rings once, at the midpoint of session time, instead
  /// of every [intervalMinutes] (which is kept, so switching back restores
  /// it). An older app ignores the key and reads the interval it stored.
  final bool intervalHalfway;

  /// The interval bell rings at all: halfway, or every N minutes.
  bool get hasIntervalBell =>
      intervalSound.isNotEmpty && (intervalHalfway || intervalMinutes > 0);
  final String pulseSound;
  final double pulseBpm, pulseEndBpm, pulseVolume, bellVolume;
  final int pulseRampMinutes;
  final bool backgroundEnabled, autoplay, hideBeforePractice;
  final String backgroundSoundId;
  final double backgroundVolume;

  /// What the soundscape mixer plays under this scope's sessions, in
  /// [SoundscapeSelection]'s grammar (`mix`, `preset:<id>`, `sound:<id>`,
  /// `none`). Empty: whatever the mixer's own default for the kind says
  /// ("Play under practice/talks" and its selection). A selection only: the
  /// mixer owns the on/off default and the volume.
  final String soundscape;

  /// [soundscape] as a selection, or null to follow the mixer's default.
  SoundscapeSelection? get soundscapeSelection =>
      soundscape.isEmpty ? null : SoundscapeSelection.parse(soundscape);
  final int interludeSeconds;

  CueSettings copyWith({
    int? durationMinutes,
    int? extendMinutes,
    int? pauseMinutes,
    int? countdownSeconds,
    String? startSound,
    String? endSound,
    String? intervalSound,
    int? intervalMinutes,
    int? randomWindowMinutes,
    bool? intervalHalfway,
    String? pulseSound,
    double? pulseBpm,
    double? pulseEndBpm,
    int? pulseRampMinutes,
    double? pulseVolume,
    double? bellVolume,
    bool? backgroundEnabled,
    String? backgroundSoundId,
    double? backgroundVolume,
    String? soundscape,
    bool? autoplay,
    int? interludeSeconds,
    bool? hideBeforePractice,
  }) => CueSettings.fromJson({
    ...toJson(),
    'durationMinutes': durationMinutes ?? this.durationMinutes,
    'extendMinutes': extendMinutes ?? this.extendMinutes,
    'pauseMinutes': pauseMinutes ?? this.pauseMinutes,
    'countdownSeconds': countdownSeconds ?? this.countdownSeconds,
    'startSound': startSound ?? this.startSound,
    'endSound': endSound ?? this.endSound,
    'intervalSound': intervalSound ?? this.intervalSound,
    'intervalMinutes': intervalMinutes ?? this.intervalMinutes,
    'randomWindowMinutes': randomWindowMinutes ?? this.randomWindowMinutes,
    'intervalHalfway': intervalHalfway ?? this.intervalHalfway,
    'pulseSound': pulseSound ?? this.pulseSound,
    'pulseBpm': pulseBpm ?? this.pulseBpm,
    'pulseEndBpm': pulseEndBpm ?? this.pulseEndBpm,
    'pulseRampMinutes': pulseRampMinutes ?? this.pulseRampMinutes,
    'pulseVolume': pulseVolume ?? this.pulseVolume,
    'bellVolume': bellVolume ?? this.bellVolume,
    'backgroundEnabled': backgroundEnabled ?? this.backgroundEnabled,
    'backgroundSoundId': backgroundSoundId ?? this.backgroundSoundId,
    'backgroundVolume': backgroundVolume ?? this.backgroundVolume,
    'soundscape': soundscape ?? this.soundscape,
    'autoplay': autoplay ?? this.autoplay,
    'interludeSeconds': interludeSeconds ?? this.interludeSeconds,
    'hideBeforePractice': hideBeforePractice ?? this.hideBeforePractice,
  });

  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'durationMinutes': durationMinutes,
    'extendMinutes': extendMinutes,
    'pauseMinutes': pauseMinutes,
    'countdownSeconds': countdownSeconds,
    'startSound': startSound,
    'endSound': endSound,
    'intervalSound': intervalSound,
    'intervalMinutes': intervalMinutes,
    'randomWindowMinutes': randomWindowMinutes,
    'intervalHalfway': intervalHalfway,
    'pulseSound': pulseSound,
    'pulseBpm': pulseBpm,
    'pulseEndBpm': pulseEndBpm,
    'pulseRampMinutes': pulseRampMinutes,
    'pulseVolume': pulseVolume,
    'bellVolume': bellVolume,
    'backgroundEnabled': backgroundEnabled,
    'backgroundSoundId': backgroundSoundId,
    'backgroundVolume': backgroundVolume,
    'soundscape': soundscape,
    'autoplay': autoplay,
    'interludeSeconds': interludeSeconds,
    'hideBeforePractice': hideBeforePractice,
  };

  factory CueSettings.fromJson(
    Map<String, Object?> json, {
    CueKind kind = CueKind.practice,
  }) {
    final defaults = CueSettings.defaults(kind);
    int integer(String key, int fallback, int min, int max) {
      final value = json[key];
      return (value is num && value.isFinite ? value.toInt() : fallback).clamp(
        min,
        max,
      );
    }

    double number(String key, double fallback, double min, double max) {
      final value = json[key] is num ? (json[key] as num).toDouble() : fallback;
      return value.isFinite ? value.clamp(min, max) : fallback;
    }

    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    // A bell is one that ships or one the user made. A made bell that has
    // since been deleted still reads as itself: whatever plays it (the native
    // resolver, the picker) answers with the default bell, so a missing file
    // never changes what is stored.
    String sound(
      String key,
      String fallback,
      Map<String, String> allowed, {
      bool custom = false,
    }) {
      final value = json[key];
      if (value is! String) return fallback;
      return allowed.containsValue(value) || (custom && isCustomBellId(value))
          ? value
          : fallback;
    }

    // Anything but a selection in the mixer's grammar (a damaged value, or a
    // kind a newer version added) follows the kind's default.
    String soundscape() {
      final value = json['soundscape'];
      if (value is! String || value.trim().isEmpty) return '';
      return SoundscapeSelection.tryParse(value)?.encode() ?? '';
    }

    final countdown = integer('countdownSeconds', 0, 0, 10);
    final interlude = integer('interludeSeconds', 0, 0, 30);
    return CueSettings(
      durationMinutes: integer('durationMinutes', 10, 1, 299),
      extendMinutes: integer('extendMinutes', 0, 0, 60),
      pauseMinutes: integer('pauseMinutes', 0, 0, 60),
      countdownSeconds: [0, 5, 10].contains(countdown) ? countdown : 0,
      startSound: sound(
        'startSound',
        defaults.startSound,
        cueBellSounds,
        custom: true,
      ),
      endSound: sound(
        'endSound',
        defaults.endSound,
        cueBellSounds,
        custom: true,
      ),
      intervalSound: sound(
        'intervalSound',
        defaults.intervalSound,
        cueBellSounds,
        custom: true,
      ),
      intervalMinutes: integer('intervalMinutes', 0, 0, 60),
      randomWindowMinutes: integer('randomWindowMinutes', 0, 0, 60),
      intervalHalfway: flag('intervalHalfway', false),
      pulseSound: sound('pulseSound', '', cuePulseSounds),
      pulseBpm: number('pulseBpm', 60, 20, 120),
      pulseEndBpm: number('pulseEndBpm', 40, 20, 120),
      pulseRampMinutes: integer('pulseRampMinutes', 0, 0, 60),
      pulseVolume: number('pulseVolume', 0.25, 0, 1),
      bellVolume: number('bellVolume', 0.5, 0, 1),
      backgroundEnabled: flag('backgroundEnabled', defaults.backgroundEnabled),
      backgroundSoundId: json['backgroundSoundId'] is String
          ? json['backgroundSoundId'] as String
          : '',
      backgroundVolume: number('backgroundVolume', 50, 0, 100),
      soundscape: soundscape(),
      autoplay: flag('autoplay', false),
      interludeSeconds: [0, 5, 10, 30].contains(interlude) ? interlude : 0,
      hideBeforePractice: flag('hideBeforePractice', false),
    );
  }

  static CueSettings decode(String? value, CueKind kind) {
    try {
      final decoded = value == null ? null : jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return CueSettings.defaults(kind);
      final version = decoded['version'];
      if (version is num && version > formatVersion) {
        return CueSettings.defaults(kind);
      }
      return CueSettings.fromJson(decoded, kind: kind);
    } catch (_) {
      // Whatever is stored, a bad value never stops a session from starting.
      return CueSettings.defaults(kind);
    }
  }

  Duration sessionDuration(Duration audioDuration, {required bool isTimer}) =>
      isTimer
      ? Duration(minutes: durationMinutes)
      : audioDuration + Duration(minutes: extraMinutes);

  DateTime finishesAt(
    DateTime now,
    Duration remainingAudio, {
    required bool isTimer,
    double speed = 1,
  }) => now
      .add(Duration(seconds: countdownSeconds))
      .add(
        isTimer
            ? Duration(minutes: durationMinutes)
            : Duration(
                    microseconds: (remainingAudio.inMicroseconds / speed)
                        .round(),
                  ) +
                  Duration(minutes: extraMinutes),
      );

  /// The engines know one extension: all of [extraMinutes]. [holds] are the
  /// silences to take inside the recording, drawn from [pauseMinutes] (see
  /// `distributeExtension`); whatever they leave is held after it.
  Map<String, Object?> nativeConfiguration({
    required int durationMs,
    required bool isTimer,
    int randomSeed = 1,
    List<PauseHold> holds = const [],
  }) => {
    ...toJson(),
    'durationMs': durationMs,
    'isTimer': isTimer,
    'randomSeed': randomSeed,
    'extendMinutes': isTimer ? 0 : extraMinutes,
    'holds': isTimer || pauseMinutes <= 0
        ? const <Map<String, Object?>>[]
        : [for (final h in holds) h.toJson()],
    'startSound': startSound.isEmpty ? null : startSound,
    'endSound': endSound.isEmpty ? null : endSound,
    'intervalSound': intervalSound.isEmpty ? null : intervalSound,
    'pulseSound': pulseSound.isEmpty ? null : pulseSound,
  };
}

class CueScope {
  const CueScope(this.kind, {this.courseId});
  final CueKind kind;
  final String? courseId;
  @override
  bool operator ==(Object other) =>
      other is CueScope && kind == other.kind && courseId == other.courseId;
  @override
  int get hashCode => Object.hash(kind, courseId);
}
