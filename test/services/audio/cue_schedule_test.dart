import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/services/audio/cue_schedule.dart';

void main() {
  CueSchedule schedule(CueSettings s, {bool timer = false, int seed = 1}) =>
      CueSchedule(
        s,
        audioDuration: const Duration(minutes: 20),
        isTimer: timer,
        seed: seed,
      );
  test('countdown precedes start, exact end includes extension', () {
    final cues = schedule(
      const CueSettings(countdownSeconds: 10, extendMinutes: 5),
    );
    final events = cues.events();
    expect(events.first.at, const Duration(seconds: 10));
    expect(events.first.type, CueType.start);
    expect(events.last.at, const Duration(minutes: 25, seconds: 10));
    expect(events.last.type, CueType.end);
  });
  test('timer uses its duration without adding extension twice', () {
    expect(
      schedule(
        const CueSettings(
          durationMinutes: 10,
          extendMinutes: 5,
          countdownSeconds: 5,
        ),
        timer: true,
      ).end,
      const Duration(minutes: 10, seconds: 5),
    );
  });
  test('off sounds produce no cues', () {
    expect(
      schedule(
        const CueSettings(
          startSound: '',
          endSound: '',
          intervalSound: '',
          intervalMinutes: 1,
        ),
      ).events(),
      isEmpty,
    );
  });
  test('fixed intervals continue into extension and exclude exact end', () {
    final cues = schedule(
      const CueSettings(intervalMinutes: 5, extendMinutes: 5),
    );
    expect(cues.intervals().toList(), [
      for (final m in [5, 10, 15, 20]) Duration(minutes: m),
    ]);
  });
  test('seeded random windows have bounded, reproducible gaps', () {
    const settings = CueSettings(
      intervalMinutes: 3,
      randomWindowMinutes: 2,
      extendMinutes: 60,
    );
    final first = schedule(settings, seed: 42).intervals().toList();
    expect(first, schedule(settings, seed: 42).intervals().toList());
    expect(first, isNot(schedule(settings, seed: 43).intervals().toList()));
    var last = Duration.zero;
    for (final deadline in first) {
      expect(
        (deadline - last).inMicroseconds,
        inInclusiveRange(60000000, 300000000),
      );
      last = deadline;
    }
    expect(last, lessThan(const Duration(minutes: 80)));
  });
  test('wide random window never creates zero or negative gaps', () {
    final cues = schedule(
      const CueSettings(intervalMinutes: 1, randomWindowMinutes: 60),
    );
    for (final at in cues.intervals()) {
      expect(at, greaterThan(Duration.zero));
    }
  });
  test('constant 60 BPM pulse is phase accurate to under 1ms after hours', () {
    final cues = schedule(
      const CueSettings(pulseSound: 'assets/audio/pulse_click.wav'),
    );
    for (final beat in [1, 10, 3600, 18000]) {
      expect(
        (cues.pulseAt(beat) - Duration(seconds: beat)).inMicroseconds.abs(),
        lessThan(1000),
      );
    }
  });
  test('settle from 60 to 40 over ten minutes integrates to 500 beats', () {
    final cues = schedule(const CueSettings(pulseRampMinutes: 10));
    expect(cues.pulseAt(500), const Duration(minutes: 10));
    expect(cues.pulseAt(501), const Duration(minutes: 10, milliseconds: 1500));
    expect(cues.pulseAt(1), greaterThan(const Duration(seconds: 1)));
    expect(cues.pulseAt(1), lessThan(const Duration(milliseconds: 1100)));
  });
  test('ramp deadlines match integrated phase within 100ms', () {
    final cues = schedule(
      const CueSettings(pulseBpm: 120, pulseEndBpm: 20, pulseRampMinutes: 60),
    );
    for (var n = 1; n < 4200; n += 17) {
      final t = cues.pulseAt(n).inMicroseconds / 1000000;
      final beats = (120 * t + 0.5 * (20 - 120) / 3600 * t * t) / 60;
      expect((beats - n).abs(), lessThan(0.001));
    }
  });
  test('pulse has its own volume and never fires at end boundary', () {
    final events = schedule(
      const CueSettings(
        durationMinutes: 1,
        pulseSound: 'assets/audio/pulse_click.wav',
        pulseVolume: .15,
      ),
      timer: true,
    ).events();
    final pulses = events.where((e) => e.type == CueType.pulse).toList();
    expect(pulses.length, 59);
    expect(pulses.every((e) => e.volume == .15), isTrue);
    expect(events.last.type, CueType.end);
    expect(events.last.at, const Duration(minutes: 1));
  });
  test('countdown can be skipped without changing meditation cue offsets', () {
    final before = schedule(
      const CueSettings(countdownSeconds: 10, intervalMinutes: 5),
    ).events();
    final skipped = schedule(const CueSettings(intervalMinutes: 5)).events();
    for (var i = 0; i < before.length; i++) {
      expect(before[i].at - skipped[i].at, const Duration(seconds: 10));
    }
  });
  test('live finish time includes speed, countdown and silent extension', () {
    final at = DateTime(2026, 10, 19, 12);
    const s = CueSettings(countdownSeconds: 5, extendMinutes: 10);
    expect(
      s.finishesAt(at, const Duration(minutes: 20), isTimer: false, speed: 2),
      at.add(const Duration(minutes: 20, seconds: 5)),
    );
  });
  test('random gaps match the Kotlin and Swift pinned vectors', () {
    expect(
      [for (var i = 1; i <= 3; i++) CueSchedule.gapMs(10, 4, 42, i)],
      [448678, 652441, 726809],
    );
    expect(CueSchedule.gapMs(10, 4, -9, 1), 409580);
  });

  group('halfway', () {
    const halfway = CueSettings(intervalHalfway: true, intervalMinutes: 5);

    test('one bell at the midpoint of the recording and its extension', () {
      // (20 min of audio + 10 min extension) / 2, after the countdown. The
      // stored "every 5 min" is kept but does not ring.
      final cues = schedule(
        halfway.copyWith(extendMinutes: 10, countdownSeconds: 10),
      );
      expect(cues.intervals().toList(), [
        const Duration(minutes: 15, seconds: 10),
      ]);
      expect(
        cues.events().where((e) => e.type == CueType.interval).single.at,
        const Duration(minutes: 15, seconds: 10),
      );
    });

    test('a timer rings at half its duration, never adding the extension', () {
      final cues = schedule(
        halfway.copyWith(durationMinutes: 25, extendMinutes: 10),
        timer: true,
      );
      expect(cues.intervals().toList(), [
        const Duration(minutes: 12, seconds: 30),
      ]);
    });

    test('an odd length rounds down to the millisecond', () {
      final cues = CueSchedule(
        halfway,
        audioDuration: const Duration(milliseconds: 60001),
      );
      expect(cues.halfway, const Duration(milliseconds: 30000));
    });

    test('the interval bell set to Off rings nothing', () {
      final cues = schedule(halfway.copyWith(intervalSound: ''));
      expect(cues.halfway, isNull);
      expect(cues.intervals(), isEmpty);
      expect(halfway.copyWith(intervalSound: '').hasIntervalBell, isFalse);
    });

    test('halfway with no interval minutes still rings', () {
      const s = CueSettings(intervalHalfway: true);
      expect(s.hasIntervalBell, isTrue);
      expect(schedule(s).intervals().single, const Duration(minutes: 10));
    });

    test('survives storage, and an old value reads as not halfway', () {
      final stored = CueSettings.decode(
        '{"version":1,"intervalHalfway":true,"intervalMinutes":7}',
        CueKind.practice,
      );
      expect(stored.intervalHalfway, isTrue);
      expect(stored.intervalMinutes, 7);
      expect(CueSettings.fromJson(stored.toJson()).intervalHalfway, isTrue);
      expect(
        CueSettings.decode(
          '{"intervalMinutes":7}',
          CueKind.practice,
        ).intervalHalfway,
        isFalse,
      );
      // The native side reads the same key.
      expect(
        stored.nativeConfiguration(
          durationMs: 1,
          isTimer: false,
        )['intervalHalfway'],
        isTrue,
      );
    });
  });
}
