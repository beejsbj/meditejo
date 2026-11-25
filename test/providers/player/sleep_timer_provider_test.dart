import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/player/repeat_mode.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/player/repeat_state_provider.dart';
import 'package:medito/providers/player/sleep_timer_provider.dart';

class _FakeEngine implements SleepTimerEngine {
  final calls = <String>[];

  @override
  Future<void> arm(Duration after) async => calls.add('arm ${after.inMinutes}');

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> expired() async => calls.add('expired');
}

class _FakePlayer extends PlayerProvider {
  final repeats = <RepeatMode>[];

  @override
  void setRepeatMode(RepeatMode mode) => repeats.add(mode);
}

void main() {
  late _FakeEngine engine;
  late _FakePlayer player;
  late ProviderContainer container;

  setUp(() {
    engine = _FakeEngine();
    player = _FakePlayer();
    container = ProviderContainer(
      overrides: [
        sleepTimerEngineProvider.overrideWithValue(engine),
        playerProvider.overrideWith(() => player),
      ],
    );
    addTearDown(container.dispose);
  });

  SleepTimerNotifier notifier() => container.read(sleepTimerProvider.notifier);
  SleepTimerState state() => container.read(sleepTimerProvider);

  // testWidgets for its fake clock.
  testWidgets('minutes arm the audio service and count down', (tester) async {
    final start = DateTime(2026, 11, 25, 23);
    notifier().now = () => start;
    await notifier().setMinutes(10);
    expect(engine.calls, ['arm 10']);
    expect(state().isSet, isTrue);
    expect(state().remaining(start), const Duration(minutes: 10));
    expect(
      state().remaining(start.add(const Duration(minutes: 4))),
      const Duration(minutes: 6),
    );

    // Run out: the button clears, and the engine is told (it pauses only
    // where there is no native clock).
    await tester.pump(const Duration(minutes: 10));
    expect(state().isSet, isFalse);
    expect(engine.calls, ['arm 10', 'expired']);
  });

  testWidgets('cancel stops it, and the Dart timer with it', (tester) async {
    await notifier().setMinutes(5);
    await notifier().cancel();
    expect(state().isSet, isFalse);
    await tester.pump(const Duration(minutes: 6));
    expect(engine.calls, ['arm 5', 'cancel']);
  });

  test('cancel with nothing set tells nobody', () async {
    await notifier().cancel();
    expect(engine.calls, isEmpty);
  });

  testWidgets('a new choice replaces the last', (tester) async {
    await notifier().setMinutes(30);
    await notifier().setMinutes(5);
    await tester.pump(const Duration(minutes: 5));
    expect(state().isSet, isFalse);
    // One expiry: the 30-minute timer went with its replacement.
    await tester.pump(const Duration(minutes: 30));
    expect(engine.calls.where((c) => c == 'expired'), hasLength(1));
  });

  test('end of track drops a timed sleep and turns repeat off', () async {
    container
        .read(repeatStateProvider.notifier)
        .setRepeatMode(RepeatMode.infinite);
    await notifier().setMinutes(15);
    await notifier().setEndOfTrack();
    expect(state().endOfTrack, isTrue);
    expect(state().endsAt, isNull);
    expect(engine.calls, ['arm 15', 'cancel']);
    expect(container.read(repeatStateProvider), RepeatMode.none);
    expect(player.repeats, [RepeatMode.none]);
  });
}
