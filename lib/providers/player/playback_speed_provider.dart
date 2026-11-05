import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The playback speeds the player offers: the slower stops a guided sit may
/// want, and the faster ones a talk may want.
const playbackSpeedOptions = [0.6, 0.75, 0.9, 1.0, 1.25, 1.5, 1.75, 2.0];

/// The speed a session starts at when nothing is stored.
const defaultPlaybackSpeed = 1.0;

/// The speed each kind of session starts at, one value per kind, kept apart
/// from the cue settings: a talk may be listened to at 1.5× while a sit stays
/// at 1×, and changing one never changes the other. There is no per-course
/// value. Before this was stored every session started at 1×, so a missing
/// value reads as 1×.
class PlaybackSpeedStore {
  PlaybackSpeedStore(this.prefs);
  final SharedPreferences prefs;

  static String key(CueKind kind) => 'speed.v1.${kind.name}';

  double read(CueKind kind) => normalisePlaybackSpeed(prefs.get(key(kind)));

  Future<void> save(CueKind kind, double speed) =>
      prefs.setDouble(key(kind), normalisePlaybackSpeed(speed));
}

/// [value] as one of [playbackSpeedOptions]: the nearest stop for a number
/// in range, 1× for anything else, so a bad value never stops a session.
double normalisePlaybackSpeed(Object? value) {
  if (value is! num || !value.isFinite) return defaultPlaybackSpeed;
  final speed = value.toDouble();
  if (speed < playbackSpeedOptions.first - 0.05 ||
      speed > playbackSpeedOptions.last + 0.05) {
    return defaultPlaybackSpeed;
  }
  var best = defaultPlaybackSpeed;
  for (final option in playbackSpeedOptions) {
    if ((option - speed).abs() < (best - speed).abs()) best = option;
  }
  return best;
}

final playbackSpeedStoreProvider = Provider<PlaybackSpeedStore>(
  (ref) => PlaybackSpeedStore(ref.watch(sharedPreferencesProvider)),
);

/// The stored speed of one kind of session.
final playbackSpeedProvider =
    NotifierProvider.family<PlaybackSpeedNotifier, double, CueKind>(
      PlaybackSpeedNotifier.new,
    );

class PlaybackSpeedNotifier extends Notifier<double> {
  PlaybackSpeedNotifier(this.kind);
  final CueKind kind;

  @override
  double build() => ref.watch(playbackSpeedStoreProvider).read(kind);

  Future<void> set(double speed) async {
    state = normalisePlaybackSpeed(speed);
    await ref.read(playbackSpeedStoreProvider).save(kind, state);
  }
}

/// The one place a session's speed is decided. A timer is silence with no
/// recording to speed up, so it always runs at 1×; everything else starts at
/// its kind's speed. A file whose sections are marked practice or talk would
/// call this per section.
double sessionPlaybackSpeed(
  double Function(CueKind kind) speedOf, {
  required CueKind kind,
  required bool isTimer,
}) => isTimer ? defaultPlaybackSpeed : speedOf(kind);
