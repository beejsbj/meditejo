import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/presets/preset.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/soundscape/soundscape_store.dart';

/// Where a preset is being picked or saved. The place decides which slots
/// are in play there (#64): the Timer has all four; under a recording the
/// recording owns the length; the Sounds sheet has only the sound.
enum PresetPlace { timer, session, sounds }

@immutable
class PresetContext {
  /// The Timer's Customize sheet (and Home's preset tiles, which start it).
  const PresetContext.timer()
    : place = PresetPlace.timer,
      scope = const CueScope(CueKind.practice),
      courseOverride = false,
      inSession = false,
      chooserKind = null;

  /// Customize for a recording, or for a kind of session from Settings.
  /// [courseOverride]: the course keeps its own settings. [inSession]: the
  /// session is running, and plays what is chosen at once.
  const PresetContext.session(
    CueScope this.scope, {
    this.courseOverride = false,
    this.inSession = false,
  }) : place = PresetPlace.session,
       chooserKind = null;

  /// The Sounds sheet: on the user's own mix, or ([chooserKind]) on what
  /// plays under a kind of session.
  const PresetContext.sounds({this.chooserKind})
    : place = PresetPlace.sounds,
      scope = null,
      courseOverride = false,
      inSession = false;

  final PresetPlace place;
  final CueScope? scope;
  final bool courseOverride;
  final bool inSession;
  final SoundscapeSessionKind? chooserKind;

  /// The slots saved from here, and the ones a preset sets here.
  Set<PresetSlot> get offered => switch (place) {
    PresetPlace.timer => PresetSlot.values.toSet(),
    PresetPlace.session => const {
      PresetSlot.sound,
      PresetSlot.bells,
      PresetSlot.rhythm,
    },
    PresetPlace.sounds => const {PresetSlot.sound},
  };

  /// What the last preset loaded here is remembered under. The Timer and
  /// practice share their settings, so they share this too. Null where
  /// nothing is remembered (a session's sound in the Sounds sheet starts
  /// from that session's choice each time).
  String? get loadedKey => switch (place) {
    PresetPlace.sounds => chooserKind == null ? 'sounds' : null,
    _ =>
      courseOverride && scope!.courseId != null
          ? 'course.${scope!.courseId}'
          : scope!.kind.name,
  };

  @override
  bool operator ==(Object other) =>
      other is PresetContext &&
      other.place == place &&
      other.scope == scope &&
      other.courseOverride == courseOverride &&
      other.inSession == inSession &&
      other.chooserKind == chooserKind;

  @override
  int get hashCode =>
      Object.hash(place, scope, courseOverride, inSession, chooserKind);
}

SoundscapeSessionKind _mixerKind(CueKind kind) => kind == CueKind.practice
    ? SoundscapeSessionKind.practice
    : SoundscapeSessionKind.talks;

typedef _Read = T Function<T>(ProviderListenable<T> provider);

/// What plays under [scope]'s sessions with [settings], as layers.
SoundMix _scopeSound(_Read read, CueScope scope, CueSettings settings) {
  // Rebuilds with the mixer; its notifier does the resolving.
  read(soundscapeProvider);
  final mixer = read(soundscapeProvider.notifier);
  return mixer.selectionMix(
    mixer.sessionChoice(
      _mixerKind(scope.kind),
      settings.soundscapeSelection,
      library: read(soundLibraryProvider).value,
    ),
  );
}

PresetSlots _current(_Read read, PresetContext context) {
  if (context.place == PresetPlace.sounds) {
    return PresetSlots(sound: read(soundscapeProvider).mix);
  }
  final scope = context.scope!;
  final settings = read(cueSettingsProvider(scope));
  return PresetSlots(
    sound: _scopeSound(read, scope, settings),
    bells: PresetCues.bells(settings),
    rhythm: PresetCues.rhythm(settings),
    length: context.place != PresetPlace.timer
        ? null
        : read(timerSettingsProvider).mode == TimerMode.stopwatch
        ? const PresetLength.openEnded()
        : PresetLength.minutes(settings.durationMinutes),
  );
}

PresetSlots _defaults(_Read read, PresetContext context) {
  if (context.place == PresetPlace.sounds) {
    return const PresetSlots(sound: SoundMix.empty);
  }
  final scope = context.scope!;
  final kindScope = CueScope(scope.kind);
  // As Customize fills its tiles: a course's own settings are measured
  // against its kind's, a kind's against the app's.
  final reference = context.courseOverride
      ? read(cueSettingsProvider(kindScope))
      : CueSettings.defaults(scope.kind);
  return PresetSlots(
    sound: context.courseOverride
        ? _scopeSound(read, kindScope, reference)
        : SoundMix.empty,
    bells: PresetCues.bells(reference),
    rhythm: PresetCues.rhythm(reference),
    length: context.place == PresetPlace.timer
        ? const PresetLength.minutes(kDefaultTimerMinutes)
        : null,
  );
}

