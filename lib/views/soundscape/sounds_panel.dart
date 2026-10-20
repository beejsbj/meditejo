import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/widgets/filter_pill.dart';

import 'sound_credits_view.dart';

/// Localised names for the shelves of the library.
String soundCategoryLabel(AppLocalizations l10n, SoundCategory category) =>
    switch (category) {
      SoundCategory.rain => l10n.soundCategoryRain,
      SoundCategory.water => l10n.soundCategoryWater,
      SoundCategory.wind => l10n.soundCategoryWind,
      SoundCategory.forest => l10n.soundCategoryForest,
      SoundCategory.fire => l10n.soundCategoryFire,
      SoundCategory.room => l10n.soundCategoryRoom,
      SoundCategory.night => l10n.soundCategoryNight,
    };

/// Built-in presets carry English names in code; show them localised.
String soundPresetLabel(AppLocalizations l10n, SoundPreset preset) =>
    switch (preset.id) {
      'starter-rain-forest' => l10n.soundPresetRainForest,
      'starter-night' => l10n.soundPresetNight,
      'starter-hearth' => l10n.soundPresetHearth,
      'starter-shore' => l10n.soundPresetShore,
      _ => preset.name,
    };

TextStyle? _sectionStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    );

class SoundsSectionLabel extends StatelessWidget {
  const SoundsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(padding16, padding16, padding16, 6),
      child: Text(text.toUpperCase(), style: _sectionStyle(context)),
    ),
  );
}

/// Play/pause, Stop, what the mix is, and the master volume. Pinned above
/// the scrolling part of the Sounds sheet.
class SoundsTransport extends ConsumerWidget {
  const SoundsTransport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final state = ref.watch(soundscapeProvider);
    final controller = ref.read(soundscapeProvider.notifier);
    final preset = state.matchingPreset;
    final subtitle = state.mix.isEmpty
        ? l10n.soundsEmptyMix
        : preset != null
        ? soundPresetLabel(l10n, preset)
        : l10n.soundsLayerCount(state.mix.layers.length);
    return Padding(
      padding: const EdgeInsets.fromLTRB(padding16, 0, padding8, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filled(
                key: const ValueKey('sounds_play'),
                iconSize: 32,
                style: IconButton.styleFrom(
                  backgroundColor: context.brandAccent,
                  foregroundColor: context.onBrandAccent,
                ),
                tooltip: state.playing ? l10n.soundsPause : l10n.soundsPlay,
                onPressed: state.mix.isEmpty ? null : controller.togglePlay,
                icon: Icon(
                  state.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: padding12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.soundsYourMix,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (state.active)
                IconButton(
                  key: const ValueKey('sounds_stop'),
                  tooltip: l10n.soundsStop,
                  onPressed: controller.stop,
                  icon: const Icon(Icons.stop_rounded),
                ),
            ],
          ),
          Row(
            children: [
              Icon(
                Icons.volume_down_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('sounds_volume'),
                  value: state.volume,
                  activeColor: context.brandAccent,
                  semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                  onChanged: controller.setVolume,
                ),
              ),
              Icon(
                Icons.volume_up_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: padding8),
            ],
          ),
        ],
      ),
    );
  }
}

/// The layers of the current mix, each with its volume, drift and remove.
class SoundsMixLayers extends ConsumerWidget {
  const SoundsMixLayers({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(soundscapeProvider);
    final library = ref.watch(soundLibraryProvider).value ?? SoundLibrary.empty;
    final layers = [
      for (final l in state.mix.layers)
        if (library[l.soundId] case final entry?) (l, entry),
    ];
    if (layers.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final (layer, entry) in layers)
          _LayerRow(
            key: ValueKey('layer_${layer.soundId}'),
            layer: layer,
            entry: entry,
            failed: state.failed.contains(layer.soundId),
          ),
      ],
    );
  }
}

class _LayerRow extends ConsumerWidget {
  const _LayerRow({
    super.key,
    required this.layer,
    required this.entry,
    required this.failed,
  });

  final SoundLayer layer;
  final SoundEntry entry;
  final bool failed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(soundscapeProvider.notifier);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(padding16, 4, padding8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('drift_${layer.soundId}'),
                tooltip: l10n.soundsDriftHint,
                isSelected: layer.animate,
                onPressed: () =>
                    controller.setLayerAnimate(layer.soundId, !layer.animate),
                icon: Icon(Icons.waves_rounded, color: muted),
                selectedIcon: Icon(
                  Icons.waves_rounded,
                  color: context.brandAccent,
                ),
              ),
              IconButton(
                key: ValueKey('remove_${layer.soundId}'),
                tooltip: l10n.soundsRemove(entry.title),
                onPressed: () => controller.toggleSound(layer.soundId),
                icon: Icon(Icons.close_rounded, color: muted),
              ),
            ],
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.soundsCouldNotPlay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Slider(
            key: ValueKey('volume_${layer.soundId}'),
            value: layer.volume,
            activeColor: context.brandAccent,
            semanticFormatterCallback: (v) =>
                '${entry.title} ${(v * 100).round()}%',
            onChanged: (v) => controller.setLayerVolume(layer.soundId, v),
          ),
        ],
      ),
    );
  }
}

