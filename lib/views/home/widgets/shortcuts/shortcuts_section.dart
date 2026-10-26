import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/home/home_presets_provider.dart';
import 'package:medito/providers/main_tab_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/library/import_view.dart';
import 'package:medito/views/timer/start_timer.dart';
import 'package:medito/views/timer/timer_format.dart';
import 'package:medito/views/timer/timer_view.dart';
import 'package:medito/widgets/medito_icon.dart';

/// One-tap starts, as a grid of tiles: the Timer, Sounds, a few sound
/// presets that start the Timer with that background, and Add.
class ShortcutsSection extends ConsumerWidget {
  const ShortcutsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final presets = ref.watch(homeSoundPresetsProvider);
    final stopwatch =
        ref.watch(timerSettingsProvider.select((s) => s.mode)) ==
        TimerMode.stopwatch;
    final minutes = ref.watch(
      cueSettingsProvider(timerCueScope).select((s) => s.durationMinutes),
    );
    final timerLength = stopwatch
        ? l10n.timerModeStopwatch
        : formatTimerLength(Duration(minutes: minutes), l10n);

    final tiles = <Widget>[
      ShortcutTile(
        key: const ValueKey('shortcut_timer'),
        color: scheme.secondaryContainer,
        onColor: scheme.onSecondaryContainer,
        icon: (color) =>
            MeditoIcon(assetName: MeditoIcons.timer, color: color, size: 24),
        label: l10n.timerTitle,
        caption: timerLength,
        onTap: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const TimerView())),
      ),
      ShortcutTile(
        key: const ValueKey('shortcut_sounds'),
        color: scheme.surfaceContainerHigh,
        onColor: scheme.onSurface,
        // The Sounds tab's own symbol.
        icon: (color) =>
            Icon(Symbols.graphic_eq_rounded, color: color, size: 24),
        label: l10n.backgroundSoundsSection,
        onTap: () => ref.read(mainTabProvider.notifier).select(MainTab.sounds),
      ),
      for (final preset in presets)
        ShortcutTile(
          key: ValueKey('shortcut_preset_${preset.id}'),
          color: scheme.tertiaryContainer,
          onColor: scheme.onTertiaryContainer,
          icon: (color) => Icon(Icons.waves_rounded, color: color, size: 24),
          label: preset.name,
          caption: '${l10n.timerTitle} · $timerLength',
          semanticsLabel: l10n.homeShortcutPresetTimer(preset.name),
          starts: true,
          onTap: () => startTimerSession(
            context,
            ref,
            soundscape: SoundscapeSelection.preset(preset.id),
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionHeader(l10n.homeShortcutsTitle),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kHomeGutter),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Two columns on a phone, more where there is room.
              final columns = (constraints.maxWidth / 220).floor().clamp(2, 4);
              final width =
                  (constraints.maxWidth - kHomeGap * (columns - 1)) / columns;
              // Padding and icon row stay fixed; the two text lines grow
              // with the user's text size, so the tile does too.
              final height = 56 + MediaQuery.textScalerOf(context).scale(44);
              return Wrap(
                spacing: kHomeGap,
                runSpacing: kHomeGap,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      height: height < 116 ? 116 : height,
                      child: tile,
                    ),
                  SizedBox(
                    width: constraints.maxWidth,
                    child: _AddTile(onTap: () => openImport(context, ref)),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A rounded tile: an icon at the top, its label and a caption at the foot,
/// and a play mark when tapping it starts something at once ([starts]).
class ShortcutTile extends StatelessWidget {
  const ShortcutTile({
    super.key,
    required this.color,
    required this.onColor,
    required this.icon,
    required this.label,
    required this.onTap,
    this.caption,
    this.semanticsLabel,
    this.starts = false,
  });

  final Color color;
  final Color onColor;
  final Widget Function(Color color) icon;
  final String label;
  final String? caption;
  final String? semanticsLabel;
  final bool starts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final muted = onColor.withValues(alpha: 0.78);
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: HomePressable(
        color: color,
        radius: kHomeTileRadius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  icon(onColor),
                  const Spacer(),
                  if (starts)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: onColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: onColor,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.emphasized.titleMedium?.copyWith(color: onColor),
              ),
              // An empty caption still takes its line, so labels align.
              Text(
                caption ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.baseline.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add, as a quiet full-width row under the tiles.
class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.homeShortcutAdd,
      excludeSemantics: true,
      onTap: onTap,
      child: HomePressable(
        key: const ValueKey('shortcut_add'),
        color: scheme.surfaceContainer,
        radius: MeditejoShapes.full,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.add_rounded, color: scheme.onSurface),
              const SizedBox(width: 12),
              Text(
                l10n.homeShortcutAdd,
                style: context.typography.emphasized.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
