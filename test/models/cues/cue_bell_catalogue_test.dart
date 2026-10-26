import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/background_sounds/background_sounds_model.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The first fields of a WAV: PCM, mono, 16-bit, with its rate and length.
({int format, int channels, int rate, int bits, double seconds}) _wav(
  String path,
) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF', reason: path);
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE', reason: path);
  expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ', reason: path);
  final channels = data.getUint16(22, Endian.little);
  final rate = data.getUint32(24, Endian.little);
  final bits = data.getUint16(34, Endian.little);
  // The data chunk follows the 16-byte fmt chunk; walk to it rather than
  // assume a 44-byte header.
  var at = 36;
  while (String.fromCharCodes(bytes.sublist(at, at + 4)) != 'data') {
    at += 8 + data.getUint32(at + 4, Endian.little);
  }
  final length = data.getUint32(at + 4, Endian.little);
  return (
    format: data.getUint16(20, Endian.little),
    channels: channels,
    rate: rate,
    bits: bits,
    seconds: length / (rate * channels * bits ~/ 8),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final bells = {
    for (final e in cueBellSounds.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };

  test('Off first, then every bell, with unique names and ids', () {
    expect(cueBellSounds.entries.first.key, 'Off');
    expect(cueBellSounds.entries.first.value, '');
    expect(bells.length, greaterThanOrEqualTo(8));
    expect(bells.values.toSet().length, bells.length);
    expect(cueBellSounds.keys.toSet().length, cueBellSounds.length);
  });

  test('every bell id is a bundled WAV the cue banks can decode', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- assets/audio/'));
    for (final e in bells.entries) {
      expect(e.value, startsWith('assets/audio/'), reason: e.key);
      expect(
        File(e.value).existsSync(),
        isTrue,
        reason: '${e.key}: ${e.value}',
      );
      final wav = _wav(e.value);
      // What SoundPool and AVAudioPlayer both read without a codec.
      expect(wav.format, 1, reason: e.value);
      expect(wav.channels, 1, reason: e.value);
      expect(wav.bits, 16, reason: e.value);
      expect(wav.rate, anyOf(22050, 44100), reason: e.value);
      expect(wav.seconds, inInclusiveRange(0.2, 15), reason: e.value);
      // SoundPool decodes a sound whole and refuses one over about 1 MiB.
      expect(File(e.value).lengthSync(), lessThan(1 << 20), reason: e.value);
    }
  });

  test('no bell file ships outside the catalogue', () {
    final onDisk = Directory('assets/audio')
        .listSync()
        .map((f) => f.path.split('/').last)
        .where((n) => n.endsWith('.wav') && !n.startsWith('pulse_'))
        .toSet();
    final listed = bells.values.map((p) => p.split('/').last).toSet();
    expect(onDisk, listed);
  });

  test('the original bell keeps its id, and stays the default', () {
    expect(bells.values, contains('assets/audio/session_bell_v2.wav'));
    expect(kSessionBellAsset, 'assets/audio/session_bell_v2.wav');
    const s = CueSettings();
    expect(s.startSound, kSessionBellAsset);
    expect(s.intervalSound, kSessionBellAsset);
    expect(s.endSound, kSessionBellAsset);
  });

  test('values stored by earlier builds load as they were', () {
    // 0.1.3 wrote the asset path, with and without Off.
    final s = CueSettings.decode(
      '{"version":1,"startSound":"assets/audio/session_bell_v2.wav",'
      '"intervalSound":"","endSound":"assets/audio/session_bell_v2.wav"}',
      CueKind.practice,
    );
    expect(s.startSound, 'assets/audio/session_bell_v2.wav');
    expect(s.intervalSound, '');
    expect(s.endSound, 'assets/audio/session_bell_v2.wav');
    // Unversioned and without any bell fields: the defaults.
    expect(
      CueSettings.decode('{"extendMinutes":5}', CueKind.practice).endSound,
      kSessionBellAsset,
    );
  });

  test('a bell this build does not know falls back to the default', () {
    final s = CueSettings.fromJson({
      'startSound': 'assets/audio/bell_from_a_newer_build.wav',
      'endSound': 'assets/audio/bell_gong.wav',
    });
    expect(s.startSound, kSessionBellAsset);
    expect(s.endSound, 'assets/audio/bell_gong.wav');
  });

  test('each bell id survives the round trip and reaches the native side', () {
    for (final id in bells.values) {
      final s = CueSettings.fromJson({
        'startSound': id,
        'intervalSound': id,
        'endSound': id,
      });
      expect(s.startSound, id);
      final native = s.nativeConfiguration(durationMs: 60000, isTimer: true);
      expect(native['startSound'], id);
      expect(native['intervalSound'], id);
      expect(native['endSound'], id);
    }
  });

  test('start, interval and end bells persist independently per cue', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = CueSettingsStore(prefs);
    const scope = CueScope(CueKind.practice);
    final start = bells['Singing bowl, deep']!;
    final interval = bells['Chime']!;
    final end = bells['Gong']!;
    await store.save(scope, const CueSettings().copyWith(startSound: start));
    var read = CueSettingsStore(prefs).read(scope);
    expect(read.startSound, start);
    expect(read.intervalSound, kSessionBellAsset);
    expect(read.endSound, kSessionBellAsset);

    await store.save(scope, read.copyWith(intervalSound: interval));
    await store.save(scope, store.read(scope).copyWith(endSound: end));
    read = CueSettingsStore(prefs).read(scope);
    expect(
      [read.startSound, read.intervalSound, read.endSound],
      [start, interval, end],
    );
    // Talks keep their own, untouched.
    final talks = store.read(const CueScope(CueKind.talks));
    expect(talks.startSound, kSessionBellAsset);
    // Off for one cue leaves the others ringing.
    await store.save(scope, read.copyWith(intervalSound: ''));
    read = CueSettingsStore(prefs).read(scope);
    expect(
      [read.startSound, read.intervalSound, read.endSound],
      [start, '', end],
    );
  });
}
