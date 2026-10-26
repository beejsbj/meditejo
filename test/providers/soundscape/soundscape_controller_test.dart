import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/starter_presets.dart';
import 'package:medito/models/soundscape/synth.dart';
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
  final failOnce = <String>{};
  final gates = <String, Completer<void>>{};
  final stopGates = <String, Completer<void>>{};
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
    sources[key] = source;
    await gates[key]?.future;
    if (failOnce.remove(key) || failOn.contains(key)) return false;
    playing[key] = gain;
    this.motion[key] = motion;
    return true;
  }

  final retuned = <String, LayerSource>{};
  final sources = <String, LayerSource>{};

  /// Retunes that fail (the voice limit), counted as tried.
  final retuneFails = <String>{};
  int retunes = 0;

  @override
  Future<bool> retune(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    retunes++;
    if (retuneFails.contains(key)) return false;
    retuned[key] = source;
    sources[key] = source;
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
    await stopGates[key]?.future;
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

  int shutdowns = 0;

  @override
  Future<void> shutdown() async => shutdowns++;
}

class _KeepAlive implements SoundscapeKeepAlive {
  bool held = false;
  int holds = 0;
  int focusRequests = 0;
  final _commands = StreamController<SoundscapeCommand>.broadcast();

  void send(SoundscapeCommand c) => _commands.add(c);

  @override
  Stream<SoundscapeCommand> get commands => _commands.stream;

  @override
  Future<bool> hold({
    required String title,
    required String text,
    required String stopLabel,
  }) async {
    held = true;
    holds++;
    return true;
  }

  @override
  Future<void> release() async => held = false;

  @override
  Future<void> requestFocus() async => focusRequests++;
}

class _Audio extends AudioStateNotifier {
  void setPlaying(bool playing) => state = state.copyWith(isPlaying: playing);
  void setCompleted() =>
      state = state.copyWith(isPlaying: true, isCompleted: true);
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
      // Generated layers are not library sounds.
      if (!isSynthId(layer.soundId)) _sound(layer.soundId, SoundCategory.rain),
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

  /// Practice plays a sound only once the user has chosen one (decision 17);
  /// the session tests choose the current mix, as Customize's chip does.
  void practiceOn() => ctl().setSessionDefault(
    SoundscapeSessionKind.practice,
    const SoundscapeSessionDefault(enabled: true),
  );

  setUp(() async => container = await make());

  test('a fresh install starts from the first starter preset, silent', () {
    expect(st().mix, kStarterPresets.first.mix);
    expect(st().active, isFalse);
    expect(engine.playing, isEmpty);
  });

