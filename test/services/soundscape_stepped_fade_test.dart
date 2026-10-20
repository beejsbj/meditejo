import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';

void main() {
  const step = Duration(milliseconds: 10);
  late List<double> steps;
  late int done;
  late SteppedFade fade;

  setUp(() {
    steps = [];
    done = 0;
    fade = SteppedFade(
      steps: 4,
      stepTime: step,
      onStep: steps.add,
      onDone: () => done++,
    );
  });

  Future<void> wait(int n) => Future<void>.delayed(step * n);

  test('runs its steps in order, then is done', () async {
    fade.start();
    await wait(8);
    expect(steps, [0.25, 0.5, 0.75, 1.0]);
    expect(done, 1);
    expect(fade.ticking, isFalse);
  });

  test('paused, it arms no timer; resumed, it runs the steps left', () async {
    fade.start();
    await Future<void>.delayed(step * 1.5);
    expect(steps, [0.25]);
    fade.pause();
    expect(fade.ticking, isFalse, reason: 'nothing wakes during a pause');
    await wait(8);
    expect(steps, [0.25], reason: 'held while paused');
    fade.resume();
    await wait(8);
    expect(steps, [0.25, 0.5, 0.75, 1.0]);
    expect(done, 1);
  });

  test('paused before it starts, it waits for resume', () async {
    fade
      ..pause()
      ..start();
    expect(fade.ticking, isFalse);
    await wait(6);
    expect(steps, isEmpty);
    fade.resume();
    await wait(8);
    expect(done, 1);
  });

  test('cancelled, it stops and never finishes', () async {
    fade.start();
    await Future<void>.delayed(step * 1.5);
    fade.cancel();
    fade.resume();
    await wait(8);
    expect(steps, [0.25]);
    expect(done, 0);
    expect(fade.ticking, isFalse);
  });
}
