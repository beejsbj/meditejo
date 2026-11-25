import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/audio/played_time.dart';

/// iOS measures real time in Dart with the rules Android's ListeningTracker
/// uses (CueMathTest covers that side).
void main() {
  /// Sampled once a real second: each step covers [speed] seconds of media.
  void playAt(PlayedTime t, int from, int to, double speed) {
    final step = (1000 * speed).round();
    var p = from;
    t.sample(p, playing: true, speed: speed);
    while (p < to) {
      p = (p + step).clamp(0, to);
      t.sample(p, playing: true, speed: speed);
    }
  }

  test('a talk at 2x takes half its length', () {
    final t = PlayedTime();
    playAt(t, 0, 3600000, 2);
    expect(t.realMs(3600000, speed: 2), 1800000);
  });

  test('at 1x real time is the length exactly', () {
    final t = PlayedTime();
    playAt(t, 0, 600000, 1);
    expect(t.realMs(600000, speed: 1), 600000);
  });

  test('each stretch counts at the speed it was heard at', () {
    final t = PlayedTime();
    playAt(t, 0, 1800000, 1);
    playAt(t, 1800000, 3600000, 2);
    expect(t.realMs(3600000, speed: 2), 2700000);
    final slow = PlayedTime();
    playAt(slow, 0, 600000, 0.6);
    expect(slow.realMs(600000, speed: 0.6), closeTo(1000000, 1));
  });

  test('a completion at 90% projects the rest at the same speed', () {
    final t = PlayedTime();
    playAt(t, 0, 540000, 1.5);
    expect(t.realMs(600000, speed: 1.5), 400000);
  });

  test('pauses, buffering and seeks add nothing', () {
    final t = PlayedTime();
    playAt(t, 0, 60000, 2);
    t.sample(60000, playing: false, speed: 2); // paused, any length of time
    t.sample(300000, playing: true, speed: 2); // resumed after a seek: rebase
    t.sample(302000, playing: true, speed: 2);
    t.sample(250000, playing: true, speed: 2); // a seek back
    expect(t.playedMediaMs, 62000);
    expect(t.playedRealMs, 31000);
  });

  test('nothing played yet takes the speed in force', () {
    expect(PlayedTime().realMs(600000, speed: 2), 300000);
    expect(PlayedTime().realMs(0, speed: 2), 0);
  });

  test('your time is the recording at its speeds, plus silence and '
      'countdown', () {
    // 10 minutes at 2x, 5 minutes of Extend, a 10 s countdown.
    expect(
      sessionRealMs(300000, silenceMs: 300000, countdownMs: 10000),
      610000,
    );
    expect(sessionRealMs(300000), 300000);
    // Nonsense never subtracts.
    expect(sessionRealMs(300000, silenceMs: -1, countdownMs: -1), 300000);
  });

  test('a new track starts fresh', () {
    final t = PlayedTime();
    playAt(t, 0, 60000, 2);
    t.reset();
    expect(t.playedMediaMs, 0);
    expect(t.playedRealMs, 0);
  });
}
