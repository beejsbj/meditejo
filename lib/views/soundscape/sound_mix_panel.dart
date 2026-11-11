import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/soundscape/synth.dart';
import 'package:medito/providers/presets/preset_providers.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/views/presets/preset_picker.dart';
import 'package:medito/views/presets/save_preset_sheet.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

import 'sound_control_spec.dart';
import 'sound_controls.dart';
import 'sounds_sheet.dart';
import 'sound_labels.dart';
import 'synth_editors.dart';

/// The level each muted layer had, to bring back on unmute. Muting sets the
/// layer's volume to 0 through the mixer's own API, so a mute is saved like
/// any level (a preset saved meanwhile keeps it silent); only this memory
/// of the old level is in-memory.
final layerUnmuteVolumesProvider =
    NotifierProvider<LayerUnmuteVolumes, Map<String, double>>(
      LayerUnmuteVolumes.new,
    );

class LayerUnmuteVolumes extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void remember(String soundId, double volume) =>
      state = {...state, soundId: volume};

  double? take(String soundId) {
    final volume = state[soundId];
    if (volume != null) state = {...state}..remove(soundId);
    return volume;
  }
}

/// Mutes [layer], or brings it back to the level it had.
void toggleLayerMute(WidgetRef ref, SoundLayer layer) {
  final mixer = ref.read(soundscapeProvider.notifier);
  final memory = ref.read(layerUnmuteVolumesProvider.notifier);
  if (layer.volume > 0) {
    memory.remember(layer.soundId, layer.volume);
    mixer.setLayerVolume(layer.soundId, 0);
  } else {
    mixer.setLayerVolume(
      layer.soundId,
      memory.take(layer.soundId) ?? SoundLayer.kDefaultLayerVolume,
    );
  }
}

/// What the mix is, in a line: a preset's name, or its sounds.
String mixSummary(
  AppLocalizations l10n,
  SoundscapeState state,
  SoundLibrary library,
) {
  if (state.mix.isEmpty) return l10n.soundsMixEmptyHint;
  final preset = state.matchingPreset;
  if (preset != null) return soundPresetLabel(l10n, preset);
  final titles = [
    for (final layer in state.mix.layers)
      ?soundTitle(l10n, layer.soundId, library),
  ];
  return titles.isEmpty
      ? l10n.soundsLayerCount(state.mix.layers.length)
      : titles.join(', ');
}

/// Play/pause the whole mix, whose it is and what it is, Stop or Clear, and
/// (in the dock) the button that opens or folds the panel.
class SoundsMixHeader extends ConsumerWidget {
  const SoundsMixHeader({
    super.key,
    this.expanded = false,
    this.onToggle,
    this.chooser,
  });

  final bool expanded;

  /// Opens or folds the dock; null where the panel is always open.
  final VoidCallback? onToggle;

