import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Practice and Talks have separate background defaults', () async {
    final store = CueSettingsStore(await SharedPreferences.getInstance());
    expect(
      store.read(const CueScope(CueKind.practice)).backgroundEnabled,
      isTrue,
    );
    expect(
      store.read(const CueScope(CueKind.talks)).backgroundEnabled,
      isFalse,
    );
  });
  test('all cue preferences persist independently by kind', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = CueSettingsStore(prefs);
    const practice = CueScope(CueKind.practice);
    const s = CueSettings(
      countdownSeconds: 10,
      extendMinutes: 25,
      intervalMinutes: 5,
      randomWindowMinutes: 2,
      pulseSound: 'assets/audio/pulse_click.wav',
      pulseBpm: 70,
      pulseEndBpm: 35,
      pulseRampMinutes: 15,
      pulseVolume: .3,
      backgroundVolume: 25,
      autoplay: true,
      interludeSeconds: 30,
      hideBeforePractice: true,
    );
    await store.save(practice, s);
    expect(CueSettingsStore(prefs).read(practice).toJson(), s.toJson());
    expect(store.read(const CueScope(CueKind.talks)).countdownSeconds, 0);
  });
  test(
    'course inherits defaults until override and can return to them',
    () async {
      final store = CueSettingsStore(await SharedPreferences.getInstance());
      const base = CueScope(CueKind.practice);
      const course = CueScope(CueKind.practice, courseId: 'ds-retreat-4496');
      await store.save(base, const CueSettings(extendMinutes: 5));
      expect(store.read(course).extendMinutes, 5);
      expect(store.hasOverride(course), isFalse);
      await store.save(course, const CueSettings(extendMinutes: 20));
      await store.save(base, const CueSettings(extendMinutes: 10));
      expect(store.read(course).extendMinutes, 20);
      expect(store.hasOverride(course), isTrue);
      await store.removeOverride(course);
      expect(store.read(course).extendMinutes, 10);
    },
  );
  test('invalid stored values safely clamp and unknown sounds are refused', () {
    final s = CueSettings.fromJson({
      'extendMinutes': 900,
      'countdownSeconds': 7,
      'pulseBpm': -1,
      'pulseVolume': 3,
      'startSound': 'https://unlicensed.test/bell.mp3',
      'backgroundVolume': double.nan,
    });
    expect(s.extendMinutes, 60);
    expect(s.countdownSeconds, 0);
    expect(s.pulseBpm, 20);
    expect(s.pulseVolume, 1);
    expect(s.startSound, 'assets/audio/session_bell_v2.wav');
    expect(s.backgroundVolume, 50);
    expect(
      CueSettings.decode('broken json', CueKind.talks).backgroundEnabled,
      isFalse,
    );
  });
  test('native timer configuration omits extension and off assets', () {
    final map = const CueSettings(
      extendMinutes: 20,
      startSound: '',
      pulseSound: '',
    ).nativeConfiguration(durationMs: 600000, isTimer: true);
    expect(map['extendMinutes'], 0);
    expect(map['startSound'], isNull);
    expect(map['pulseSound'], isNull);
    expect(map['durationMs'], 600000);
  });
}
