import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';

void main() {
  test('a failed start-up is tried again; a good one is shared', () async {
    var runs = 0;
    var fail = true;
    final once = RetryableOnce(() async {
      runs++;
      if (fail) throw StateError('no audio device');
    });

    await expectLater(once(), throwsStateError);
    expect(once.current, isNull, reason: 'the failure is not kept');
    fail = false;
    await once();
    await once();
    expect(runs, 2, reason: 'one retry, then shared');

    once.reset();
    await once();
    expect(runs, 3, reason: 'after a shutdown it starts again');
  });
}
