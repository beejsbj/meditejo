import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';
import 'package:medito/services/soundscape/soundscape_keep_alive.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Engine implements SoundscapeEngine {
  final playing = <String, double>{};
  final motion = <String, LayerMotion?>{};
  final starts = <String>[];
  final failOn = <String>{};
  double master = 1;
  bool paused = false;

  @override
  Future<bool> start(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    starts.add(key);
    if (failOn.contains(key)) return false;
    playing[key] = gain;
    this.motion[key] = motion;
    return true;
  }

  @override
  void setGain(String key, double gain, {LayerMotion? motion}) {
    playing[key] = gain;
    this.motion[key] = motion;
  }

  @override
  Future<void> stop(String key, {Duration fade = Duration.zero}) async {
    playing.remove(key);
    motion.remove(key);
  }

  @override
  void setMaster(double gain, {Duration fade = Duration.zero}) => master = gain;

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  Future<void> stopAll({Duration fade = Duration.zero}) async =>
      playing.clear();
}

class _KeepAlive implements SoundscapeKeepAlive {
  bool held = false;
  int holds = 0;
  final _commands = StreamController<SoundscapeCommand>.broadcast();

  void send(SoundscapeCommand c) => _commands.add(c);

  @override
  Stream<SoundscapeCommand> get commands => _commands.stream;

  @override
  Future<void> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async {
    held = true;
    holds++;
  }

  @override
  Future<void> release() async => held = false;
}

class _Audio extends AudioStateNotifier {
  void setPlaying(bool playing) => state = state.copyWith(isPlaying: playing);
}

SoundEntry _sound(String id, SoundCategory category) => SoundEntry(
  id: id,
  title: id,
  category: category,
  asset: 'assets/sounds/$id.opus',
  license: SoundLicense.cc0,
  author: 'Someone',
  sourceUrl: 'https://example.org/$id',
);

final _library = SoundLibrary([
  for (final preset in kStarterPresets)
    for (final layer in preset.mix.layers)
      _sound(layer.soundId, SoundCategory.rain),
  _sound('cafe', SoundCategory.room),
  _sound('river', SoundCategory.water),
  for (var i = 0; i < 8; i++) _sound('extra-$i', SoundCategory.night),
]);