  /// The mix is what plays under [SoundChooser.kind]'s sessions, and says
  /// so: the one line that tells the sheet on a session from the sheet on
  /// your own mix.
  final SoundChooser? chooser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final still = MediaQuery.disableAnimationsOf(context);
    final state = ref.watch(soundscapeProvider);
    final library = ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty;
    final controller = ref.read(soundscapeProvider.notifier);
    final chooser = this.chooser;
    // A mix that began as a preset and moved on says where it came from.
    final loaded = ref.watch(
      loadedPresetProvider(PresetContext.sounds(chooserKind: chooser?.kind)),
    );
    final summary = chooser != null && state.mix.isEmpty
        ? l10n.soundsChooserEmpty
        : loaded != null && loaded.edited
        ? presetFromLine(l10n, loaded)
        : mixSummary(l10n, state, library);
    const motion = MeditejoMotion.standardSpatial;
    return Row(
      children: [
        // The live mix card: the mix's art, following its two loudest
        // layers as they change, with play/pause on it.
        SizedBox.square(
          dimension: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MeditejoShapes.large),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (state.mix.isEmpty)
                  ColoredBox(color: scheme.surfaceContainerHighest)
                else
                  ArtCover(
                    key: const ValueKey('sounds_mix_art'),
                    subject: ArtSubject.layers(
                      state.matchingPreset?.id ?? MixArt.current,
                      state.mix.layers,
                    ),
                    live: state.playing,
                  ),
                Center(
                  child: IconButton.filled(
                    key: const ValueKey('sounds_play'),
                    iconSize: 24,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(40),
                      backgroundColor: scheme.primary.withValues(alpha: 0.92),
                      foregroundColor: scheme.onPrimary,
                      disabledBackgroundColor: scheme.onSurface.withValues(
                        alpha: 0.12,
                      ),
                      disabledForegroundColor: scheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
                    tooltip: state.playing ? l10n.soundsPause : l10n.soundsPlay,
                    onPressed: state.mix.isEmpty ? null : controller.togglePlay,
                    icon: Icon(
                      state.playing
                          ? Symbols.pause_rounded
                          : Symbols.play_arrow_rounded,
                      fill: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                switch (chooser?.kind) {
                  null => l10n.soundsYourMix,
                  SoundscapeSessionKind.practice =>
                    l10n.soundsPlaysUnderPractice,
                  SoundscapeSessionKind.talks => l10n.soundsPlaysUnderTalks,
                },
                // A session's longer title wraps rather than cut ("Läuft
                // bei Übungen" at 360 dp with large text).
                maxLines: chooser == null ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: type.emphasized.titleMedium,
              ),
              AnimatedSwitcher(
                duration: still ? Duration.zero : MeditejoMotion.short,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                child: Text(
                  summary,
                  key: ValueKey(summary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.baseline.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // On your own mix, while the panel is folded. Open, Clear takes its
        // place (and the art still pauses). For a session, Clear is the way
        // to silence: an empty mix is the choice Off.
        if (state.active && chooser == null && !expanded)
          IconButton(
            key: const ValueKey('sounds_stop'),
            tooltip: l10n.soundsStop,
            onPressed: controller.stop,
            icon: const Icon(Symbols.stop_rounded, fill: 1),
          ),
        // Clear takes the whole mix off the deck; Undo in the snackbar puts
        // it back. Only where the panel is open (the dock's chevron stays),
        // except on a session's sound, where an empty mix is the choice Off.
        if ((expanded || onToggle == null || chooser != null) &&
            !state.mix.isEmpty)
          // Words where they fit; at large text an icon, so the title
          // keeps its line.
          if (MediaQuery.textScalerOf(context).scale(1) > 1.3)
            IconButton(
              key: const ValueKey('sounds_clear'),
              tooltip: l10n.soundsClear,
              onPressed: () => _clear(context, ref),
              icon: const Icon(Symbols.playlist_remove_rounded),
            )
          else
            TextButton(
              key: const ValueKey('sounds_clear'),
              onPressed: () => _clear(context, ref),
              child: Text(l10n.soundsClear),
            ),
        // An empty mix has nothing to open: its line says how to start.
        if (onToggle != null && (expanded || !state.mix.isEmpty))
          IconButton(
            key: const ValueKey('sounds_mix_toggle'),
            tooltip: expanded ? l10n.soundsHideMix : l10n.soundsShowMix,
            onPressed: onToggle,
            icon: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: still ? Duration.zero : motion.duration,
              curve: motion.curve,
              child: const Icon(Symbols.keyboard_arrow_up_rounded),
            ),
          ),
      ],
    );
  }
}

/// The height of the mix's docked bar, for what is drawn under it: a
/// snackbar shown from the mix sits above the bar instead of over it. Absent
/// where the mix is a pane beside the library.
class SoundsDockBar extends InheritedWidget {
  const SoundsDockBar({super.key, required this.height, required super.child});

  /// From the Scaffold's foot to the bar's top edge.
  final double height;

  @override
  bool updateShouldNotify(SoundsDockBar old) => height != old.height;
}

/// Shows [content] as a snackbar from the mix, replacing the one showing. It
/// floats clear of the docked bar where there is one (an emptied mix folds
/// the dock to its bar, and a snackbar at the foot would cover it).
void _showMixSnackBar(
  BuildContext context,
  Widget content, {
  SnackBarAction? action,
}) {
  final bar = context.getInheritedWidgetOfExactType<SoundsDockBar>()?.height;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: content,
        // An action keeps a SnackBar up until dismissed; Undo is for the
        // moment after Clear, so let it time out.
        persist: false,
        // A quiet lift: it floats over the library's cards.
        elevation: 2,
        action: action,
        behavior: bar == null ? null : SnackBarBehavior.floating,
        margin: bar == null ? null : EdgeInsets.fromLTRB(16, 0, 16, bar + 8),
      ),
    );
}

/// Empties the mix and offers Undo, which restores it exactly (and plays it
/// again if it was playing).
void _clear(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context)!;
  final controller = ref.read(soundscapeProvider.notifier);
  final before = ref.read(soundscapeProvider);
  controller.clearMix();
  // A paused mix is loaded but not playing; Undo brings it back paused.
  final wasPaused =
      before.owner == SoundscapeOwner.standalone && !before.playing;
  _showMixSnackBar(
    context,
    Text(l10n.soundsMixCleared),
    action: SnackBarAction(
      label: l10n.undo,
      onPressed: () => controller.restoreMix(
        before.mix,
        play: before.playing || wasPaused,
        paused: wasPaused,
      ),
    ),
  );
}

