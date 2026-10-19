import 'dart:convert';

/// Playback preferences are independent of a source's audio metadata.
enum CueKind { practice, talks }

const cueBellSounds = <String, String>{
  'Off': '',
  'Bowl': 'assets/audio/session_bell_v2.wav',
};
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
    this.countdownSeconds = 0,
    this.startSound = 'assets/audio/session_bell_v2.wav',
    this.endSound = 'assets/audio/session_bell_v2.wav',
    this.intervalSound = 'assets/audio/session_bell_v2.wav',
    this.intervalMinutes = 0,
    this.randomWindowMinutes = 0,
    this.pulseSound = '',
    this.pulseBpm = 60,
    this.pulseEndBpm = 40,
    this.pulseRampMinutes = 0,
    this.pulseVolume = 0.25,
    this.bellVolume = 0.5,
    this.backgroundEnabled = true,
    this.backgroundSoundId = '',
    this.backgroundVolume = 50,
    this.autoplay = false,
    this.interludeSeconds = 0,
    this.hideBeforePractice = false,
  });

  factory CueSettings.defaults(CueKind kind) =>
      CueSettings(backgroundEnabled: kind == CueKind.practice);

  final int durationMinutes, extendMinutes, countdownSeconds;
  final String startSound, endSound, intervalSound;
  final int intervalMinutes, randomWindowMinutes;
  final String pulseSound;
  final double pulseBpm, pulseEndBpm, pulseVolume, bellVolume;
  final int pulseRampMinutes;
  final bool backgroundEnabled, autoplay, hideBeforePractice;
  final String backgroundSoundId;
  final double backgroundVolume;
  final int interludeSeconds;

  CueSettings copyWith({
    int? durationMinutes,
    int? extendMinutes,
    int? countdownSeconds,
    String? startSound,
    String? endSound,
    String? intervalSound,
    int? intervalMinutes,
    int? randomWindowMinutes,
    String? pulseSound,
    double? pulseBpm,
    double? pulseEndBpm,
    int? pulseRampMinutes,
    double? pulseVolume,
    double? bellVolume,
    bool? backgroundEnabled,
    String? backgroundSoundId,
    double? backgroundVolume,
    bool? autoplay,
    int? interludeSeconds,
    bool? hideBeforePractice,
  }) => CueSettings.fromJson({
    ...toJson(),
    'durationMinutes': durationMinutes ?? this.durationMinutes,
    'extendMinutes': extendMinutes ?? this.extendMinutes,
    'countdownSeconds': countdownSeconds ?? this.countdownSeconds,
    'startSound': startSound ?? this.startSound,
    'endSound': endSound ?? this.endSound,
    'intervalSound': intervalSound ?? this.intervalSound,
    'intervalMinutes': intervalMinutes ?? this.intervalMinutes,
    'randomWindowMinutes': randomWindowMinutes ?? this.randomWindowMinutes,
    'pulseSound': pulseSound ?? this.pulseSound,
    'pulseBpm': pulseBpm ?? this.pulseBpm,
    'pulseEndBpm': pulseEndBpm ?? this.pulseEndBpm,
    'pulseRampMinutes': pulseRampMinutes ?? this.pulseRampMinutes,
    'pulseVolume': pulseVolume ?? this.pulseVolume,
    'bellVolume': bellVolume ?? this.bellVolume,
    'backgroundEnabled': backgroundEnabled ?? this.backgroundEnabled,
    'backgroundSoundId': backgroundSoundId ?? this.backgroundSoundId,
    'backgroundVolume': backgroundVolume ?? this.backgroundVolume,
    'autoplay': autoplay ?? this.autoplay,
    'interludeSeconds': interludeSeconds ?? this.interludeSeconds,
    'hideBeforePractice': hideBeforePractice ?? this.hideBeforePractice,
  });

  Map<String, Object?> toJson() => {
    'version': 1,
    'durationMinutes': durationMinutes,
    'extendMinutes': extendMinutes,
    'countdownSeconds': countdownSeconds,
    'startSound': startSound,
    'endSound': endSound,
    'intervalSound': intervalSound,
    'intervalMinutes': intervalMinutes,
    'randomWindowMinutes': randomWindowMinutes,
    'pulseSound': pulseSound,
    'pulseBpm': pulseBpm,
    'pulseEndBpm': pulseEndBpm,
    'pulseRampMinutes': pulseRampMinutes,
    'pulseVolume': pulseVolume,
    'bellVolume': bellVolume,
    'backgroundEnabled': backgroundEnabled,
    'backgroundSoundId': backgroundSoundId,
    'backgroundVolume': backgroundVolume,
    'autoplay': autoplay,
    'interludeSeconds': interludeSeconds,
    'hideBeforePractice': hideBeforePractice,
  };

  factory CueSettings.fromJson(
    Map<String, Object?> json, {
    CueKind kind = CueKind.practice,
  }) {
    final defaults = CueSettings.defaults(kind);
    int integer(String key, int fallback, int min, int max) =>
        (json[key] is num ? (json[key] as num).toInt() : fallback).clamp(
          min,
          max,
        );
    double number(String key, double fallback, double min, double max) {
      final value = json[key] is num ? (json[key] as num).toDouble() : fallback;
      return value.isFinite ? value.clamp(min, max) : fallback;
    }

    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    String sound(String key, String fallback, Map<String, String> allowed) {
      final value = json[key];
      return value is String && allowed.containsValue(value) ? value : fallback;
    }

    final countdown = integer('countdownSeconds', 0, 0, 10);
    final interlude = integer('interludeSeconds', 0, 0, 30);
    return CueSettings(
      durationMinutes: integer('durationMinutes', 10, 1, 299),
      extendMinutes: integer('extendMinutes', 0, 0, 60),
      countdownSeconds: [0, 5, 10].contains(countdown) ? countdown : 0,
      startSound: sound('startSound', defaults.startSound, cueBellSounds),
      endSound: sound('endSound', defaults.endSound, cueBellSounds),
      intervalSound: sound(
        'intervalSound',
        defaults.intervalSound,
        cueBellSounds,
      ),
      intervalMinutes: integer('intervalMinutes', 0, 0, 60),
      randomWindowMinutes: integer('randomWindowMinutes', 0, 0, 60),
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
      autoplay: flag('autoplay', false),
      interludeSeconds: [0, 5, 10, 30].contains(interlude) ? interlude : 0,
      hideBeforePractice: flag('hideBeforePractice', false),
    );
  }

  static CueSettings decode(String? value, CueKind kind) {
    try {
      final decoded = value == null ? null : jsonDecode(value);
      return decoded is Map<String, dynamic>
          ? CueSettings.fromJson(decoded, kind: kind)
          : CueSettings.defaults(kind);
    } on FormatException {
      return CueSettings.defaults(kind);
    }
  }

  Duration sessionDuration(Duration audioDuration, {required bool isTimer}) =>
      isTimer
      ? Duration(minutes: durationMinutes)
      : audioDuration + Duration(minutes: extendMinutes);

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
                  Duration(minutes: extendMinutes),
      );

  Map<String, Object?> nativeConfiguration({
    required int durationMs,
    required bool isTimer,
    int randomSeed = 1,
  }) => {
    ...toJson(),
    'durationMs': durationMs,
    'isTimer': isTimer,
    'randomSeed': randomSeed,
    'extendMinutes': isTimer ? 0 : extendMinutes,
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