  group('practice starts with nothing chosen (decision 17)', () {
    // The factory value before decision 17: on, the current mix, level 0.5.
    String oldFactory({Map<String, Object?> practice = const {}}) =>
        jsonEncode({
          'practice': {
            'enabled': true,
            'selection': 'mix',
            'volume': 0.5,
            ...practice,
          },
          'talks': {'enabled': false, 'selection': 'mix', 'volume': 0.35},
        });

    String mixWith(String soundId) =>
        jsonEncode(SoundMix([SoundLayer(soundId: soundId)]).toJson());

    Future<SoundscapeSessionDefault> practiceAfter(
      Map<String, Object> stored,
    ) async {
      final c = await make(stored);
      return c
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.practice);
    }

    test('a fresh install plays nothing under Practice or Talks', () async {
      expect(
        st().sessionDefault(SoundscapeSessionKind.practice).enabled,
        isFalse,
      );
      expect(st().sessionDefault(SoundscapeSessionKind.talks).enabled, isFalse);
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      expect(st().active, isFalse);
      expect(st().owner, SoundscapeOwner.none);
      expect(engine.playing, isEmpty);
      expect(keepAlive.holds, 0);
    });

    test('a pick plays, and the pick survives a relaunch', () async {
      ctl().setSessionDefault(
        SoundscapeSessionKind.practice,
        const SoundscapeSessionDefault(
          enabled: true,
          selection: SoundscapeSelection.sound('river'),
        ),
      );
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      expect(st().owner, SoundscapeOwner.session);
      expect(engine.playing.keys, ['river']);

      final again = await make({
        SoundscapeStore.sessionDefaultsKey: prefs.getString(
          SoundscapeStore.sessionDefaultsKey,
        )!,
        SoundscapeStore.sessionDefaultsVersionKey: prefs.getInt(
          SoundscapeStore.sessionDefaultsVersionKey,
        )!,
      });
      final kept = again
          .read(soundscapeProvider)
          .sessionDefault(SoundscapeSessionKind.practice);
      expect(kept.enabled, isTrue);
      expect(kept.selection, const SoundscapeSelection.sound('river'));
    });

    test(
      'an install that never touched the setting moves to nothing',
      () async {
        // Nothing stored at all: the common case.
        final fresh = await practiceAfter({});
        expect(fresh.enabled, isFalse);
        expect(prefs.getInt(SoundscapeStore.sessionDefaultsVersionKey), 2);

        // Both kinds written as a side effect (a Talks level, a deleted
        // preset), Practice still at the old factory value, no mix ever built.
        final rewritten = await practiceAfter({
          SoundscapeStore.sessionDefaultsKey: oldFactory(),
        });
        expect(rewritten.enabled, isFalse);
        expect(rewritten.selection, SoundscapeSelection.currentMix);
        expect(rewritten.volume, 0.5);
        // Talks is untouched, and the stored value now says so.
        final stored =
            jsonDecode(prefs.getString(SoundscapeStore.sessionDefaultsKey)!)
                as Map;
        expect((stored['practice'] as Map)['enabled'], isFalse);
        expect((stored['talks'] as Map)['volume'], 0.35);
      },
    );

    test(
      'a built mix keeps playing when nothing was stored for Practice',
      () async {
        // On 0.1.3 the mix alone never wrote session settings; Practice played
        // it through the old default.
        final noSettings = await practiceAfter({
          SoundscapeStore.mixKey: mixWith('river'),
        });
        expect(noSettings.enabled, isTrue);
        expect(noSettings.selection, SoundscapeSelection.currentMix);

        // Defaults stored for Talks only, still no Practice entry.
        final talksOnly = await practiceAfter({
          SoundscapeStore.mixKey: mixWith('river'),
          SoundscapeStore.sessionDefaultsKey: jsonEncode({
            'talks': {'enabled': true, 'selection': 'mix', 'volume': 0.2},
          }),
        });
        expect(talksOnly.enabled, isTrue);
        final stored =
            jsonDecode(prefs.getString(SoundscapeStore.sessionDefaultsKey)!)
                as Map;
        expect((stored['talks'] as Map)['volume'], 0.2);

        // And it plays: a Practice session starts the mix.
        final c = await make({SoundscapeStore.mixKey: mixWith('river')});
        await c
            .read(soundscapeProvider.notifier)
            .startSession(SoundscapeSessionKind.practice);
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(engine.playing.keys, ['river']);
      },
    );

    test('a damaged stored value does not hide a built mix', () async {
      for (final junk in ['not json', '[]', '{"practice": 7}']) {
        final d = await practiceAfter({
          SoundscapeStore.sessionDefaultsKey: junk,
          SoundscapeStore.mixKey: mixWith('river'),
        });
        expect(d.enabled, isTrue, reason: junk);
      }
    });

    test('an emptied mix is not a chosen sound', () async {
      final d = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(),
        SoundscapeStore.mixKey: jsonEncode(SoundMix.empty.toJson()),
      });
      expect(d.enabled, isFalse);
    });

    test('anyone who chose a sound keeps it', () async {
      // A sound put in the mixer: Practice follows "the current mix".
      final mixer = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(),
        SoundscapeStore.mixKey: mixWith('river'),
      });
      expect(mixer.enabled, isTrue);
      expect(mixer.selection, SoundscapeSelection.currentMix);

      // A preset or a single sound picked for Practice.
      final preset = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(
          practice: {'selection': 'preset:starter-night'},
        ),
      });
      expect(preset.enabled, isTrue);
      expect(
        preset.selection,
        const SoundscapeSelection.preset('starter-night'),
      );
      final single = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(
          practice: {'selection': 'sound:river'},
        ),
      });
      expect(single.enabled, isTrue);
      expect(single.selection, const SoundscapeSelection.sound('river'));

      // A level the user set means they used the setting.
      final louder = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(
          practice: {'volume': 0.8},
        ),
      });
      expect(louder.enabled, isTrue);
      expect(louder.volume, 0.8);
    });

    test('an explicit off stays off', () async {
      final d = await practiceAfter({
        SoundscapeStore.sessionDefaultsKey: oldFactory(
          practice: {'enabled': false, 'selection': 'sound:river'},
        ),
      });
      expect(d.enabled, isFalse);
      expect(d.selection, const SoundscapeSelection.sound('river'));
    });

    test(
      'a damaged stored value does not throw and starts with nothing',
      () async {
        for (final junk in ['not json', '[]', '{"practice": 7}', '{}']) {
          final d = await practiceAfter({
            SoundscapeStore.sessionDefaultsKey: junk,
          });
          expect(d.enabled, isFalse, reason: junk);
        }
      },
    );

    test(
      'the move happens once: a later choice of the same value stays',
      () async {
        // Moved on first launch ...
        final first = await make({
          SoundscapeStore.sessionDefaultsKey: oldFactory(),
        });
        expect(
          first
              .read(soundscapeProvider)
              .sessionDefault(SoundscapeSessionKind.practice)
              .enabled,
          isFalse,
        );
        // ... then the user turns Practice on with the current mix, which is
        // the very value the migration looks for ...
        first
            .read(soundscapeProvider.notifier)
            .setSessionDefault(
              SoundscapeSessionKind.practice,
              const SoundscapeSessionDefault(enabled: true),
            );
        // ... and a relaunch must not undo it.
        final second = await make({
          SoundscapeStore.sessionDefaultsKey: prefs.getString(
            SoundscapeStore.sessionDefaultsKey,
          )!,
          SoundscapeStore.sessionDefaultsVersionKey: prefs.getInt(
            SoundscapeStore.sessionDefaultsVersionKey,
          )!,
        });
        expect(
          second
              .read(soundscapeProvider)
              .sessionDefault(SoundscapeSessionKind.practice)
              .enabled,
          isTrue,
        );
      },
    );
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

  test(
    'a mix where every sound fails stops and lets go of the service',
    () async {
      engine.failOn.addAll({'cafe', 'river'});
      ctl().clearMix();
      ctl().toggleSound('cafe');
      ctl().toggleSound('river');
      await settle();
      expect(st().failed, {'cafe', 'river'});
      expect(st().active, isFalse);
      expect(st().playing, isFalse);
      expect(keepAlive.held, isFalse, reason: 'no notification over silence');
      expect(keepAlive.holds, 0, reason: 'the service never started');
      // Picking a sound that plays starts again.
      ctl().toggleSound('waves');
      await settle();
      expect(st().active, isTrue);
      expect(engine.playing.keys, ['waves']);
      expect(keepAlive.held, isTrue);
    },
  );

  test(
    'the service is taken when the first layer plays, not the last',
    () async {
      engine.gates['cafe'] = Completer<void>();
      ctl().clearMix();
      ctl().toggleSound('waves');
      ctl().toggleSound('cafe');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(engine.playing.keys, ['waves']);
      expect(keepAlive.held, isTrue, reason: 'held while cafe still loads');
      engine.gates['cafe']!.complete();
      await settle();
      expect(engine.playing.keys, containsAll(['waves', 'cafe']));
    },
  );

  test('Stop while layers are still loading starts no further layer', () async {
    engine.gates['waves'] = Completer<void>();
    ctl().clearMix();
    ctl().toggleSound('waves');
    ctl().toggleSound('cafe');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    ctl().stop();
    engine.gates['waves']!.complete();
    await settle();
    expect(engine.starts, ['waves']);
    expect(engine.playing, isEmpty);
    expect(keepAlive.held, isFalse);
  });

  test('a play that resolves after its session ended does not start', () async {
    await ctl().startSession(SoundscapeSessionKind.practice);
    await settle();
    final played = ctl().play(SoundscapeSelection.currentMix);
    ctl().endSession();
    await played;
    await settle();
    expect(st().active, isFalse);
    expect(engine.playing, isEmpty);
  });

  test(
    'a level set while a session resolves is the one it starts at',
    () async {
      final started = ctl().startSession(SoundscapeSessionKind.practice);
      ctl().setSessionVolume(SoundscapeSessionKind.practice, 0.3);
      await started;
      await settle();
      expect(st().volume, 0.3);
    },
  );

  test(
    'a failure of an overtaken pass is not held against the sound',
    () async {
      engine.failOnce.add('cafe');
      engine.gates['cafe'] = Completer<void>();
      ctl().clearMix();
      ctl().toggleSound('cafe');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ctl().toggleSound('cafe');
      ctl().toggleSound('cafe');
      engine.gates['cafe']!.complete();
      await settle();
      expect(st().failed, isEmpty);
      expect(engine.playing.keys, ['cafe']);
    },
  );

  test('a pass overtaken while a fade ends does not stop the mix', () async {
    ctl().clearMix();
    ctl().toggleSound('waves');
    await settle();
    engine.stopGates['waves'] = Completer<void>();
    engine.failOnce.add('cafe');
    await ctl().play(SoundscapeSelection.sound('cafe'));
    await settle();
    await ctl().play(SoundscapeSelection.sound('cafe'));
    engine.stopGates['waves']!.complete();
    await settle();
    expect(st().active, isTrue);
    expect(engine.playing.keys, ['cafe']);
  });

  test('a sound the library no longer has leaves the saved mix', () async {
    container.dispose();
    container = await make({
      SoundscapeStore.mixKey: jsonEncode([
        {'soundId': 'waves'},
        {'soundId': 'gone-sound'},
      ]),
    });
    ctl();
    await settle();
    expect(st().mix.layers.map((l) => l.soundId), ['waves']);
  });

  test('a saved layer with a damaged volume or params still loads', () {
    final mix = SoundMix.fromJson([
      {
        'soundId': 'waves',
        'volume': 'loud',
        'params': {1: 2},
      },
    ]);
    expect(mix.layers.single.soundId, 'waves');
    expect(mix.layers.single.volume, SoundLayer.kDefaultLayerVolume);
  });

  test('damaged session defaults fall back to the kind default', () {
    final d = SoundscapeSessionDefault.fromJson({
      'selection': 7,
      'volume': 'loud',
    }, SoundscapeSessionKind.practice);
    expect(
      d.volume,
      SoundscapeSessionDefault.initial(SoundscapeSessionKind.practice).volume,
    );
    expect(d.selection, SoundscapeSelection.currentMix);
  });

  test('an unreadable library leaves the saved mix alone', () async {
    container.dispose();
    SharedPreferences.setMockInitialValues({
      SoundscapeStore.mixKey: jsonEncode([
        {'soundId': 'waves'},
      ]),
    });
    prefs = await SharedPreferences.getInstance();
    engine = _Engine();
    keepAlive = _KeepAlive();
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        soundLibraryProvider.overrideWith((ref) async => SoundLibrary.empty),
        soundscapeEngineProvider.overrideWithValue(engine),
        soundscapeKeepAliveProvider.overrideWithValue(keepAlive),
        audioStateProvider.overrideWith(_Audio.new),
      ],
    );
    addTearDown(container.dispose);
    ctl();
    await settle();
    expect(st().mix.layers.map((l) => l.soundId), ['waves']);
    expect(prefs.getString(SoundscapeStore.mixKey), contains('waves'));
  });

  test('a play begun in one session does not land in the next', () async {
    await ctl().startSession(SoundscapeSessionKind.practice);
    await settle();
    final played = ctl().play(SoundscapeSelection.sound('river'));
    unawaited(ctl().startSession(SoundscapeSessionKind.talks));
    await played;
    await settle();
    expect(engine.playing.containsKey('river'), isFalse);
  });

  test('Play after a failure tries the failed sounds again', () async {
    engine.failOn.add('cafe');
    ctl().clearMix();
    ctl().toggleSound('cafe');
    await settle();
    expect(st().failed, {'cafe'});
    expect(st().active, isFalse);
    engine.failOn.clear();
    ctl().resume();
    await settle();
    expect(st().failed, isEmpty);
    expect(engine.playing.keys, ['cafe']);
  });

  test(
    'Sounds paused on their own stop after a while and close the engine',
    () async {
      SoundscapeController.pausedStandaloneTimeout = const Duration(
        milliseconds: 60,
      );
      addTearDown(
        () => SoundscapeController.pausedStandaloneTimeout = const Duration(
          minutes: 10,
        ),
      );
      ctl().resume();
      await settle();
      expect(keepAlive.held, isTrue);
      // Resuming in time keeps them.
      ctl().pause();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      ctl().resume();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await settle();
      expect(st().active, isTrue);

      // Headphones out, nobody comes back: the notification goes.
      keepAlive.send(SoundscapeCommand.noisy);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await settle();
      expect(st().active, isFalse);
      expect(keepAlive.held, isFalse);
      expect(engine.playing, isEmpty);
      expect(engine.shutdowns, greaterThan(0), reason: 'the stream closes');
    },
  );

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
      practiceOn();
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

    test(
      'a Customize selection replaces the default but keeps its volume',
      () async {
        await ctl().startSession(
          SoundscapeSessionKind.talks,
          selection: const SoundscapeSelection.sound('river'),
        );
        await settle();
        expect(engine.playing.keys, [
          'river',
        ], reason: 'talks are off by default');
        expect(st().volume, 0.35, reason: 'the talks level');

        // Changing the kind's default mid-session keeps the scope's choice.
        ctl().setSessionDefault(
          SoundscapeSessionKind.talks,
          const SoundscapeSessionDefault(enabled: false, volume: 0.2),
        );
        await settle();
        expect(engine.playing.keys, ['river']);
        expect(st().volume, 0.2);

        ctl().endSession();
        await ctl().startSession(
          SoundscapeSessionKind.practice,
          selection: SoundscapeSelection.none,
        );
        await settle();
        expect(st().active, isFalse, reason: 'none silences an enabled kind');
        expect(engine.playing, isEmpty);
      },
    );

    test('a kind volume set outside its session waits for it', () async {
      practiceOn();
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      ctl().setSessionVolume(SoundscapeSessionKind.talks, 0.1);
      expect(st().volume, 0.5, reason: 'not the running kind');
      expect(st().sessionDefault(SoundscapeSessionKind.talks).volume, 0.1);
      ctl().setSessionVolume(SoundscapeSessionKind.practice, 0.8);
      expect(st().volume, 0.8);
    });

    test('a session-only preset leaves the current mix alone', () async {
      ctl().clearMix();
      ctl().toggleSound('cafe');
      ctl().stop();
      await settle();
      const mine = SoundMix([SoundLayer(soundId: 'cafe')]);
      expect(st().mix, mine);

      await ctl().startSession(
        SoundscapeSessionKind.practice,
        selection: const SoundscapeSelection.preset('starter-night'),
      );
      await settle();
      expect(
        st().mix,
        kStarterPresets[1].mix,
        reason: 'what the session plays',
      );

      // Switching the session to the current mix plays the user's mix, not
      // the preset the session had put in its place.
      await ctl().startSession(
        SoundscapeSessionKind.practice,
        selection: SoundscapeSelection.currentMix,
      );
      await settle();
      expect(engine.playing.keys, ['cafe']);

      await ctl().startSession(
        SoundscapeSessionKind.practice,
        selection: const SoundscapeSelection.sound('river'),
      );
      ctl().endSession();
      await settle();
      expect(st().mix, mine);
      expect(SoundscapeStore(prefs).readMix(), mine);
    });

    test('a deleted preset or a dropped sound plays the current mix', () async {
      final evening = ctl().savePreset('Evening')!;
      ctl().setSessionDefault(
        SoundscapeSessionKind.practice,
        SoundscapeSessionDefault(
          enabled: true,
          selection: SoundscapeSelection.preset(evening.id),
        ),
      );
      ctl().deletePreset(evening.id);
      expect(
        st().sessionDefault(SoundscapeSessionKind.practice).selection,
        SoundscapeSelection.currentMix,
        reason: 'the default says what will play',
      );
      expect(
        SoundscapeStore(
          prefs,
        ).readSessionDefaults()[SoundscapeSessionKind.practice]?.selection,
        SoundscapeSelection.currentMix,
      );

      // A course's own choice of a preset or sound that no longer exists.
      for (final gone in const [
        SoundscapeSelection.preset('user-gone'),
        SoundscapeSelection.sound('not-in-the-library'),
      ]) {
        await ctl().startSession(SoundscapeSessionKind.talks, selection: gone);
        await settle();
        expect(engine.playing.keys.toSet(), {
          for (final l in st().mix.layers) l.soundId,
        });
        expect(engine.playing, isNotEmpty, reason: '$gone is not silence');
        ctl().endSession();
        await settle();
      }
      expect(
        st().playable(const SoundscapeSelection.preset('user-gone'), null),
        SoundscapeSelection.currentMix,
      );
    });

    test('the session player pausing pauses the mix', () async {
      practiceOn();
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

    test(
      'a completed voice pauses the mix though the player says playing',
      () async {
        practiceOn();
        await ctl().startSession(SoundscapeSessionKind.practice);
        await settle();
        final audio = container.read(audioStateProvider.notifier) as _Audio;
        audio.setPlaying(true);
        await settle();
        expect(engine.paused, isFalse);
        audio.setCompleted();
        await settle();
        expect(engine.paused, isTrue);
      },
    );

    test('defaults persist', () async {
      practiceOn();
      final again = await make({
        SoundscapeStore.sessionDefaultsKey: prefs.getString(
          SoundscapeStore.sessionDefaultsKey,
        )!,
        SoundscapeStore.sessionDefaultsVersionKey: prefs.getInt(
          SoundscapeStore.sessionDefaultsVersionKey,
        )!,
      });
      final state = again.read(soundscapeProvider);
      expect(
        state.sessionDefault(SoundscapeSessionKind.practice).enabled,
        isTrue,
      );
      expect(
        state.sessionDefault(SoundscapeSessionKind.talks).enabled,
        isFalse,
      );
    });
  });

  group('generated layers', () {
    test('noise starts as a generated loop with default settings', () async {
      ctl().clearMix();
      ctl().toggleSound(kSynthNoiseId);
      await settle();
      final layer = st().mix.layer(kSynthNoiseId)!;
      expect(layer.params, const NoiseParams().toJson());
      final source = engine.sources[kSynthNoiseId] as NoiseLoopSource;
      expect(source.spec.params.colour, NoiseColour.pink);
    });

    test('changing settings retunes in place instead of restarting', () async {
      ctl().clearMix();
      ctl().toggleSound(kSynthNoiseId);
      ctl().toggleSound(kSynthBinauralId);
      await settle();
      final starts = engine.starts.length;
      ctl().setLayerParams(
        kSynthNoiseId,
        const NoiseParams(colour: NoiseColour.brown).toJson(),
      );
      ctl().setLayerParams(
        kSynthBinauralId,
        const BinauralParams(carrierHz: 150, beatHz: 10).toJson(),
      );
      await settle();
      expect(engine.starts.length, starts);
      final noise = engine.retuned[kSynthNoiseId] as NoiseLoopSource;
      expect(noise.spec.params.colour, NoiseColour.brown);
      final beats = engine.retuned[kSynthBinauralId] as OscillatorSource;
      expect(beats.partials.map((p) => p.hz), [145, 155]);
      // A volume change alone does not retune.
      engine.retuned.clear();
      ctl().setLayerVolume(kSynthNoiseId, 0.3);
      await settle();
      expect(engine.retuned, isEmpty);
    });

    test('generated layers stay in the saved mix and play', () async {
      container.dispose();
      container = await make({
        SoundscapeStore.mixKey: jsonEncode([
          {'soundId': 'waves'},
          {'soundId': kSynthNoiseId, 'params': const NoiseParams().toJson()},
          {'soundId': kSynthDroneId},
          {'soundId': 'gone-sound'},
        ]),
      });
      ctl();
      await settle();
      // Only the sound the library dropped leaves.
      expect(st().mix.layers.map((l) => l.soundId), [
        'waves',
        kSynthNoiseId,
        kSynthDroneId,
      ]);
      ctl().resume();
      await settle();
      expect(engine.playing.keys, {'waves', kSynthNoiseId, kSynthDroneId});
      expect(engine.sources[kSynthDroneId], isA<OscillatorSource>());
      // Nor does a session treat one as a sound the library dropped.
      final noise = SoundscapeSelection.sound(kSynthNoiseId);
      expect(st().playable(noise, _library), noise);
    });

    test('the Stillness preset plays its generated layers', () async {
      await ctl().play(SoundscapeSelection.preset('starter-stillness'));
      await settle();
      expect(engine.playing.keys, {kSynthNoiseId, kSynthDroneId});
      await ctl().startSession(
        SoundscapeSessionKind.practice,
        selection: SoundscapeSelection.preset('starter-stillness'),
      );
      await settle();
      expect(st().underSession, isTrue);
      expect(engine.playing.keys, {kSynthNoiseId, kSynthDroneId});
    });

    test('a failed retune keeps the old settings as what plays', () async {
      ctl().clearMix();
      ctl().toggleSound(kSynthDroneId);
      await settle();
      engine.retuneFails.add(kSynthDroneId);
      // New settings and a new volume in one pass; the settings fail (the
      // voice limit), but the volume still reaches the engine.
      const bright = DroneParams(timbre: DroneTimbre.bright);
      ctl().setLayerParams(kSynthDroneId, bright.toJson());
      ctl().setLayerVolume(kSynthDroneId, 0.9);
      await settle();
      expect(engine.retunes, 1);
      expect(engine.playing[kSynthDroneId], closeTo(layerGain(0.9), 1e-9));
      // Later passes (a volume drag) don't regenerate the failed settings.
      ctl().setLayerVolume(kSynthDroneId, 0.3);
      await settle();
      ctl().setLayerVolume(kSynthDroneId, 0.4);
      await settle();
      expect(engine.retunes, 1);
      expect(engine.playing[kSynthDroneId], closeTo(layerGain(0.4), 1e-9));
      // Other settings, or the same ones chosen again after them, are tried.
      engine.retuneFails.clear();
      ctl().setLayerParams(
        kSynthDroneId,
        const DroneParams(timbre: DroneTimbre.pure).toJson(),
      );
      await settle();
      ctl().setLayerParams(kSynthDroneId, bright.toJson());
      await settle();
      expect(engine.retunes, 3);
      final played = engine.retuned[kSynthDroneId] as OscillatorSource;
      expect(played.partials, bright.partials());
    });

    test('a preset keeps generated settings', () async {
      ctl().clearMix();
      ctl().toggleSound(kSynthDroneId);
      ctl().setLayerParams(
        kSynthDroneId,
        const DroneParams(rootHz: 73.42, timbre: DroneTimbre.pure).toJson(),
      );
      final saved = ctl().savePreset('Low drone')!;
      final again = await make({
        SoundscapeStore.presetsKey: prefs.getString(
          SoundscapeStore.presetsKey,
        )!,
      });
      final preset = again
          .read(soundscapeProvider)
          .presets
          .firstWhere((p) => p.id == saved.id);
      final drone = DroneParams.fromJson(
        preset.mix.layer(kSynthDroneId)!.params,
      );
      expect(drone.rootHz, 73.42);
      expect(drone.timbre, DroneTimbre.pure);
    });
  });

  group('review fixes', () {
    test('a sound added during a silent session joins the session', () async {
      await ctl().startSession(SoundscapeSessionKind.talks); // off by default
      await settle();
      expect(st().inSession, isTrue);
      expect(st().active, isFalse);
      ctl().toggleSound('cafe');
      await settle();
      expect(st().owner, SoundscapeOwner.session);
      expect(keepAlive.held, isFalse, reason: 'never a second service');
      expect(engine.playing.containsKey('cafe'), isTrue);
      ctl().endSession();
      await settle();
      expect(engine.playing, isEmpty);
      expect(st().inSession, isFalse);
    });

    test('Stop mid-session keeps the session; resuming rejoins it', () async {
      practiceOn();
      await ctl().startSession(SoundscapeSessionKind.practice);
      await settle();
      ctl().stop();
      await settle();
      expect(st().active, isFalse);
      expect(st().inSession, isTrue);
      ctl().resume();
      await settle();
      expect(st().owner, SoundscapeOwner.session);
      expect(keepAlive.held, isFalse);
    });

    test('a mix the user paused stays paused through a call', () async {
      ctl().resume();
      await settle();
      ctl().pause();
      keepAlive.send(SoundscapeCommand.pause);
      keepAlive.send(SoundscapeCommand.resume);
      await settle();
      expect(st().playing, isFalse);
    });

    test(
      'unplugging headphones pauses, and a call ending does not resume',
      () async {
        ctl().resume();
        await settle();
        keepAlive.send(SoundscapeCommand.pause);
        await settle();
        keepAlive.send(SoundscapeCommand.noisy);
        keepAlive.send(SoundscapeCommand.resume);
        await settle();
        expect(st().playing, isFalse, reason: 'not on to the speaker');
        expect(keepAlive.held, isTrue, reason: 'paused, not stopped');
        ctl().resume();
        await settle();
        expect(st().playing, isTrue);
      },
    );

    test('after another app takes focus, resuming asks for it again', () async {
      ctl().resume();
      await settle();
      keepAlive.send(SoundscapeCommand.lost);
      await settle();
      expect(st().playing, isFalse);
      keepAlive.send(SoundscapeCommand.resume);
      await settle();
      expect(st().playing, isFalse, reason: 'a lasting loss is not undone');
      ctl().resume();
      await settle();
      expect(st().playing, isTrue);
      expect(keepAlive.focusRequests, 1);
    });

    test(
      'changing a default while the session is paused stays paused',
      () async {
        practiceOn();
        await ctl().startSession(SoundscapeSessionKind.practice);
        ctl().setSessionPaused(true);
        await settle();
        expect(engine.paused, isTrue);
        ctl().setSessionDefault(
          SoundscapeSessionKind.practice,
          const SoundscapeSessionDefault(
            enabled: true,
            selection: SoundscapeSelection.sound('river'),
          ),
        );
        await settle();
        expect(st().playing, isFalse);
        expect(engine.paused, isTrue);
        expect(engine.playing.keys, ['river']);
      },
    );

    test('a session ended while its mix resolves plays nothing', () async {
      practiceOn();
      final starting = ctl().startSession(SoundscapeSessionKind.practice);
      ctl().endSession();
      await starting;
      await settle();
      expect(st().active, isFalse);
      expect(engine.playing, isEmpty);
    });

    test('layers compare settings by value', () {
      const a = SoundLayer(
        soundId: 'x',
        params: {
          'bands': [1.0, 0.5],
        },
      );
      final b = SoundLayer(
        soundId: 'x',
        params: {
          'bands': [1, 0.5],
        },
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            const SoundLayer(
              soundId: 'x',
              params: {
                'bands': [1.0],
              },
            ),
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
