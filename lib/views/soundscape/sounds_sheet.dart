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

/// What the mix in the Sounds sheet is for, when it is not the user's own:
/// what plays under sessions of [kind] (#66).
@immutable
class SoundChooser {
  const SoundChooser(this.kind);

  final SoundscapeSessionKind kind;
}

/// What the open Sounds sheet is editing. There is one sheet
/// ([showSoundsSheet], [showSoundsSheetFor], [openSessionSounds]): on its own
/// it holds the user's mix, which plays by itself and goes on after the
/// sheet closes; for a session, or a kind of session, it holds a draft of
/// what plays under it, heard as it is made and kept as the sheet closes.
///
/// The sheet opened on the user's mix can turn to a kind's default in place
/// (its "Plays under" rows, [chooseDefault]) and come [back].
class SoundsSheetSession extends ChangeNotifier {
  SoundsSheetSession(this._container);

  final ProviderContainer _container;
  SoundscapeSessionKind? _kind;
  SoundMix? _draft;
  bool _scoped = false;
  bool _turning = false;

  SoundscapeController get _mixer =>
      _container.read(soundscapeProvider.notifier);

  /// The sessions the mix on screen plays under; null for the user's own
  /// mix.
  SoundscapeSessionKind? get kind => _kind;

  /// Turned to a kind's default from the user's own mix: [back] returns.
  bool get canGoBack => _kind != null && !_scoped;

  /// Starts choosing what plays under sessions of [kind] from [current].
  /// [inSession]: opened from that running session, so it starts from what
  /// it plays. [scoped]: the sheet was opened for this and nothing else.
  /// False when [stillWanted] says no once [current] has resolved.
  Future<bool> _begin(
    SoundscapeSessionKind kind,
    SoundscapeSelection current, {
    bool inSession = false,
    bool scoped = false,
    bool Function()? stillWanted,
  }) async {
    final now = _container.read(soundscapeProvider);
    // From inside a session, what you hear is what you edit.
    final draft = inSession && now.underSession && now.sessionKind == kind
        ? now.mix
        : await _mixer.resolveSelection(current);
    if (stillWanted != null && !stillWanted()) return false;
    _mixer.beginAudition(kind, draft);
    _kind = kind;
    _draft = draft;
    _scoped = scoped;
    notifyListeners();
    return true;
  }

  /// Ends the choosing. The choice is what is left in the mix, or null when
  /// that is what it started from, or when a session that started or ended
  /// meanwhile took the mixer ([overtaken]): then nothing is kept.
  ///
  /// As it ends, whatever played before comes back (the user's own mix, a
  /// session's sound), except that a new choice keeps playing under a
  /// running session of the kind when [playsNow].
  ({SoundscapeSelection? selection, bool overtaken}) _end({
    bool playsNow = true,
  }) {
    final kind = _kind;
    final draft = _draft;
    if (kind == null || draft == null) {
      return (selection: null, overtaken: false);
    }
    _kind = null;
    _draft = null;
    _scoped = false;
    final mixer = _mixer;
    final overtaken = !mixer.auditionIntact;
    final state = _container.read(soundscapeProvider);
    final chosen = state.mix;
    final changed = !overtaken && chosen != draft;
    final selection = changed ? state.selectionFor(chosen) : null;
    // Chosen for a session of this kind that is running and will play it:
    // it goes on playing (the session then plays its own choice, which may
    // be this one), rather than the old sound coming back for a moment.
    mixer.endAudition(
      keep: changed && playsNow && state.inSession && state.sessionKind == kind,
    );
    return (selection: selection, overtaken: overtaken);
  }

  /// Turns the sheet from the user's mix to what plays under sessions of
  /// [kind] by default: no course's choice is in play here.
  Future<void> chooseDefault(SoundscapeSessionKind kind) async {
    if (_kind != null || _turning) return;
    _turning = true;
    try {
      await _begin(
        kind,
        _mixer.sessionChoice(
          kind,
          null,
          library: _container.read(soundLibraryProvider).value,
        ),
      );
    } finally {
      _turning = false;
    }
  }

  /// Keeps what was chosen for the kind and returns to the user's own mix,
  /// playing or silent as it was. Also what closing the sheet does.
  /// True when a session overtook the choosing.
  bool back() {
    final kind = _kind;
    if (kind == null || _scoped) return false;
    final (:selection, :overtaken) = _end();
    if (selection != null) _mixer.setSessionChoice(kind, selection);
    notifyListeners();
    return overtaken;
  }
}

