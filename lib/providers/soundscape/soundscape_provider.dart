import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/soundscape/sound_library.dart';
import '../../models/soundscape/sound_mix.dart';
import '../../models/soundscape/starter_presets.dart';
import '../../services/soundscape/soundscape_engine.dart';
import '../../services/soundscape/soundscape_keep_alive.dart';
import '../../services/soundscape/soundscape_store.dart';
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

  /// A session is running ([sessionKind] is set), whether or not the mixer
  /// plays under it. Sounds added meanwhile join the session.
  bool get inSession => sessionKind != null;

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

  /// [selection] as it will play: a preset that was deleted, or a sound a
  /// later library dropped, means the current mix rather than silence.
  /// [library] null (still loading) takes sounds on trust.
  SoundscapeSelection playable(
    SoundscapeSelection selection,
    SoundLibrary? library,
  ) => switch (selection.kind) {
    SoundscapeSelectionKind.preset
        when !presets.any((p) => p.id == selection.id) =>
      SoundscapeSelection.currentMix,
    SoundscapeSelectionKind.sound
        when library != null && !library.contains(selection.id) =>
      SoundscapeSelection.currentMix,
    _ => selection,
  };

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

  /// Whether the session player is playing (followed while a session runs).
  bool _sessionPlaying = true;

  /// Bumped when a session starts or ends; a start that finds it changed
  /// after resolving its mix was overtaken and does nothing.
  int _sessionToken = 0;

  /// Paused for another app's transient audio (a call); resumed with it.
  bool _pausedByFocus = false;

  /// How long Sounds may sit paused on their own (after a manual pause, an
  /// unplug, a lost focus) before they stop and let go of the foreground
  /// service and its notification.
  @visibleForTesting
  static Duration pausedStandaloneTimeout = const Duration(minutes: 10);
  Timer? _idleTimer;
  AppLifecycleListener? _lifecycle;
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
    try {
      // Swiping the app away detaches the (cached) engine; Sounds playing on
      // their own must not carry on with no screen to stop them from.
      _lifecycle = AppLifecycleListener(onDetach: _onDetach);
    } on FlutterError {
      // No widgets binding (plain unit tests).
    }
    ref.onDispose(() {
      _idleTimer?.cancel();
      _lifecycle?.dispose();
      _commands?.cancel();
      if (_held) unawaited(_keepAlive.release());
      unawaited(_engine.stopAll(fade: Duration.zero));
    });
    // Under a session, follow the session player (pauses, phone calls).
    ref.listen(audioStateProvider.select((s) => s.isPlaying), (_, playing) {
      if (!state.inSession) return;
      _sessionPlaying = playing;
      if (state.underSession && state.playing != playing) {
        _update(state.copyWith(playing: playing));
      }
    });
    return SoundscapeState(
      mix: _currentMix(),
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
      mix.put(SoundLayer(soundId: soundId)),
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

  void clearMix() => _editMix(SoundMix.empty);

  /// Master volume. Under a session it is that session kind's level.
  void setVolume(double volume) {
    final kind = state.sessionKind;
    if (kind != null) {
      setSessionVolume(kind, volume);
    } else {
      final v = volume.clamp(0.0, 1.0);
      _store.writeVolume(v);
      _update(state.copyWith(volume: v));
    }
  }

  /// The level sounds play at under sessions of [kind] (the one volume for
  /// that kind, whoever sets it). Applies at once if such a session runs.
  void setSessionVolume(SoundscapeSessionKind kind, double volume) {
    final v = volume.clamp(0.0, 1.0);
    final defaults = {
      ...state.sessionDefaults,
      kind: state.sessionDefault(kind).copyWith(volume: v),
    };
    _store.writeSessionDefaults(defaults);
    _update(
      state.copyWith(
        volume: state.sessionKind == kind ? v : null,
        sessionDefaults: defaults,
      ),
    );
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
    _pausedByFocus = false;
    if (state.underSession) {
      _update(state.copyWith(playing: _sessionPlaying));
    } else if (state.active) {
      _update(state.copyWith(playing: true));
      // Another app may have taken focus for good meanwhile.
      if (_held) unawaited(_keepAlive.requestFocus());
    } else {
      _start();
    }
  }

  /// Stops the sounds (the Sounds screen's Stop; the notification's Stop).
  /// A running session stays a session: sounds added later join it.
  void stop() {
    _pausedByFocus = false;
    if (state.inSession) {
      _update(state.copyWith(playing: false, owner: SoundscapeOwner.none));
      return;
    }
    _update(
      state.copyWith(
        playing: false,
        owner: SoundscapeOwner.none,
        sessionKind: null,
        volume: _store.readVolume(),
      ),
    );
  }

  /// Plays [selection] now. Outside a session it plays on its own; under a
  /// session it replaces what the session plays.
  Future<void> play(SoundscapeSelection selection, {double? volume}) async {
    final inSession = state.inSession;
    final mix = await _resolve(selection, orCurrentMix: false);
    // The session ended while this resolved: do not start on its own.
    if (inSession && !state.inSession) return;
    if (mix.isEmpty) {
      if (state.underSession) {
        _update(state.copyWith(playing: false));
      } else {
        stop();
      }
      return;
    }
    _store.writeMix(mix);
    if (state.inSession) {
      _update(
        state.copyWith(
          mix: mix,
          playing: _sessionPlaying,
          owner: SoundscapeOwner.session,
          volume: volume ?? state.sessionDefault(state.sessionKind!).volume,
          failed: const {},
        ),
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
    // A kind that played the deleted preset plays the current mix instead
    // (and says so). A course's own choice resolves the same way on play.
    final deleted = SoundscapeSelection.preset(presetId);
    final defaults = {
      for (final MapEntry(:key, :value) in state.sessionDefaults.entries)
        key: value.selection == deleted
            ? value.copyWith(selection: SoundscapeSelection.currentMix)
            : value,
    };
    _store.writeSessionDefaults(defaults);
    _update(state.copyWith(userPresets: presets, sessionDefaults: defaults));
  }

  // ---------------------------------------------------------------------------
  // Sessions (decision 8): on for Practice, off for Talks by default.

  /// What a session plays: the kind's [kindDefault], unless the session's
  /// scope chose its own [selection] (`none` for silence).
  static SoundscapeSessionDefault sessionSetting(
    SoundscapeSessionDefault kindDefault,
    SoundscapeSelection? selection,
  ) => selection == null
      ? kindDefault
      : kindDefault.copyWith(
          enabled: selection.kind != SoundscapeSelectionKind.none,
          selection: selection.kind == SoundscapeSelectionKind.none
              ? kindDefault.selection
              : selection,
        );

  SoundscapeSessionDefault sessionDefault(SoundscapeSessionKind kind) =>
      state.sessionDefault(kind);

  void setSessionDefault(
    SoundscapeSessionKind kind,
    SoundscapeSessionDefault value,
  ) {
    final defaults = {...state.sessionDefaults, kind: value};
    _store.writeSessionDefaults(defaults);
    _update(state.copyWith(sessionDefaults: defaults));
    if (state.sessionKind == kind) {
      unawaited(startSession(kind, selection: _sessionSelection));
    }
  }

  /// The running session's own choice (a course's Customize selection),
  /// kept so a change to the kind's default does not override it.
  SoundscapeSelection? _sessionSelection;

  /// A session of [kind] is starting: play what its default says, at its
  /// volume. [selection] (the Customize sheet's choice for the session's
  /// scope) replaces the default's on/off and selection but not its volume;
  /// [override], for a caller that keeps its own setting, replaces all of it.
  /// Takes over anything playing on its own.
  Future<void> startSession(
    SoundscapeSessionKind kind, {
    SoundscapeSessionDefault? override,
    SoundscapeSelection? selection,
  }) async {
    final token = ++_sessionToken;
    _sessionSelection = selection;
    // Restarting within a running session (its setting changed) keeps the
    // player's play state; a new session starts as playing.
    if (state.sessionKind == null) _sessionPlaying = true;
    // Mark the session at once, so an endSession() while the mix resolves
    // is not lost.
    if (state.sessionKind != kind) {
      _update(state.copyWith(sessionKind: kind));
    }
    final setting =
        override ?? sessionSetting(state.sessionDefault(kind), selection);
    final mix = setting.enabled
        ? await _resolve(setting.selection)
        : SoundMix.empty;
    if (token != _sessionToken || state.sessionKind != kind) return;
    _pausedByFocus = false;
    if (mix.isEmpty) {
      _update(state.copyWith(playing: false, owner: SoundscapeOwner.none));
      return;
    }
    _update(
      state.copyWith(
        mix: mix,
        playing: _sessionPlaying,
        owner: SoundscapeOwner.session,
        // A level set while the mix resolved wins over the one read before.
        volume: override == null
            ? state.sessionDefault(kind).volume
            : setting.volume,
        failed: const {},
      ),
    );
  }

  /// The session player paused or resumed (iOS calls this; Android's state
  /// arrives through [audioStateProvider]).
  void setSessionPaused(bool paused) {
    if (!state.inSession) return;
    _sessionPlaying = !paused;
    if (state.underSession) _update(state.copyWith(playing: !paused));
  }

  /// The session is over: fade out and stop.
  void endSession() {
    if (!state.inSession) return;
    _sessionToken++;
    _sessionSelection = null;
    _update(
      state.copyWith(
        // A session may have played a preset or a single sound in place of
        // the current mix; the Sounds sheet gets the user's mix back.
        mix: _currentMix(),
        playing: false,
        owner: SoundscapeOwner.none,
        sessionKind: null,
        volume: _store.readVolume(),
      ),
    );
  }

  /// The user's current mix: the one last saved from the Sounds sheet (or
  /// played from it), never one a session chose for itself, which only
  /// lives in [state] while that session runs.
  SoundMix _currentMix() => _store.readMix() ?? kStarterPresets.first.mix;

  // ---------------------------------------------------------------------------

  /// [requested] as a mix. A stored default (a session) plays the current
  /// mix in place of a preset or sound that no longer exists; an explicit
  /// [play] of one plays nothing.
  Future<SoundMix> _resolve(
    SoundscapeSelection requested, {
    bool orCurrentMix = true,
  }) async {
    final library = await ref.read(soundLibraryProvider.future);
    final selection = orCurrentMix
        ? state.playable(requested, library)
        : requested;
    final SoundMix mix = switch (selection.kind) {
      SoundscapeSelectionKind.none => SoundMix.empty,
      SoundscapeSelectionKind.mix => switch (_currentMix()) {
        final current when current.isEmpty => kStarterPresets.first.mix,
        final current => current,
      },
      SoundscapeSelectionKind.preset =>
        state.presets.where((p) => p.id == selection.id).firstOrNull?.mix ??
            SoundMix.empty,
      SoundscapeSelectionKind.sound => SoundMix([
        SoundLayer(soundId: selection.id, volume: 0.8),
      ]),
    };
    return mix.where(library.contains);
  }

  void _editMix(SoundMix mix, {Set<String>? failed, bool start = false}) {
    _store.writeMix(mix);
    if (mix.isEmpty && state.active) {
      _update(state.copyWith(mix: mix, failed: failed));
      stop();
      return;
    }
    _update(state.copyWith(mix: mix, failed: failed));
    if (start && !state.active) _start();
  }

  /// Plays the current mix: under the running session if there is one,
  /// otherwise on its own.
  void _start({double? volume}) {
    final kind = state.sessionKind;
    if (kind == null) {
      _startStandalone(volume: volume);
      return;
    }
    _update(
      state.copyWith(
        playing: _sessionPlaying,
        owner: SoundscapeOwner.session,
        volume: volume ?? state.sessionDefault(kind).volume,
        failed: const {},
      ),
    );
  }

  void _startStandalone({double? volume}) {
    if (volume != null) _store.writeVolume(volume.clamp(0.0, 1.0));
    _update(
      state.copyWith(
        playing: true,
        owner: SoundscapeOwner.standalone,
        sessionKind: null,
        volume: _store.readVolume(),
        failed: const {},
      ),
    );
  }

  void _onCommand(SoundscapeCommand command) {
    if (state.owner != SoundscapeOwner.standalone) return;
    switch (command) {
      case SoundscapeCommand.stop:
        stop();
      case SoundscapeCommand.pause:
        // A call or a prompt: come back with it, but only if we were
        // playing (a paused mix stays paused).
        _pausedByFocus = _pausedByFocus || state.playing;
        pause();
      case SoundscapeCommand.lost:
      case SoundscapeCommand.noisy:
        // Another app took over playback, or the headphones came out: stay
        // paused (never resume on the speaker by itself).
        _pausedByFocus = false;
        pause();
      case SoundscapeCommand.resume:
        if (_pausedByFocus) {
          _pausedByFocus = false;
          _update(state.copyWith(playing: true));
        }
    }
  }

  void _onDetach() {
    if (state.owner == SoundscapeOwner.standalone) stop();
  }

  void _update(SoundscapeState next) {
    if (!ref.mounted) return;
    state = next;
    _syncIdleTimer();
    _sync = _sync.then((_) => _apply()).catchError((
      Object error,
      StackTrace s,
    ) {
      AppLogger.e('SOUNDSCAPE', 'Mixer sync failed', error, s);
    });
  }

  void _syncIdleTimer() {
    final idle = state.owner == SoundscapeOwner.standalone && !state.playing;
    if (!idle) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }
    _idleTimer ??= Timer(pausedStandaloneTimeout, () {
      _idleTimer = null;
      if (!ref.mounted) return;
      if (state.owner == SoundscapeOwner.standalone && !state.playing) stop();
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
          if (library.contains(l.soundId) && !s.failed.contains(l.soundId))
            l.soundId: l,
    };

    final standalone = s.owner == SoundscapeOwner.standalone && s.active;
    // Let go first when nothing should hold; take the service only once a
    // layer really plays (below), so a mix that cannot play never starts
    // it and then stops it before Android saw startForeground().
    if (!standalone) await _holdKeepAlive(false);

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
    var stale = false;
    for (final layer in desired.values) {
      // Loading is slow. If the user stopped or paused, or the mix or its
      // owner changed, meanwhile, leave the rest to the queued pass.
      if (!ref.mounted ||
          state.active != s.active ||
          state.playing != s.playing ||
          state.owner != s.owner ||
          state.mix != s.mix) {
        stale = true;
        break;
      }
      final motion = layer.animate ? LayerMotion.forSound(layer.soundId) : null;
      final current = _applied[layer.soundId];
      if (current == null) {
        final entry = library[layer.soundId]!;
        final ok = await _engine.start(
          layer.soundId,
          AssetLoopSource(entry.asset, channels: entry.channels),
          gain: layerGain(layer.volume),
          motion: motion,
        );
        if (ok) {
          _applied[layer.soundId] = layer;
          // As soon as the first layer plays, not after the last has loaded:
          // loading can outlast the few seconds Android allows to start a
          // foreground service once the screen is off.
          if (standalone) await _holdKeepAlive(true);
        } else {
          failed.add(layer.soundId);
        }
      } else if (current != layer) {
        _engine.setGain(layer.soundId, layerGain(layer.volume), motion: motion);
        _applied[layer.soundId] = layer;
      }
    }
    if (failed.isNotEmpty && ref.mounted) {
      state = state.copyWith(failed: {...state.failed, ...failed});
    }
    await Future.wait(fades);
    if (stale) return;
    if (standalone && _applied.isNotEmpty) await _holdKeepAlive(true);
    // Nothing in the mix could play (every layer failed, or none is in the
    // library): stop, rather than hold the foreground service and its
    // notification over silence. Only if the mix is still the one this
    // pass tried; a newer edit gets its own pass.
    if (ref.mounted &&
        s.active &&
        _applied.isEmpty &&
        state.active &&
        state.mix == s.mix) {
      stop();
    }
    // Silent and nothing loaded: close the output stream too.
    if (ref.mounted && !s.active && _applied.isEmpty && !state.active) {
      await _engine.shutdown();
    }
  }

  Future<void> _holdKeepAlive(bool hold) async {
    if (hold == _held) return;
    _held = hold;
    if (hold) {
      final text = _notification;
      final held = await _keepAlive.hold(
        title: text.title,
        text: text.text,
        stopLabel: text.stop,
      );
      // Refused (the app was not in the foreground): try again on the next
      // change rather than believe it held.
      if (!held) _held = false;
    } else {
      await _keepAlive.release();
    }
  }
}
