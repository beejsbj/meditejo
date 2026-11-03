import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/widgets/art/art_subject.dart';

import 'sound_labels.dart';
import 'sounds_view.dart';

/// The mixer as a chooser: what plays under sessions of [kind] (#66). The
/// Sounds tab is the same component at full screen, playing the Sounds
/// tab's own mix; this form edits a draft for those sessions instead.
@immutable
class SoundChooser {
  const SoundChooser(this.kind);

  final SoundscapeSessionKind kind;
}

/// Runs [open] unless a drawer is already opening or open: a second tap (a
/// double tap on the player's button, a tile tapped while the scope
/// resolves) opens nothing, and gets null.
Future<T?> _once<T>(BuildContext context, Future<T?> Function() open) async {
  final mixer = ProviderScope.containerOf(
    context,
  ).read(soundscapeProvider.notifier);
  if (!mixer.claimChooser()) return null;
  try {
    return await open();
  } finally {
    mixer.releaseChooser();
  }
}

/// Opens the mixer as a drawer to choose what plays under sessions of
/// [kind], starting from [current]. Choosing is editing the mix: a card or a
/// preset is heard as it goes in, and several layer up. What is left in the
/// drawer when it closes (Done, back, a swipe down) is the choice; it
/// returns it, or null when it is what [current] already played (or another
/// drawer was already opening).
///
/// The drawer holds the speaker while it is open. As it closes, whatever
/// played before comes back (the Sounds tab's mix, a session's sound),
/// except that a new choice made while a session of [kind] runs keeps
/// playing under it. [inSession]: opened from that running session (its
/// player, its Customize), so the drawer starts from what it plays.
///
/// A session that starts or ends while it is open (the sit ends, autoplay
/// moves on) owns the mixer: the drawer closes, keeps nothing, and says so.
Future<SoundscapeSelection?> showSoundDrawer(
  BuildContext context, {
  required SoundscapeSessionKind kind,
  required SoundscapeSelection current,
  bool inSession = false,
}) => _once(
  context,
  () => _showSoundDrawer(
    context,
    kind: kind,
    current: current,
    inSession: inSession,
  ),
);

Future<SoundscapeSelection?> _showSoundDrawer(
  BuildContext context, {
  required SoundscapeSessionKind kind,
  required SoundscapeSelection current,
  required bool inSession,
}) async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final mixer = container.read(soundscapeProvider.notifier);
  final now = container.read(soundscapeProvider);
  // From inside a session, what you hear is what you edit.
  final draft = inSession && now.underSession && now.sessionKind == kind
      ? now.mix
      : await mixer.resolveSelection(current);
  if (!context.mounted) return null;
  retryLegacySounds(container);
  mixer.beginAudition(kind, draft);
  SoundscapeSelection? selection;
  var overtaken = false;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Its own messenger: Clear's Undo (#67) belongs in the drawer, not
      // behind it on the page's Scaffold.
      builder: (_) => ScaffoldMessenger(
        child: FractionallySizedBox(
          heightFactor: 0.94,
          child: SoundsView(chooser: SoundChooser(kind)),
        ),
      ),
    );
  } finally {
    // A session that started or ended meanwhile owns the mixer: what plays
    // is no longer this drawer's draft, so nothing is kept from it.
    overtaken = !mixer.auditionIntact;
    final state = container.read(soundscapeProvider);
    final chosen = state.mix;
    final changed = !overtaken && chosen != draft;
    if (changed) selection = state.selectionFor(chosen);
    // Chosen while a session of this kind runs: it goes on playing (the
    // session then plays its own choice, which may be this one), rather
    // than the old sound coming back for a moment first.
    mixer.endAudition(
      keep: changed && state.inSession && state.sessionKind == kind,
    );
  }
  if (overtaken && l10n != null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.soundsChooserOvertaken)),
    );
  }
  return selection;
}

/// The mixer kind for a cue scope's kind.
SoundscapeSessionKind soundscapeKindFor(CueKind kind) =>
    kind == CueKind.practice
    ? SoundscapeSessionKind.practice
    : SoundscapeSessionKind.talks;

