import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/player/audio_state_provider.dart';
import 'package:medito/services/audio/session_bell_preview.dart';

final pulsePreviewProvider = Provider<PulsePreview>((ref) {
  final preview = PulsePreview();
  ref.onDispose(preview.dispose);
  return preview;
});

/// Plays a pulse at a rate and a level until stopped, so the Rhythm sheet
/// can be heard while it is set: "so you can hear how it feels". Foreground
/// only; the session's own pulse is the native cue engine's, untouched.
///
/// It beats at the starting rate: a ramp is heard only in a session.
class PulsePreview {
  PulsePreview({AudioPlayer Function()? newPlayer})
    : _newPlayer = newPlayer ?? SessionBellPreview.newPlayer;

  final AudioPlayer Function() _newPlayer;
  AudioPlayer? _player;
  Timer? _beat;
  String _asset = '';
  double _bpm = 0;
  double _volume = -1;
  int _generation = 0;

  /// Beats [asset] at [bpm] and [volume]. A new rate starts the beat over;
  /// a new level or sound is heard from the next beat. An empty [asset]
  /// stops it.
  Future<void> set({
    required String asset,
    required double bpm,
    required double volume,
  }) async {
    if (asset.isEmpty || bpm <= 0) return stop();
    final generation = ++_generation;
    final player = _player ??= _newPlayer();
    if (asset != _asset) {
      await player.setAsset(asset);
      _asset = asset;
      if (generation != _generation) return;
    }
    if (volume != _volume) {
      _volume = volume;
      await player.setVolume(volume);
      if (generation != _generation) return;
    }
    if (_beat != null && bpm == _bpm) return;
    _bpm = bpm;
    _beat?.cancel();
    _beat = Timer.periodic(
      Duration(microseconds: (60e6 / bpm).round()),
      (_) => _hit(),
    );
    _hit();
  }

  void _hit() {
    final player = _player;
    if (player == null) return;
    unawaited(() async {
      try {
        await player.seek(Duration.zero);
        // Once a beat has played to its end the player still counts as
        // playing: the seek alone sounds it again.
        if (!player.playing) unawaited(player.play());
      } catch (_) {
        // A beat the platform drops is not worth surfacing.
      }
    }());
  }

  Future<void> stop() async {
    _generation++;
    _beat?.cancel();
    _beat = null;
    _bpm = 0;
    // Stopped, the player lets its sound go: the next beat loads it again.
    _asset = '';
    await _player?.stop();
  }

  Future<void> dispose() async {
    _generation++;
    _beat?.cancel();
    _beat = null;
    await _player?.dispose();
    _player = null;
  }
}

/// Plays the chosen pulse while [child] (the Rhythm sheet) is shown, live as
/// [settings] change, and stops when it goes or Off is chosen. A session
/// already playing has its own pulse: nothing is added over it.
class PulseAudition extends ConsumerStatefulWidget {
  const PulseAudition({super.key, required this.settings, required this.child});

  final CueSettings settings;
  final Widget child;

  @override
  ConsumerState<PulseAudition> createState() => _PulseAuditionState();
}

class _PulseAuditionState extends ConsumerState<PulseAudition> {
  late final PulsePreview _preview = ref.read(pulsePreviewProvider);

  @override
  void initState() {
    super.initState();
    _apply();
  }

  @override
  void didUpdateWidget(PulseAudition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _apply();
  }

  @override
  void dispose() {
    unawaited(_preview.stop().catchError((Object _) {}));
    super.dispose();
  }

  void _apply() {
    final s = widget.settings;
    final sessionPlaying = ref.read(audioStateProvider).isPlaying;
    unawaited(
      (sessionPlaying || s.pulseSound.isEmpty
              ? _preview.stop()
              : _preview.set(
                  asset: s.pulseSound,
                  bpm: s.pulseBpm.roundToDouble(),
                  volume: s.pulseVolume,
                ))
          .catchError((Object _) {}),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
