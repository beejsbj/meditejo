import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';

/// The cue sounds that are generated samples and not synthesis (#76), as
/// `tools/meditejo/cue_samples.json` records them.
void main() {
  final record =
      (jsonDecode(File('tools/meditejo/cue_samples.json').readAsStringSync())
              as Map<String, dynamic>)['samples']
          as List<dynamic>;
  final samples = [for (final s in record) s as Map<String, dynamic>];
  final notice = File('assets/audio/NOTICE').readAsStringSync();
  final names = {
    for (final e in {...cueBellSounds, ...cuePulseSounds}.entries)
      e.value: e.key,
  };

  test('the four sampled sounds are the ones recorded', () {
    expect(samples.map((s) => s['file']).toSet(), {
      'bell_chime.wav',
      'pulse_heartbeat.wav',
      'pulse_chirp.wav',
      'pulse_footstep.wav',
    });
  });

  test('each shipped file is the recorded one, byte for byte', () {
    for (final s in samples) {
      final file = File('assets/audio/${s['file']}');
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        s['sha256'],
        reason: '${s['file']}',
      );
    }
  });

  test('each is offered under its recorded name', () {
    for (final s in samples) {
      expect(names['assets/audio/${s['file']}'], s['name']);
    }
  });

  test('each records its model, prompt, take, date, plan and CC0', () {
    for (final s in samples) {
      final reason = '${s['file']}';
      expect(s['license'], 'CC0-1.0', reason: reason);
      expect(s['model'], 'eleven_text_to_sound_v3', reason: reason);
      expect(s['plan'], 'ElevenLabs Creator (paid)', reason: reason);
      expect(s['prompt'], isA<String>(), reason: reason);
      expect((s['prompt'] as String).length, greaterThan(40), reason: reason);
      expect(s['take'], isA<int>(), reason: reason);
      expect(DateTime.tryParse(s['date'] as String), isNotNull, reason: reason);
    }
  });

  test('the notice shipped with the sounds says the same', () {
    expect(notice, contains('CC0-1.0'));
    for (final s in samples) {
      final reason = '${s['file']}';
      expect(notice, contains('${s['file']} ("${s['name']}")'), reason: reason);
      expect(notice, contains('Prompt: "${s['prompt']}"'), reason: reason);
      expect(
        notice,
        contains('Take ${s['take']} of ${s['takesGenerated']}'),
        reason: reason,
      );
      expect(notice, contains('${s['model']}'), reason: reason);
      expect(notice, contains('Plan: ${s['plan']}'), reason: reason);
    }
  });

  test('a pulse is a short one-shot the native pool can load', () {
    for (final s in samples.where(
      (s) => (s['file'] as String).startsWith('pulse_'),
    )) {
      final bytes = File('assets/audio/${s['file']}').readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(data.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(data.getUint32(24, Endian.little), 44100);
      expect(data.getUint16(34, Endian.little), 16);
      final seconds = (bytes.length - 44) / (44100 * 2);
      // One beat is over before the next at 75 BPM (0.8 s); faster tempos
      // overlap only its fading tail. Far under SoundPool's 1 MiB.
      expect(seconds, inInclusiveRange(0.2, 0.8), reason: '${s['file']}');
      expect(bytes.length, lessThan(100 * 1024));
      // Starts and ends on zero: no click at either edge.
      expect(data.getInt16(44, Endian.little), 0);
      expect(data.getInt16(bytes.length - 2, Endian.little), 0);
    }
  });
}