/// The open panel under the header: the mix's volume, its layers (each
/// with volume, mute, swell, settings for a generated one, and remove) and
/// Save mix. Scrolls with [controller].
class SoundsMixBody extends ConsumerWidget {
  const SoundsMixBody({super.key, this.controller, this.padding, this.chooser});

  /// As [SoundsMixHeader.chooser]: whose mix this is.
  final SoundChooser? chooser;

  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final state = ref.watch(soundscapeProvider);
    final mixer = ref.read(soundscapeProvider.notifier);
    return ListView(
      controller: controller,
      padding: padding,
      children: [
        Semantics(
          label: l10n.soundsMixVolume,
          child: Row(
            children: [
              Icon(Symbols.volume_down_rounded, color: scheme.onSurfaceVariant),
              Expanded(
                child: Slider(
                  key: const ValueKey('sounds_volume'),
                  value: state.volume,
                  semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  onChanged: mixer.setVolume,
                ),
              ),
              Icon(Symbols.volume_up_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (state.mix.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Column(
              children: [
                Icon(
                  Symbols.graphic_eq_rounded,
                  size: 40,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.soundsMixEmptyTitle,
                  textAlign: TextAlign.center,
                  style: type.emphasized.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.soundsMixEmptyHint,
                  textAlign: TextAlign.center,
                  style: type.baseline.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const AnimatedMixLayers(),
        if (!state.mix.isEmpty && !mixer.canAddLayer)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.soundsLayerLimit(SoundMix.kMaxLayers),
              style: type.baseline.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        if (!state.mix.isEmpty && state.matchingPreset == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              key: const ValueKey('mix_save'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => saveMixAsPreset(
                context,
                PresetContext.sounds(chooserKind: chooser?.kind),
              ),
              icon: const Icon(Symbols.bookmark_add_rounded),
              label: Text(l10n.soundsSavePreset),
            ),
          ),
      ],
    );
  }
}

/// The layers of the mix, each growing in or folding away (Expressive's
/// spatial spring for size, its effects spring for opacity) as it is added
/// or removed, wherever that happened.
class AnimatedMixLayers extends ConsumerStatefulWidget {
  const AnimatedMixLayers({super.key});

  @override
  ConsumerState<AnimatedMixLayers> createState() => _AnimatedMixLayersState();
}

class _AnimatedMixLayersState extends ConsumerState<AnimatedMixLayers> {
  var _list = GlobalKey<AnimatedListState>();

  /// The ids the list shows, in order: the mix's layers this build can name.
  late List<String> _ids;

  /// The last known layer and title of each id, to draw one folding away.
  final _last = <String, (SoundLayer, String)>{};

  List<String> _shown(SoundscapeState state, SoundLibrary? library) => [
    for (final layer in state.mix.layers)
      if (isSynthId(layer.soundId) ||
          (library?.contains(layer.soundId) ?? false))
        layer.soundId,
  ];

  @override
  void initState() {
    super.initState();
    _ids = _shown(
      ref.read(soundscapeProvider),
      ref.read(soundLibraryProvider).value,
    );
  }

  Duration _duration(MotionToken token) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : token.duration;

  void _sync(List<String> next) {
    final list = _list.currentState;
    if (list == null) {
      _ids = next;
      return;
    }
    const size = MeditejoMotion.standardSpatial;
    for (var i = _ids.length - 1; i >= 0; i--) {
      final id = _ids[i];
      if (next.contains(id)) continue;
      final last = _last[id];
      _ids.removeAt(i);
      list.removeItem(
        i,
        (context, animation) => last == null
            ? const SizedBox.shrink()
            : _transition(
                animation,
                _LayerTile(layer: last.$1, title: last.$2, failed: false),
              ),
        duration: _duration(size),
      );
    }
    for (var i = 0; i < next.length; i++) {
      if (i < _ids.length && _ids[i] == next[i]) continue;
      if (_ids.contains(next[i])) {
        // Moved (not something the mixer does today): start the list
        // afresh rather than animate a reorder.
        setState(() {
          _ids = [...next];
          _list = GlobalKey<AnimatedListState>();
        });
        return;
      }
      _ids.insert(i, next[i]);
      list.insertItem(i, duration: _duration(size));
    }
  }

  Widget _transition(Animation<double> animation, Widget child) {
    const size = MeditejoMotion.standardSpatial;
    const fade = MeditejoMotion.effects;
    return SizeTransition(
      sizeFactor: CurvedAnimation(parent: animation, curve: size.curve),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: fade.curve),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(soundscapeProvider);
    final library = ref.watch(soundLibraryProvider).value;
    final next = _shown(state, library);
    if (!_sameIds(next, _ids)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync(_shown(ref.read(soundscapeProvider), library));
      });
    }
    return AnimatedList(
      key: _list,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _ids.length,
      itemBuilder: (context, index, animation) {
        final id = _ids[index];
        final layer = state.mix.layer(id) ?? _last[id]?.$1;
        if (layer == null) return const SizedBox.shrink();
        final title = soundTitle(l10n, id, library ?? SoundLibrary.empty) ?? id;
        _last[id] = (layer, title);
        return _transition(
          animation,
          _LayerTile(
            key: ValueKey('layer_$id'),
            layer: layer,
            title: title,
            failed: state.failed.contains(id),
          ),
        );
      },
    );
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _LayerTile extends ConsumerWidget {
  const _LayerTile({
    super.key,
    required this.layer,
    required this.title,
    required this.failed,
  });

  final SoundLayer layer;
  final String title;
  final bool failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final type = context.typography;
    final mixer = ref.read(soundscapeProvider.notifier);
    final id = layer.soundId;
    // Every layer: volume and Swell; a generated one adds Adjust (#71).
    final spec = soundControlSpec(id);
    final muted = layer.volume == 0;
    final playing = ref.watch(soundscapeProvider.select((s) => s.playing));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: MeditejoShapes.rounded(MeditejoShapes.largeIncreased),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        MeditejoShapes.medium,
                      ),
                      child: ArtCover(
                        subject: ArtSubject.sound(id, layer.params),
                        live: playing && !muted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: type.emphasized.titleMedium),
                        if (failed)
                          Text(
                            l10n.soundsCouldNotPlay,
                            style: type.baseline.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('mute_$id'),
                    tooltip: muted
                        ? l10n.soundsUnmute(title)
                        : l10n.soundsMute(title),
                    isSelected: muted,
                    onPressed: () => toggleLayerMute(ref, layer),
                    icon: const Icon(Symbols.volume_up_rounded),
                    selectedIcon: const Icon(Symbols.volume_off_rounded),
                  ),
                  IconButton(
                    key: ValueKey('remove_$id'),
                    tooltip: l10n.soundsRemove(title),
                    onPressed: () {
                      ref.read(layerUnmuteVolumesProvider.notifier).take(id);
                      mixer.toggleSound(id);
                    },
                    icon: const Icon(Symbols.close_rounded),
                  ),
                ],
              ),
              Slider(
                key: ValueKey('volume_$id'),
                value: layer.volume,
                semanticFormatterCallback: (v) =>
                    '$title ${(v * 100).round()}%',
                onChanged: (v) {
                  ref.read(layerUnmuteVolumesProvider.notifier).take(id);
                  mixer.setLayerVolume(id, v);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SwellToggle(
                      chipKey: ValueKey('swell_$id'),
                      selected: layer.animate,
                      onChanged: (on) => mixer.setLayerAnimate(id, on),
                    ),
                    if (spec.adjustable)
                      ActionChip(
                        key: ValueKey('adjust_$id'),
                        tooltip: l10n.synthAdjust(title),
                        avatar: const Icon(Symbols.tune_rounded),
                        label: Text(l10n.soundsAdjust),
                        onPressed: () => showSynthEditor(context, id),
                      ),
                  ],
                ),
              ),
              if (spec.headphones) const BinauralHeadphonesNote(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the save sheet on the mix (the Sound slot is all the Sounds
/// sheet saves) and says what was saved.
Future<void> saveMixAsPreset(BuildContext context, PresetContext place) async {
  final l10n = AppLocalizations.of(context)!;
  final saved = await showSavePresetSheet(context, place);
  // The sheet may have closed under it (a session took the mixer).
  if (saved == null || !context.mounted) return;
  _showMixSnackBar(
    context,
    Text(
      saved.updated
          ? l10n.presetUpdated(saved.preset.name)
          : l10n.soundsPresetSaved(saved.preset.name),
    ),
  );
}
