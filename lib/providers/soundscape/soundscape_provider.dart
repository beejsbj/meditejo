import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/soundscape/sound_library.dart';
import '../../models/soundscape/sound_mix.dart';
import '../../models/soundscape/starter_presets.dart';
import '../../models/soundscape/synth.dart';
import '../../services/soundscape/soundscape_engine.dart';
import '../../services/soundscape/soundscape_keep_alive.dart';
import '../../services/soundscape/soundscape_store.dart';
import '../../services/soundscape/synth/noise_generator.dart';
import '../../utils/logger.dart';
import '../player/audio_state_provider.dart';
import '../shared_preference/shared_preference_provider.dart';

/// The bundled library (`assets/sounds/sounds.json`).
final soundLibraryProvider = FutureProvider<SoundLibrary>((ref) async {
  ref.keepAlive();
  try {
    final raw = await rootBundle.loadString(kSoundLibraryAsset);
    return SoundLibrary.fromJson(jsonDecode(raw) as Map<String, Object?>);
  } catch (error, stack) {
    AppLogger.e('SOUNDSCAPE', 'Could not read the sound library', error, stack);
    return SoundLibrary.empty;
  }
});

final soundscapeEngineProvider = Provider<SoundscapeEngine>(
  (ref) => SoLoudSoundscapeEngine(),
);

final soundscapeKeepAliveProvider = Provider<SoundscapeKeepAlive>(
  (ref) => platformSoundscapeKeepAlive(),
);

/// Text for the Android notification shown while Sounds play on their own.
class SoundscapeNotificationText {
  const SoundscapeNotificationText({
    required this.title,
    required this.text,
    required this.stop,
  });

  final String title;
  final String text;
  final String stop;
}

/// Who the mixer is playing for.
enum SoundscapeOwner {
  /// Nothing loaded.
  none,

  /// The Sounds screen, on its own. Android holds `SoundscapeService`.
  standalone,

  /// Under a session: follows the session player's play/pause, and the
  /// session's foreground service keeps the app alive.
  session,
}

@immutable
class SoundscapeState {
  const SoundscapeState({
    this.mix = SoundMix.empty,
    this.volume = 0.7,
    this.playing = false,
    this.owner = SoundscapeOwner.none,
    this.sessionKind,
    this.userPresets = const [],
    this.failed = const {},
    this.sessionDefaults = const {},
  });

  /// The current mix: what plays, or would play on Play.
  final SoundMix mix;

  /// Master level, 0–1: the Sounds volume on its own, or the session kind's
  /// volume under a session.
  final double volume;
  final bool playing;
  final SoundscapeOwner owner;
  final SoundscapeSessionKind? sessionKind;
  final List<SoundPreset> userPresets;

  /// Sounds that failed to load this run; skipped until picked again.
  final Set<String> failed;
  final Map<SoundscapeSessionKind, SoundscapeSessionDefault> sessionDefaults;

  /// Loaded and audible or paused (not stopped).
  bool get active => owner != SoundscapeOwner.none;

  bool get underSession => owner == SoundscapeOwner.session;

  List<SoundPreset> get presets => [...kStarterPresets, ...userPresets];

  /// The preset the current mix still matches, if any.
  SoundPreset? get matchingPreset {
    for (final p in presets) {
      if (p.mix == mix) return p;
    }
    return null;
  }

  SoundscapeSessionDefault sessionDefault(SoundscapeSessionKind kind) =>
      sessionDefaults[kind] ?? SoundscapeSessionDefault.initial(kind);

  SoundscapeState copyWith({
    SoundMix? mix,
    double? volume,
    bool? playing,
    SoundscapeOwner? owner,
    Object? sessionKind = _keep,
    List<SoundPreset>? userPresets,
    Set<String>? failed,
    Map<SoundscapeSessionKind, SoundscapeSessionDefault>? sessionDefaults,
  }) => SoundscapeState(
    mix: mix ?? this.mix,
    volume: volume ?? this.volume,
    playing: playing ?? this.playing,
    owner: owner ?? this.owner,
    sessionKind: sessionKind == _keep
        ? this.sessionKind
        : sessionKind as SoundscapeSessionKind?,
    userPresets: userPresets ?? this.userPresets,
    failed: failed ?? this.failed,
    sessionDefaults: sessionDefaults ?? this.sessionDefaults,
  );
}

const _keep = Object();

/// Slider position to gain: squared, so the low end of the slider has room
/// for a sound barely there.
double layerGain(double volume) => volume * volume;