/// Keeps [choice] as what plays under [scope]'s sessions: in the scope's own
/// cue settings when it has its own ([courseOverride], "only for this
/// course"), otherwise as its kind's default in the mixer, the one the Sounds
/// tab's "Plays under" lines show. [inSession]: chosen from the running
/// session, which plays it now.
void chooseScopeSound(
  ProviderContainer container,
  CueScope scope,
  SoundscapeSelection choice, {
  required bool courseOverride,
  bool inSession = false,
}) {
  final settings = container.read(cueSettingsProvider(scope));
  final cues = container.read(cueSettingsProvider(scope).notifier);
  if (courseOverride) {
    unawaited(
      cues.update(
        settings.copyWith(soundscape: choice.encode()),
        courseOverride: true,
      ),
    );
    return;
  }
  container
      .read(soundscapeProvider.notifier)
      .setSessionChoice(
        soundscapeKindFor(scope.kind),
        choice,
        followNow: inSession,
      );
  // A kind-wide choice lives in the mixer only; clear any stored here.
  if (settings.soundscape.isNotEmpty) {
    unawaited(cues.update(settings.copyWith(soundscape: '')));
  }
}

/// The player's Sounds button: the drawer for the running session's scope,
/// the same choice as its Customize › Sound.
Future<void> openSessionSounds(BuildContext context, PlaybackRequest request) =>
    _once(context, () => _openSessionSounds(context, request));

Future<void> _openSessionSounds(
  BuildContext context,
  PlaybackRequest request,
) async {
  final container = ProviderScope.containerOf(context);
  final scope = await container.read(
    cueScopeForRequestProvider(request).future,
  );
  if (!context.mounted) return;
  final courseOverride = container
      .read(cueSettingsStoreProvider)
      .hasOverride(scope);
  final kind = soundscapeKindFor(scope.kind);
  final current = container
      .read(soundscapeProvider.notifier)
      .sessionChoice(
        kind,
        container.read(cueSettingsProvider(scope)).soundscapeSelection,
        library: container.read(soundLibraryProvider).value,
      );
  final choice = await _showSoundDrawer(
    context,
    kind: kind,
    current: current,
    inSession: true,
  );
  if (choice == null) return;
  chooseScopeSound(
    container,
    scope,
    choice,
    courseOverride: courseOverride,
    inSession: true,
  );
}

/// [choice] in a word or a line: Off, the current mix, a preset's name, a
/// sound's, or the sounds of a mix of its own.
String soundChoiceLabel(
  AppLocalizations l10n,
  SoundscapeState state,
  SoundLibrary library,
  SoundscapeSelection choice,
) {
  String sounds(SoundMix mix) {
    final titles = [
      for (final layer in mix.layers) ?soundTitle(l10n, layer.soundId, library),
    ];
    return titles.isEmpty
        ? l10n.soundsLayerCount(mix.layers.length)
        : titles.join(', ');
  }

  return switch (choice.kind) {
    SoundscapeSelectionKind.none => l10n.customizeOff,
    SoundscapeSelectionKind.mix => l10n.customizeCurrentMix,
    SoundscapeSelectionKind.preset => switch (state.presets
        .where((p) => p.id == choice.id)
        .firstOrNull) {
      final preset? => soundPresetLabel(l10n, preset),
      null => l10n.customizeCurrentMix,
    },
    SoundscapeSelectionKind.sound =>
      soundTitle(l10n, choice.id, library) ?? choice.id,
    SoundscapeSelectionKind.layers => switch (state.selectionFor(
      choice.mix ?? SoundMix.empty,
    )) {
      final s when s.kind == SoundscapeSelectionKind.preset => soundChoiceLabel(
        l10n,
        state,
        library,
        s,
      ),
      _ => sounds(choice.mix ?? SoundMix.empty),
    },
  };
}

/// [choice]'s art, as on the Sounds tab's cards; null when nothing plays.
ArtSubject? soundChoiceArt(SoundscapeState state, SoundscapeSelection choice) =>
    switch (choice.kind) {
      SoundscapeSelectionKind.none => null,
      SoundscapeSelectionKind.mix =>
        state.mix.isEmpty
            ? null
            : ArtSubject.layers(MixArt.current, state.mix.layers),
      SoundscapeSelectionKind.preset => switch (state.presets
          .where((p) => p.id == choice.id)
          .firstOrNull) {
        final p? => ArtSubject.layers(p.id, p.mix.layers),
        null => null,
      },
      SoundscapeSelectionKind.sound => ArtSubject.sound(choice.id),
      SoundscapeSelectionKind.layers => switch (choice.mix) {
        final mix? when !mix.isEmpty => ArtSubject.layers(
          MixArt.current,
          mix.layers,
        ),
        _ => null,
      },
    };