void main() {
  late _Engine engine;
  late _KeepAlive keepAlive;
  late ProviderContainer container;
  late SharedPreferences prefs;

  Future<ProviderContainer> make([
    Map<String, Object> values = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = await SharedPreferences.getInstance();
    engine = _Engine();
    keepAlive = _KeepAlive();
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundLibraryProvider.overrideWith((ref) async => _library),
        soundscapeEngineProvider.overrideWithValue(engine),
        soundscapeKeepAliveProvider.overrideWithValue(keepAlive),
        audioStateProvider.overrideWith(_Audio.new),
      ],
    );
    addTearDown(c.dispose);
    await c.read(soundLibraryProvider.future);
    return c;
  }

  SoundscapeController ctl() => container.read(soundscapeProvider.notifier);
  SoundscapeState st() => container.read(soundscapeProvider);
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async => container = await make());

  test('a fresh install starts from the first starter preset, silent', () {
    expect(st().mix, kStarterPresets.first.mix);
    expect(st().active, isFalse);
    expect(engine.playing, isEmpty);
  });

  test('adding a sound to a silent mixer plays it on its own', () async {
    ctl().clearMix();
    ctl().toggleSound('cafe');
    await settle();
    expect(st().owner, SoundscapeOwner.standalone);
    expect(st().playing, isTrue);
    expect(engine.playing.keys, ['cafe']);
    expect(engine.playing['cafe'], closeTo(layerGain(0.6), 1e-9));
    expect(keepAlive.held, isTrue);
  });

  test('volume, drift and removal reach the engine', () async {
    ctl().clearMix();
    ctl().toggleSound('cafe');
    ctl().toggleSound('river');
    await settle();
    ctl().setLayerVolume('river', 0.5);
    ctl().setLayerAnimate('river', true);
    ctl().setVolume(0.4);
    await settle();
    expect(engine.playing['river'], closeTo(0.25, 1e-9));
    expect(engine.motion['river'], LayerMotion.forSound('river'));
    expect(engine.motion['cafe'], isNull);
    expect(engine.master, closeTo(0.16, 1e-9));

    ctl().toggleSound('cafe');
    await settle();
    expect(engine.playing.keys, ['river']);

    // Taking out the last layer stops the mixer and lets the app go.
    ctl().toggleSound('river');
    await settle();
    expect(st().active, isFalse);
    expect(engine.playing, isEmpty);
    expect(keepAlive.held, isFalse);
  });

  test('pause keeps the layers loaded; stop unloads them', () async {
    ctl().resume();
    await settle();
    final loaded = engine.playing.keys.toSet();
    expect(loaded, isNotEmpty);
    ctl().pause();
    await settle();
    expect(engine.paused, isTrue);
    expect(engine.playing.keys.toSet(), loaded);
    expect(keepAlive.held, isTrue, reason: 'resume must stay possible');
    ctl().stop();
    await settle();
    expect(engine.playing, isEmpty);
    expect(keepAlive.held, isFalse);
  });

  test('a mix holds at most kMaxLayers sounds', () async {
    ctl().clearMix();
    for (var i = 0; i < 8; i++) {
      ctl().toggleSound('extra-$i');
    }
    await settle();
    expect(st().mix.layers.length, SoundMix.kMaxLayers);
    expect(ctl().canAddLayer, isFalse);
  });

  test('a sound that fails to load is marked and skipped', () async {
    engine.failOn.add('cafe');
    ctl().clearMix();
    ctl().toggleSound('cafe');
    ctl().toggleSound('river');
    await settle();
    expect(st().failed, {'cafe'});
    expect(engine.playing.keys, ['river']);
  });

  test(
    'the notification Stop and focus changes drive standalone play',
    () async {
      ctl().resume();
      await settle();
      keepAlive.send(SoundscapeCommand.pause);
      await settle();
      expect(st().playing, isFalse);
      keepAlive.send(SoundscapeCommand.resume);
      await settle();
      expect(st().playing, isTrue);
      keepAlive.send(SoundscapeCommand.stop);
      await settle();
      expect(st().active, isFalse);
    },
  );

  group('presets', () {
    test('apply, save and delete; saved presets persist', () async {
      ctl().applyPreset('starter-night');
      await settle();
      expect(st().matchingPreset?.id, 'starter-night');
      expect(engine.playing.keys.toSet(), {
        for (final l in kStarterPresets[1].mix.layers) l.soundId,
      });

      ctl().toggleSound('cafe');
      expect(st().matchingPreset, isNull);
      final saved = ctl().savePreset('  Evening  ')!;
      expect(saved.name, 'Evening');
      expect(st().matchingPreset?.id, saved.id);

      final again = await make({
        SoundscapeStore.presetsKey: prefs.getString(
          SoundscapeStore.presetsKey,
        )!,
        SoundscapeStore.mixKey: prefs.getString(SoundscapeStore.mixKey)!,
      });
      final reloaded = again.read(soundscapeProvider);
      expect(reloaded.userPresets.single.name, 'Evening');
      expect(reloaded.matchingPreset?.id, saved.id);

      again.read(soundscapeProvider.notifier).deletePreset(saved.id);
      expect(again.read(soundscapeProvider).userPresets, isEmpty);
    });

    test('an empty name or an empty mix saves nothing', () {
      expect(ctl().savePreset('   '), isNull);
      ctl().clearMix();
      expect(ctl().savePreset('Nothing'), isNull);
    });
  });

  group('sessions', () {
    test('practice plays the current mix at its own volume', () async {
      ctl().setVolume(0.9);
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      expect(st().owner, SoundscapeOwner.session);
      expect(st().volume, 0.5);
      expect(engine.master, closeTo(0.25, 1e-9));
      expect(engine.playing.keys.toSet(), {
        for (final l in kStarterPresets.first.mix.layers) l.soundId,
      });
      expect(keepAlive.held, isFalse, reason: 'the session holds the app');

      // Changing the volume under a session changes that kind's level.
      ctl().setVolume(0.3);
      expect(st().sessionDefault(SoundscapeSessionKind.practice).volume, 0.3);
      ctl().endSession();
      await settle();
      expect(engine.playing, isEmpty);
      expect(st().volume, 0.9, reason: 'standalone volume is untouched');
    });

    test(
      'talks are silent by default, and a talk default can be turned on',
      () async {
        await ctl().startSession(SoundscapeSessionKind.talks);
        await settle();
        expect(st().active, isFalse);
        expect(engine.playing, isEmpty);

        ctl().setSessionDefault(
          SoundscapeSessionKind.talks,
          const SoundscapeSessionDefault(
            enabled: true,
            selection: SoundscapeSelection.sound('river'),
            volume: 0.2,
          ),
        );
        await ctl().startSession(SoundscapeSessionKind.talks);
        await settle();
        expect(engine.playing.keys, ['river']);
        expect(st().volume, 0.2);
      },
    );

    test('a session takes over sounds playing on their own', () async {
      ctl().clearMix();
      ctl().toggleSound('cafe');
      await settle();
      expect(keepAlive.held, isTrue);
      await ctl().startSession(
        SoundscapeSessionKind.practice,
        override: const SoundscapeSessionDefault(
          enabled: true,
          selection: SoundscapeSelection.preset('starter-shore'),
        ),
      );
      await settle();
      expect(st().owner, SoundscapeOwner.session);
      expect(keepAlive.held, isFalse);
      expect(engine.playing.keys.toSet(), {
        for (final l in kStarterPresets[3].mix.layers) l.soundId,
      });
    });

    test('the session player pausing pauses the mix', () async {
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      final audio = container.read(audioStateProvider.notifier) as _Audio;
      audio.setPlaying(true);
      audio.setPlaying(false);
      await settle();
      expect(engine.paused, isTrue);
      audio.setPlaying(true);
      await settle();
      expect(engine.paused, isFalse);
    });

    test('defaults persist', () async {
      ctl().setSessionDefault(
        SoundscapeSessionKind.practice,
        const SoundscapeSessionDefault(enabled: false),
      );
      final again = await make({
        SoundscapeStore.sessionDefaultsKey: prefs.getString(
          SoundscapeStore.sessionDefaultsKey,
        )!,
      });
      final state = again.read(soundscapeProvider);
      expect(
        state.sessionDefault(SoundscapeSessionKind.practice).enabled,
        isFalse,
      );
      expect(
        state.sessionDefault(SoundscapeSessionKind.talks).enabled,
        isFalse,
      );
    });
  });

  test('play() resolves a selection; unknown sounds are skipped', () async {
    await ctl().play(const SoundscapeSelection.sound('not-in-library'));
    await settle();
    expect(st().active, isFalse);
    await ctl().play(const SoundscapeSelection.sound('river'), volume: 0.6);
    await settle();
    expect(engine.playing.keys, ['river']);
    expect(st().volume, 0.6);
    await ctl().play(SoundscapeSelection.none);
    await settle();
    expect(st().active, isFalse);
  });
}