final soundscapeProvider =
    NotifierProvider<SoundscapeController, SoundscapeState>(
      SoundscapeController.new,
    );

/// The mixer: the Sounds screen and sessions drive it; it drives the
/// [SoundscapeEngine]. See "Sounds and the mixer" in ARCHITECTURE.md for the
/// API the player's Customize sheet uses.
class SoundscapeController extends Notifier<SoundscapeState> {
  late SoundscapeStore _store;
  late SoundscapeEngine _engine;
  late SoundscapeKeepAlive _keepAlive;
  StreamSubscription<SoundscapeCommand>? _commands;

  /// What the engine is playing, by sound id.
  final _applied = <String, SoundLayer>{};
  Future<void> _sync = Future.value();
  bool _held = false;
  bool? _enginePaused;
  double? _engineVolume;
  var _notification = const SoundscapeNotificationText(
    title: 'Sounds',
    text: 'Playing your mix',
    stop: 'Stop',
  );

  /// The Sounds screen passes localised text as it opens.
  void setNotificationText(SoundscapeNotificationText text) =>
      _notification = text;

  @override
  SoundscapeState build() {
    _store = SoundscapeStore(ref.watch(sharedPreferencesProvider));
    _engine = ref.watch(soundscapeEngineProvider);
    _keepAlive = ref.watch(soundscapeKeepAliveProvider);
    _commands = _keepAlive.commands.listen(_onCommand);
    ref.onDispose(() {
      _commands?.cancel();
      if (_held) unawaited(_keepAlive.release());
      unawaited(_engine.stopAll(fade: Duration.zero));
    });
    // Under a session, follow the session player (pauses, phone calls).
    ref.listen(audioStateProvider.select((s) => s.isPlaying), (_, playing) {
      if (state.underSession && state.playing != playing) {
        _update(state.copyWith(playing: playing));
      }
    });
    return SoundscapeState(
      mix: _store.readMix() ?? kStarterPresets.first.mix,
      volume: _store.readVolume(),
      userPresets: _store.readPresets(),
      sessionDefaults: _store.readSessionDefaults(),
    );
  }

  // ---------------------------------------------------------------------------
  // The Sounds screen

  /// Adds [soundId] to the mix, or takes it out. Adding to a silent mixer
  /// starts it on its own.
  void toggleSound(String soundId) {
    final mix = state.mix;
    if (mix.contains(soundId)) {
      _editMix(mix.remove(soundId));
      return;
    }
    if (mix.layers.length >= SoundMix.kMaxLayers) return;
    final failed = {...state.failed}..remove(soundId);
    _editMix(
      mix.put(
        SoundLayer(soundId: soundId, params: defaultSynthParams(soundId)),
      ),
      failed: failed,
      start: true,
    );
  }

  bool get canAddLayer => state.mix.layers.length < SoundMix.kMaxLayers;

  void setLayerVolume(String soundId, double volume) {
    final layer = state.mix.layer(soundId);
    if (layer == null) return;
    _editMix(state.mix.put(layer.copyWith(volume: volume.clamp(0.0, 1.0))));
  }

  void setLayerAnimate(String soundId, bool animate) {
    final layer = state.mix.layer(soundId);
    if (layer == null) return;
    _editMix(state.mix.put(layer.copyWith(animate: animate)));
  }

  /// A generated layer's settings (noise bands, drone root, beat …), as
  /// JSON (see `synth.dart`). The engine retunes it without a gap.
  void setLayerParams(String soundId, Map<String, Object?> params) {
    final layer = state.mix.layer(soundId);
    if (layer == null) return;
    _editMix(state.mix.put(layer.copyWith(params: params)));
  }

  void clearMix() => _editMix(SoundMix.empty);