/// Starter and saved presets; Save mix keeps the current one.
class SoundsPresets extends ConsumerWidget {
  const SoundsPresets({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(soundscapeProvider);
    final controller = ref.read(soundscapeProvider.notifier);
    final current = state.matchingPreset;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: padding16),
      child: Wrap(
        spacing: padding8,
        runSpacing: padding8,
        children: [
          for (final preset in state.presets)
            GestureDetector(
              key: ValueKey('preset_${preset.id}'),
              onLongPress: preset.builtIn
                  ? null
                  : () => _confirmDelete(context, ref, preset),
              child: FilterPill(
                label: soundPresetLabel(l10n, preset),
                selected: current?.id == preset.id && state.active,
                onTap: () => controller.applyPreset(preset.id),
              ),
            ),
          if (!state.mix.isEmpty && current == null)
            ActionChip(
              key: const ValueKey('preset_save'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.soundsSavePreset),
              onPressed: () => _save(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _PresetNameDialog(),
    );
    if (name == null || name.trim().isEmpty) return;
    final saved = ref.read(soundscapeProvider.notifier).savePreset(name);
    if (saved != null && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(l10n.soundsPresetSaved(saved.name))),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SoundPreset preset,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.soundsDeletePreset(preset.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.soundsCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.soundsDelete),
          ),
        ],
      ),
    );
    if (delete == true) {
      ref.read(soundscapeProvider.notifier).deletePreset(preset.id);
    }
  }
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.soundsSavePreset),
      content: TextField(
        key: const ValueKey('preset_name'),
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: l10n.soundsPresetName),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.soundsCancel),
        ),
        TextButton(
          key: const ValueKey('preset_name_save'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l10n.soundsSave),
        ),
      ],
    );
  }
}

/// Whether the mix plays under Practice and under Talks (decision 8).
/// The player's Customize sheet will offer the full per-kind choice.
class SoundsSessionDefaults extends ConsumerWidget {
  const SoundsSessionDefaults({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(soundscapeProvider);
    final controller = ref.read(soundscapeProvider.notifier);
    Widget row(SoundscapeSessionKind kind, String label) {
      final value = state.sessionDefault(kind);
      return SwitchListTile(
        key: ValueKey('under_${kind.name}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: padding16),
        title: Text(label),
        value: value.enabled,
        onChanged: (on) =>
            controller.setSessionDefault(kind, value.copyWith(enabled: on)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(SoundscapeSessionKind.practice, l10n.soundsUnderPractice),
        row(SoundscapeSessionKind.talks, l10n.soundsUnderTalks),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: padding16),
          child: Text(
            l10n.soundsUnderSessionsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

/// The library, shelf by shelf. Tap a sound to layer it in or out.
class SoundsLibraryShelves extends ConsumerWidget {
  const SoundsLibraryShelves({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final library = ref.watch(soundLibraryProvider).value;
    if (library == null) {
      return const Padding(
        padding: EdgeInsets.all(padding24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final state = ref.watch(soundscapeProvider);
    final controller = ref.read(soundscapeProvider.notifier);
    final full = !controller.canAddLayer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (full)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              padding16,
              padding8,
              padding16,
              0,
            ),
            child: Text(
              l10n.soundsLayerLimit(SoundMix.kMaxLayers),
              style: _sectionStyle(context)?.copyWith(letterSpacing: 0),
            ),
          ),
        for (final category in library.categories) ...[
          SoundsSectionLabel(soundCategoryLabel(l10n, category)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: padding16),
            child: Wrap(
              spacing: padding8,
              runSpacing: padding8,
              children: [
                for (final sound in library.inCategory(category))
                  Opacity(
                    opacity: full && !state.mix.contains(sound.id) ? 0.4 : 1,
                    child: FilterPill(
                      key: ValueKey('sound_${sound.id}'),
                      label: sound.title,
                      selected: state.mix.contains(sound.id),
                      onTap: () => controller.toggleSound(sound.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class SoundsCreditsLink extends StatelessWidget {
  const SoundsCreditsLink({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(padding8, padding16, padding8, 0),
    child: TextButton.icon(
      key: const ValueKey('sound_credits'),
      icon: const Icon(Icons.info_outline_rounded, size: 18),
      label: Text(AppLocalizations.of(context)!.soundsCredits),
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SoundCreditsView())),
    ),
  );
}
