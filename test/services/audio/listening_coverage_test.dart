import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/audio/cue_schedule.dart';

void main() {
  test('opening, pause and seeking to the end do not count', () {
    final heard = ListeningCoverage();
    heard.sample(positionMs: 0, clockMs: 0, playing: true);
    heard.sample(positionMs: 99000, clockMs: 100, playing: false);
    heard.sample(positionMs: 100000, clockMs: 100000, playing: false);
    expect(heard.heardMs, 0);
    expect(heard.completed(100000, ended: true), isFalse);
  });
  test('89.9 percent is incomplete, exactly 90 percent completes', () {
    final heard = ListeningCoverage();
    heard.sample(positionMs: 0, clockMs: 0, playing: true);
    heard.sample(positionMs: 89900, clockMs: 89900, playing: true);
    expect(heard.completed(100000), isFalse);
    heard.sample(positionMs: 90000, clockMs: 90000, playing: true);
    expect(heard.completed(100000), isTrue);
  });
  test('replaying the same part never double counts', () {
    final heard = ListeningCoverage();
    heard.restore([
      [0, 50000],
    ]);
    heard.discontinuity();
    heard.sample(positionMs: 0, clockMs: 0, playing: true);
    heard.sample(positionMs: 50000, clockMs: 50000, playing: true);
    expect(heard.heardMs, 50000);
    expect(heard.completed(100000), isFalse);
    heard.restore([
      [40000, 90000],
    ]);
    expect(heard.heardMs, 90000);
    expect(heard.completed(100000), isTrue);
  });
  test('persisted coverage resumes across sessions', () {
    final first = ListeningCoverage()
      ..restore([
        [0, 40000],
        [50000, 70000],
      ]);
    final next = ListeningCoverage()..restore(first.ranges);
    next.sample(positionMs: 70000, clockMs: 0, playing: true);
    next.sample(positionMs: 100000, clockMs: 30000, playing: false);
    expect(next.heardMs, 90000);
    expect(next.completed(100000), isTrue);
  });
  test('timer and extended session complete only when ended', () {
    final heard = ListeningCoverage()
      ..restore([
        [0, 90000],
      ]);
    expect(heard.completed(100000, isTimer: true), isFalse);
    expect(heard.completed(100000, isTimer: true, ended: true), isTrue);
    expect(
      ListeningCoverage().completed(100000, extended: true, ended: true),
      isTrue,
    );
    expect(heard.completed(0, ended: true), isFalse);
  });
  test('speed and explicit seek discontinuities do not invent coverage', () {
    final heard = ListeningCoverage();
    heard.sample(positionMs: 0, clockMs: 0, playing: true, speed: 2);
    heard.sample(positionMs: 40000, clockMs: 20000, playing: true, speed: 2);
    heard.discontinuity();
    heard.sample(positionMs: 90000, clockMs: 21000, playing: true, speed: 2);
    expect(heard.heardMs, 40000);
  });
}