  /// Master volume. Under a session it is that session kind's level.
  void setVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    final kind = state.sessionKind;
    if (state.underSession && kind != null) {
      final defaults = {
        ...state.sessionDefaults,
        kind: state.sessionDefault(kind).copyWith(volume: v),
      };
      _store.writeSessionDefaults(defaults);
      _update(state.copyWith(volume: v, sessionDefaults: defaults));
    } else {
      _store.writeVolume(v);
      _update(state.copyWith(volume: v));
    }
  }

  /// Play or pause. Starting from silence plays the current mix on its own.
  void togglePlay() {
    if (state.playing) {
      pause();
    } else {
      resume();
    }
  }

  void pause() => _update(state.copyWith(playing: false));

  void resume() {
    if (state.mix.isEmpty) return;
    if (state.active) {
      _update(state.copyWith(playing: true));
    } else {
      _startStandalone();
    }
  }

  /// Stops everything (the Sounds screen's Stop; the notification's Stop).
  void stop() => _update(
    state.copyWith(
      playing: false,
      owner: SoundscapeOwner.none,
      sessionKind: null,
      volume: _store.readVolume(),
    ),
  );

  /// Plays [selection] now. Outside a session it plays on its own; under a
  /// session it replaces what the session plays.
  Future<void> play(SoundscapeSelection selection, {double? volume}) async {
    final mix = await _resolve(selection);
    if (mix.isEmpty) {
      if (state.underSession) {
        _update(state.copyWith(playing: false));
      } else {
        stop();
      }
      return;
    }
    _store.writeMix(mix);
    if (state.underSession) {
      _update(
        state.copyWith(mix: mix, playing: true, volume: volume ?? state.volume),
      );
    } else {
      _update(state.copyWith(mix: mix));
      _startStandalone(volume: volume);
    }
  }

  void applyPreset(String presetId) =>
      unawaited(play(SoundscapeSelection.preset(presetId)));

  /// Saves the current mix as a preset named [name] and returns it.
  SoundPreset? savePreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || state.mix.isEmpty) return null;
    final preset = SoundPreset(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      mix: state.mix,
    );
    final presets = [...state.userPresets, preset];
    _store.writePresets(presets);
    _update(state.copyWith(userPresets: presets));
    return preset;
  }

  void deletePreset(String presetId) {
    final presets = [
      for (final p in state.userPresets)
        if (p.id != presetId) p,
    ];
    _store.writePresets(presets);
    _update(state.copyWith(userPresets: presets));
  }

  // ---------------------------------------------------------------------------
  // Sessions (decision 8): on for Practice, off for Talks by default.

  SoundscapeSessionDefault sessionDefault(SoundscapeSessionKind kind) =>
      state.sessionDefault(kind);

  void setSessionDefault(
    SoundscapeSessionKind kind,
    SoundscapeSessionDefault value,
  ) {
    final defaults = {...state.sessionDefaults, kind: value};
    _store.writeSessionDefaults(defaults);
    _update(state.copyWith(sessionDefaults: defaults));
    if (state.underSession && state.sessionKind == kind) {
      unawaited(startSession(kind));
    }
  }

  /// A session of [kind] is starting: play what its default says (or
  /// [override], for a caller that keeps its own setting), at its volume.
  /// Takes over anything playing on its own.
  Future<void> startSession(
    SoundscapeSessionKind kind, {
    SoundscapeSessionDefault? override,
  }) async {
    final setting = override ?? state.sessionDefault(kind);
    final mix = setting.enabled
        ? await _resolve(setting.selection)
        : SoundMix.empty;
    if (mix.isEmpty) {
      _update(
        state.copyWith(
          playing: false,
          owner: SoundscapeOwner.none,
          sessionKind: null,
        ),
      );
      return;
    }
    _update(
      state.copyWith(
        mix: mix,
        playing: true,
        owner: SoundscapeOwner.session,
        sessionKind: kind,
        volume: setting.volume,
      ),
    );
  }

  /// The session player paused or resumed (iOS calls this; Android's state
  /// arrives through [audioStateProvider]).
  void setSessionPaused(bool paused) {
    if (state.underSession) _update(state.copyWith(playing: !paused));
  }

  /// The session is over: fade out and stop.
  void endSession() {
    if (state.underSession) stop();
  }

  // ---------------------------------------------------------------------------

  Future<SoundMix> _resolve(SoundscapeSelection selection) async {
    final library = await ref.read(soundLibraryProvider.future);
    final SoundMix mix = switch (selection.kind) {
      SoundscapeSelectionKind.none => SoundMix.empty,
      SoundscapeSelectionKind.mix =>
        state.mix.isEmpty ? kStarterPresets.first.mix : state.mix,
      SoundscapeSelectionKind.preset =>
        state.presets.where((p) => p.id == selection.id).firstOrNull?.mix ??
            SoundMix.empty,
      SoundscapeSelectionKind.sound => SoundMix([
        SoundLayer(soundId: selection.id, volume: 0.8),
      ]),
    };
    return mix.where((id) => _isKnown(id, library));
  }

  static bool _isKnown(String id, SoundLibrary library) =>
      library.contains(id) || isSynthId(id);

  static LayerSource _sourceFor(SoundLayer layer, SoundLibrary library) =>
      switch (layer.soundId) {
        kSynthNoiseId => NoiseLoopSource(
          NoiseSpec(params: NoiseParams.fromJson(layer.params)),
        ),
        kSynthDroneId => OscillatorSource(
          DroneParams.fromJson(layer.params).partials(),
        ),
        kSynthBinauralId => OscillatorSource(
          BinauralParams.fromJson(layer.params).partials(),
        ),
        _ => AssetLoopSource(library[layer.soundId]!.asset),
      };

  void _editMix(SoundMix mix, {Set<String>? failed, bool start = false}) {
    _store.writeMix(mix);
    if (mix.isEmpty && state.owner == SoundscapeOwner.standalone) {
      _update(state.copyWith(mix: mix, failed: failed));
      stop();
      return;
    }
    _update(state.copyWith(mix: mix, failed: failed));
    if (start && !state.active) _startStandalone();
  }

  void _startStandalone({double? volume}) {
    if (volume != null) _store.writeVolume(volume.clamp(0.0, 1.0));
    _update(
      state.copyWith(
        playing: true,
        owner: SoundscapeOwner.standalone,
        sessionKind: null,
        volume: _store.readVolume(),
      ),
    );
  }

  void _onCommand(SoundscapeCommand command) {
    if (state.owner != SoundscapeOwner.standalone) return;
    switch (command) {
      case SoundscapeCommand.stop:
        stop();
      case SoundscapeCommand.pause:
        pause();
      case SoundscapeCommand.resume:
        resume();
    }
  }

  void _update(SoundscapeState next) {
    if (!ref.mounted) return;
    state = next;
    _sync = _sync.then((_) => _apply()).catchError((
      Object error,
      StackTrace s,
    ) {
      AppLogger.e('SOUNDSCAPE', 'Mixer sync failed', error, s);
    });
  }

  /// Brings the engine and the keep-alive service in line with [state].
  /// Serialised: one pass at a time, each reading the latest state.
  Future<void> _apply() async {
    if (!ref.mounted) return;
    final library = await ref.read(soundLibraryProvider.future);
    if (!ref.mounted) return;
    final s = state;
    final desired = <String, SoundLayer>{
      if (s.active)
        for (final l in s.mix.layers)
          if (_isKnown(l.soundId, library) && !s.failed.contains(l.soundId))
            l.soundId: l,
    };

    await _holdKeepAlive(s.owner == SoundscapeOwner.standalone && s.active);

    final gain = layerGain(s.volume);
    if (_engineVolume != gain) {
      _engine.setMaster(gain);
      _engineVolume = gain;
    }
    if (_enginePaused != !s.playing) {
      _engine.setPaused(!s.playing);
      _enginePaused = !s.playing;
    }

    final stopping = [
      for (final id in [..._applied.keys])
        if (!desired.containsKey(id)) id,
    ];
    for (final id in stopping) {
      _applied.remove(id);
    }
    final fades = [for (final id in stopping) _engine.stop(id)];

    final failed = <String>{};
    for (final layer in desired.values) {
      final motion = layer.animate ? LayerMotion.forSound(layer.soundId) : null;
      final current = _applied[layer.soundId];
      if (current == null) {
        final ok = await _engine.start(
          layer.soundId,
          _sourceFor(layer, library),
          gain: layerGain(layer.volume),
          motion: motion,
        );
        if (ok) {
          _applied[layer.soundId] = layer;
        } else {
          failed.add(layer.soundId);
        }
      } else if (!mapEquals(current.params, layer.params)) {
        final ok = await _engine.retune(
          layer.soundId,
          _sourceFor(layer, library),
          gain: layerGain(layer.volume),
          motion: motion,
        );
        if (ok) _applied[layer.soundId] = layer;
      } else if (current != layer) {
        _engine.setGain(layer.soundId, layerGain(layer.volume), motion: motion);
        _applied[layer.soundId] = layer;
      }
    }
    if (failed.isNotEmpty && ref.mounted) {
      state = state.copyWith(failed: {...state.failed, ...failed});
    }
    await Future.wait(fades);
  }

  Future<void> _holdKeepAlive(bool hold) async {
    if (hold == _held) return;
    _held = hold;
    if (hold) {
      final text = _notification;
      await _keepAlive.hold(
        title: text.title,
        text: text.text,
        stopLabel: text.stop,
      );
    } else {
      await _keepAlive.release();
    }
  }
}
