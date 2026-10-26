import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/widgets/generated_artwork.dart';

import 'sound_labels.dart';

/// Corner radius of the Sounds tab's cards and of the art inside its panel.
const kSoundCardRadius = MeditejoShapes.largeIncreased;
const kPresetCardRadius = MeditejoShapes.extraLarge;

/// White text and icons on the generated art; the art's colours are muted
/// and a scrim darkens the foot, so this reads in both themes.
const _onArt = Colors.white;

/// A card drawn on generated art that dips under the finger (Expressive's
/// fast spatial spring) and outlines itself when [selected]. Content is
/// decorative; the card is one button to screen readers, labelled
/// [semanticsLabel]. [action], if any, sits top-right and stays its own
/// button.
class SoundArtSurface extends StatefulWidget {
  const SoundArtSurface({
    super.key,
    required this.seed,
    required this.colors,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.radius = kSoundCardRadius,
    this.action,
  });

  final String seed;
  final (Color, Color) colors;
  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool enabled;
  final double radius;
  final Widget child;
  final Widget? action;

  @override
  State<SoundArtSurface> createState() => _SoundArtSurfaceState();
}

class _SoundArtSurfaceState extends State<SoundArtSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    const press = MeditejoMotion.expressiveFastSpatial;
    const fade = MeditejoMotion.effects;
    final radius = BorderRadius.circular(widget.radius);
    final card = Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GeneratedArtwork(seed: widget.seed, colors: widget.colors),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.35, 1],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.38),
                    ],
                  ),
                ),
              ),
              widget.child,
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  splashColor: _onArt.withValues(alpha: 0.16),
                  highlightColor: _onArt.withValues(alpha: 0.08),
                  onHighlightChanged: (pressed) =>
                      setState(() => _pressed = pressed),
                ),
              ),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: still ? Duration.zero : fade.duration,
                  curve: fade.curve,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      width: 3,
                      color: widget.selected
                          ? scheme.primary
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AnimatedScale(
      scale: _pressed && !still ? 0.95 : 1,
      duration: still ? Duration.zero : press.duration,
      curve: press.curve,
      child: AnimatedOpacity(
        opacity: widget.enabled ? 1 : 0.4,
        duration: still ? Duration.zero : fade.duration,
        child: widget.action == null
            ? card
            : Stack(
                fit: StackFit.expand,
                children: [
                  card,
                  Positioned(top: 4, right: 4, child: widget.action!),
                ],
              ),
      ),
    );
  }
}

/// A sound's icon on a soft disc, as the art's top-left mark.
class SoundIconBubble extends StatelessWidget {
  const SoundIconBubble(this.icon, {super.key, this.size = 20});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: _onArt.withValues(alpha: 0.18),
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: EdgeInsets.all(size * 0.4),
      child: Icon(icon, size: size, color: _onArt, fill: 1),
    ),
  );
}

/// One sound in the library: tap to layer it into the mix or take it out.
class SoundCard extends StatelessWidget {
  const SoundCard({
    super.key,
    required this.soundId,
    required this.title,
    required this.look,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String soundId;
  final String title;
  final SoundLook look;
  final bool selected;

  /// False when the mix is full and this sound is not in it.
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    const pop = MeditejoMotion.expressiveFastSpatial;
    return SoundArtSurface(
      seed: soundId,
      colors: look.colors,
      semanticsLabel: title,
      selected: selected,
      enabled: enabled,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SoundIconBubble(look.icon),
                const Spacer(),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: still ? Duration.zero : pop.duration,
                  curve: pop.curve,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Symbols.check_rounded,
                        size: 18,
                        weight: 600,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.typography.emphasized.titleSmall?.copyWith(
                color: _onArt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A preset as a large card: one tap plays it.
class PresetCard extends StatelessWidget {
  const PresetCard({
    super.key,
    required this.presetId,
    required this.label,
    required this.looks,
    required this.playing,
    required this.onTap,
    this.onDelete,
  });

  final String presetId;
  final String label;

  /// The looks of its layers, in order: the first colours the card.
  final List<SoundLook> looks;
  final bool playing;
  final VoidCallback onTap;

  /// Null for a built-in preset, which can't be deleted.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final still = MediaQuery.disableAnimationsOf(context);
    const swap = MeditejoMotion.expressiveFastSpatial;
    final icons = <IconData>{for (final look in looks) look.icon}.take(4);
    return SoundArtSurface(
      seed: presetId,
      colors:
          (looks.isEmpty ? SoundLook.forCategory(null) : looks.first).colors,
      radius: kPresetCardRadius,
      semanticsLabel: playing
          ? '${l10n.soundsPlayPreset(label)}, ${l10n.soundsPresetPlaying}'
          : l10n.soundsPlayPreset(label),
      selected: playing,
      onTap: onTap,
      onLongPress: onDelete,
      action: onDelete == null
          ? null
          : PopupMenuButton<void>(
              key: ValueKey('preset_menu_$presetId'),
              icon: const Icon(Symbols.more_vert_rounded, color: _onArt),
              itemBuilder: (_) => [
                PopupMenuItem<void>(
                  key: ValueKey('preset_delete_$presetId'),
                  onTap: onDelete,
                  child: Text(l10n.soundsDelete),
                ),
              ],
            ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final icon in icons)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SoundIconBubble(icon, size: 16),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: type.emphasized.titleMedium?.copyWith(color: _onArt),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    playing
                        ? l10n.soundsPresetPlaying
                        : l10n.soundsLayerCount(looks.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.baseline.bodyMedium?.copyWith(
                      color: _onArt.withValues(alpha: 0.85),
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: still ? Duration.zero : swap.duration,
                  switchInCurve: swap.curve,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: DecoratedBox(
                    key: ValueKey(playing),
                    decoration: BoxDecoration(
                      color: _onArt.withValues(alpha: playing ? 1 : 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        playing
                            ? Symbols.equalizer_rounded
                            : Symbols.play_arrow_rounded,
                        fill: 1,
                        size: 24,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The last card of the presets row: keeps the current mix as a preset.
class SavePresetCard extends StatelessWidget {
  const SavePresetCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(kPresetCardRadius),
      side: BorderSide(color: scheme.outlineVariant, width: 1.5),
    );
    return Material(
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Symbols.bookmark_add_rounded,
                size: 32,
                color: scheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.soundsSavePreset,
                textAlign: TextAlign.center,
                style: context.typography.emphasized.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