/// Runs [open] unless a Sounds sheet is already opening or open: a second
/// tap (a double tap on the player's button, a tile tapped while the scope
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

/// The one Sounds sheet, on [session].
Future<void> _sheet(BuildContext context, SoundsSheetSession session) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      // Its own messenger: Clear's Undo (#67) belongs in the sheet, not
      // behind it on the page's Scaffold.
      builder: (_) => ScaffoldMessenger(
        child: FractionallySizedBox(
          heightFactor: 0.94,
          child: SoundsView(session: session),
        ),
      ),
    );

/// Opens Sounds on the user's own mix, over whatever is open (Home's Sounds
/// tile, a `meditejo://sounds` link): presets, every sound and its editor,
/// the mix, and what plays under practice and talks. What is started here
/// plays on its own and goes on, with its notification, after the sheet
/// closes.
///
/// A session that starts or ends under it closes it.
Future<void> showSoundsSheet(BuildContext context) => _once(context, () async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  retryLegacySounds(container);
  final session = SoundsSheetSession(container);
  var overtaken = false;
  try {
    await _sheet(context, session);
  } finally {
    // Closed while turned to a kind's default: that choice is kept.
    overtaken = session.back();
    session.dispose();
  }
  if (overtaken && l10n != null) {
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.soundsChooserOvertaken)),
    );
  }
});

/// Opens the Sounds sheet to choose what plays under sessions of [kind],
/// starting from [current]. Choosing is editing the mix: a card or a preset
/// is heard as it goes in, and several layer up. What is left in the sheet
/// when it closes (Done, back, a swipe down) is the choice; it returns it,
/// or null when it is what [current] already played (or another Sounds
/// sheet was already opening).
///
/// The sheet holds the speaker while it is open. As it closes, whatever
/// played before comes back (the user's own mix, a session's sound),
/// except that a new choice keeps playing under a running session of
/// [kind] when [playsNow]: the caller's choice is what that session plays
/// (its player, its Customize, the kind's default). A course's own choice
/// made from another course's page is not, and the sit's sound comes back.
/// [inSession]: opened from that running session, so the sheet starts from
/// what it plays.
///
/// A session that starts or ends while it is open (autoplay moves on, a
/// sit starts or ends) owns the mixer: the sheet closes and keeps nothing.
/// [announce] says so in a snackbar on [context]'s messenger, except when
/// the sheet was opened in the session that has simply ended; a caller
/// whose messenger is hidden (under the Customize sheet) passes false.
Future<SoundscapeSelection?> showSoundsSheetFor(
  BuildContext context, {
  required SoundscapeSessionKind kind,
  required SoundscapeSelection current,
  bool inSession = false,
  bool playsNow = true,
  bool announce = true,
}) => _once(
  context,
  () => _showSoundsSheetFor(
    context,
    kind: kind,
    current: current,
    inSession: inSession,
    playsNow: playsNow,
    announce: announce,
  ),
);

Future<SoundscapeSelection?> _showSoundsSheetFor(
  BuildContext context, {
  required SoundscapeSessionKind kind,
  required SoundscapeSelection current,
  required bool inSession,
  bool playsNow = true,
  bool announce = true,
}) async {
  final container = ProviderScope.containerOf(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  final session = SoundsSheetSession(container);
  final began = await session._begin(
    kind,
    current,
    inSession: inSession,
    scoped: true,
    stillWanted: () => context.mounted,
  );
  if (!began || !context.mounted) {
    session.dispose();
    return null;
  }
  retryLegacySounds(container);
  SoundscapeSelection? selection;
  var overtaken = false;
  try {
    await _sheet(context, session);
  } finally {
    (:selection, :overtaken) = session._end(playsNow: playsNow);
    session.dispose();
    // Opened in a sit that has since ended: the end screen says enough.
    if (inSession && !container.read(soundscapeProvider).inSession) {
      announce = false;
    }
  }
  if (overtaken && announce && l10n != null) {
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
/// sheet's "Plays under" lines show. [inSession]: chosen from the running
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

/// The player's Sounds button: the Sounds sheet on the running session's scope,
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
  final choice = await _showSoundsSheetFor(
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

/// [choice]'s art, as on the Sounds sheet's cards; null when nothing plays.
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