/// The four slots as they are set in [context] now (null where the place
/// has no such slot).
final currentPresetSlotsProvider = Provider.autoDispose
    .family<PresetSlots, PresetContext>(
      (ref, context) => _current(ref.watch, context),
    );

/// What [currentPresetSlotsProvider] is measured against: a slot that
/// differs from these is one the user set.
final defaultPresetSlotsProvider = Provider.autoDispose
    .family<PresetSlots, PresetContext>(
      (ref, context) => _defaults(ref.watch, context),
    );

/// The preset loaded in a place, and whether what is set there has moved
/// on from it.
@immutable
class LoadedPreset {
  const LoadedPreset(this.preset, {required this.edited});

  final Preset preset;
  final bool edited;

  @override
  bool operator ==(Object other) =>
      other is LoadedPreset && other.preset == preset && other.edited == edited;

  @override
  int get hashCode => Object.hash(preset, edited);
}

/// The preset last loaded in [PresetContext], if it still exists. In the
/// Sounds sheet a mix that is exactly a preset's sound counts as that
/// preset, loaded.
final loadedPresetProvider = Provider.autoDispose
    .family<LoadedPreset?, PresetContext>((ref, context) {
      final mixer = ref.watch(soundscapeProvider);
      final current = ref.watch(currentPresetSlotsProvider(context));
      final key = context.loadedKey;
      final id = key == null ? null : ref.watch(loadedPresetsProvider)[key];
      var preset = id == null ? null : mixer.preset(id);
      if (context.place == PresetPlace.sounds) {
        if (mixer.mix.isEmpty) return null;
        final matching = mixer.matchingPreset;
        if (matching != null) return LoadedPreset(matching, edited: false);
        if (preset != null && !preset.playsSound) preset = null;
      }
      if (preset == null) return null;
      final theirs = preset.slots.filled.intersection(context.offered);
      return LoadedPreset(
        preset,
        edited: current.differing(preset.slots, theirs).isNotEmpty,
      );
    });

/// Which preset was last loaded where, by [PresetContext.loadedKey].
final loadedPresetsProvider =
    NotifierProvider<LoadedPresetsNotifier, Map<String, String>>(
      LoadedPresetsNotifier.new,
    );

class LoadedPresetsNotifier extends Notifier<Map<String, String>> {
  SoundscapeStore get _store =>
      SoundscapeStore(ref.read(sharedPreferencesProvider));

  @override
  Map<String, String> build() {
    // An emptied mix came from nowhere: the next one built is not "from"
    // the preset that was there. (A session's sound being chosen empties
    // the mixer's draft, not the user's own mix.)
    ref.listen(soundscapeProvider.select((s) => s.mix.isEmpty), (_, empty) {
      if (empty && !ref.read(soundscapeProvider.notifier).auditioning) {
        clear('sounds');
      }
    });
    return _store.readLoadedPresets();
  }

  void load(String? key, String presetId) {
    if (key == null || state[key] == presetId) return;
    _set({...state, key: presetId});
  }

  void clear(String? key) {
    if (key == null || !state.containsKey(key)) return;
    _set({...state}..remove(key));
  }

  /// A deleted preset is loaded nowhere.
  void forget(String presetId) {
    if (!state.containsValue(presetId)) return;
    _set({
      for (final MapEntry(:key, :value) in state.entries)
        if (value != presetId) key: value,
    });
  }

  void _set(Map<String, String> next) {
    state = next;
    _store.writeLoadedPresets(next);
  }
}

/// The ids of the presets pinned to Home, oldest pin first. A preset is on
/// Home because it is pinned, exactly like a course or a session.
final pinnedPresetIdsProvider =
    NotifierProvider<PinnedPresetsNotifier, List<String>>(
      PinnedPresetsNotifier.new,
    );

class PinnedPresetsNotifier extends Notifier<List<String>> {
  /// How many preset tiles Home shows before "See all": two rows of two.
  static const homeLimit = 4;

  SoundscapeStore get _store =>
      SoundscapeStore(ref.read(sharedPreferencesProvider));

  @override
  List<String> build() => _store.readPinnedPresets();

  bool isPinned(String id) => state.contains(id);

  void pin(String id) {
    if (state.contains(id)) return;
    _set([...state, id]);
  }

  void unpin(String id) {
    if (!state.contains(id)) return;
    _set([
      for (final p in state)
        if (p != id) p,
    ]);
  }

  void setPinned(String id, bool pinned) => pinned ? pin(id) : unpin(id);

