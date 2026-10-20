import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';

void main() {
  const fade = Duration(milliseconds: 40);
  late List<String> calls;
  late PauseFade pause;

  setUp(() {
    calls = [];
    pause = PauseFade(
      fadeMaster: (gain, over) =>
          calls.add('fade $gain ${over.inMilliseconds}'),
      pauseVoices: (paused) => calls.add(paused ? 'pause' : 'unpause'),
      fadeOut: fade,
      fadeIn: fade,
    );
  });

  test('pausing fades the mix out before the voices pause', () async {
    pause.pause();
    expect(calls, ['fade 0.0 40'], reason: 'nothing stops dead');
    expect(pause.paused, isTrue);
    var settled = false;
    pause.settled.then((_) => settled = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(settled, isFalse, reason: 'a layer stopped now waits for the fade');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(calls, ['fade 0.0 40', 'pause']);
    expect(settled, isTrue);

    pause.resume(0.5);
    expect(calls.skip(2), ['unpause', 'fade 0.5 40'], reason: 'fades back in');
  });

  test('resuming during the fade-out never pauses the voices', () async {
    pause.pause();
    pause.resume(0.8);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, ['fade 0.0 40', 'unpause', 'fade 0.8 40']);
    expect(pause.paused, isFalse);
    await pause.settled;
  });

  test('with nothing audible the voices pause at once', () {
    pause.pause(fade: false);
    expect(calls, ['pause']);
    expect(pause.paused, isTrue);
  });
}