  /// Undo of [unpin]: back where it was among the pins in [before] that
  /// are still pinned, else last.
  void pinBack(String id, List<String> before) {
    if (state.contains(id)) return;
    final after = before.skip(before.indexOf(id) + 1);
    final at = state.indexWhere(after.contains);
    _set([...state]..insert(at < 0 ? state.length : at, id));
  }

  void _set(List<String> ids) {
    state = ids;
    _store.writePinnedPresets(ids);
  }
}

/// The pinned presets that still exist, in pin order.
final pinnedPresetsProvider = Provider<List<Preset>>((ref) {
  final ids = ref.watch(pinnedPresetIdsProvider);
  final mine = ref.watch(soundscapeProvider.select((s) => s.userPresets));
  final all = SoundscapeState(userPresets: mine);
  return [for (final id in ids) ?all.preset(id)];
});

/// Sets what [preset] holds, in [context]: its slots that are in play
/// there, leaving the rest as they are. Remembers it as the preset loaded
/// there.
Future<void> applyPreset(
  ProviderContainer container,
  PresetContext context,
  Preset preset,
) async {
  final slots = preset.slots.only(context.offered);
  final mixer = container.read(soundscapeProvider.notifier);
  if (context.place == PresetPlace.sounds) {
    if (preset.playsSound) mixer.applyPreset(preset.id);
  } else if (!slots.isEmpty) {
    final scope = context.scope!;
    var next = container.read(cueSettingsProvider(scope));
    if (slots.bells case final bells?) next = bells.applyTo(next);
    if (slots.rhythm case final rhythm?) next = rhythm.applyTo(next);
    if (slots.length case final length?) {
      container
          .read(timerSettingsProvider.notifier)
          .setMode(
            length.openEnded ? TimerMode.stopwatch : TimerMode.countdown,
          );
      if (length.minutes case final minutes?) {
        next = next.copyWith(durationMinutes: minutes);
      }
    }
    if (slots.sound != null) {
      // Its sound by name, so a later change to the preset is heard here.
      final choice = preset.playsSound
          ? SoundscapeSelection.preset(preset.id)
          : SoundscapeSelection.none;
      if (context.courseOverride) {
        next = next.copyWith(soundscape: choice.encode());
      } else {
        // A kind-wide choice lives in the mixer, as Customize keeps it.
        mixer.setSessionChoice(
          _mixerKind(scope.kind),
          choice,
          followNow: context.inSession,
        );
        next = next.copyWith(soundscape: '');
      }
    }
    await container
        .read(cueSettingsProvider(scope).notifier)
        .update(next, courseOverride: context.courseOverride);
  }
  container
      .read(loadedPresetsProvider.notifier)
      .load(context.loadedKey, preset.id);
}

/// Saves what is set in [context] as a new preset holding [ticked] (of the
/// slots offered there), and loads it there. Null when there is no name or
/// nothing ticked.
Preset? saveNewPreset(
  ProviderContainer container,
  PresetContext context, {
  required String name,
  required Set<PresetSlot> ticked,
  bool pin = false,
}) {
  final slots = _current(
    container.read,
    context,
  ).only(ticked.intersection(context.offered));
  final trimmed = name.trim();
  if (trimmed.isEmpty || slots.isEmpty) return null;
  final preset = Preset(
    id: SoundscapeController.newPresetId(),
    name: trimmed,
    slots: slots,
  );
  container.read(soundscapeProvider.notifier).putPreset(preset);
  container
      .read(loadedPresetsProvider.notifier)
      .load(context.loadedKey, preset.id);
  if (pin) container.read(pinnedPresetIdsProvider.notifier).pin(preset.id);
  return preset;
}

/// Writes [ticked] (of the slots offered in [context]) into [preset] from
/// what is set there now; every other slot it holds is kept (#68).
Preset updatePreset(
  ProviderContainer container,
  PresetContext context,
  Preset preset, {
  required Set<PresetSlot> ticked,
  bool? pin,
}) {
  final written = _current(
    container.read,
    context,
  ).only(ticked.intersection(context.offered));
  final updated = preset.copyWith(slots: preset.slots.withSlots(written));
  container.read(soundscapeProvider.notifier).putPreset(updated);
  container
      .read(loadedPresetsProvider.notifier)
      .load(context.loadedKey, preset.id);
  if (pin != null) {
    container.read(pinnedPresetIdsProvider.notifier).setPinned(preset.id, pin);
  }
  return updated;
}

/// Deletes one of the user's presets: unpinned, and loaded nowhere.
void deletePreset(ProviderContainer container, String presetId) {
  container.read(soundscapeProvider.notifier).deletePreset(presetId);
  container.read(pinnedPresetIdsProvider.notifier).unpin(presetId);
  container.read(loadedPresetsProvider.notifier).forget(presetId);
}
