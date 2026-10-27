import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/constants/theme/tokens.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/soundscape/sound_mix.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

import 'sound_pack_widgets.dart';

/// Corner radius of the Sounds tab's cards and of the art inside its panel.
const kSoundCardRadius = MeditejoShapes.largeIncreased;
const kPresetCardRadius = MeditejoShapes.extraLarge;

/// Space between the library's cards, across and down.
const kSoundGridGap = 10.0;

/// The library grid's cell sizes: three cards across a phone (BRIEF 19
/// follow-up), on a card small enough to hold an icon, a tick and a
/// two-line title at 101 dp.
class SoundGridMetrics {
  const SoundGridMetrics._(this.maxCardWidth, this.cardHeight);

  /// A card is never wider than this, so the grid takes as many columns as
  /// fit (3 at 360 dp and 412 dp; 8 across 1280 dp). It widens with the text
  /// size beyond 1.3x, so a 360 dp phone falls back to two columns when
  /// titles would otherwise break mid-word.
  final double maxCardWidth;
  final double cardHeight;

  /// The widest card at the default text size. The usable width of a 360 dp
  /// phone (328 dp) fits three of these and their gaps; 412 dp does too.
  static const _baseMaxWidth = 140.0;

  factory SoundGridMetrics.of(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // The factor on a 14 sp title, which is what the card sets.
    final factor = scaler.scale(14) / 14;
    return SoundGridMetrics._(
      _baseMaxWidth * math.max(1.0, factor / 1.3),
      // Padding, the icon row and a gap are fixed; two title lines grow.
      math.max(104.0, 58 + scaler.scale(40)),
    );
  }
}

/// White text and icons on the generated art; a scrim darkens the art's
/// foot, so this reads on light and dark grounds alike.
const _onArt = Colors.white;

Color _scrim(double alpha) => Colors.black.withValues(alpha: alpha);

/// A card drawn on generated art that dips under the finger (Expressive's
/// fast spatial spring) and outlines itself when [selected]. [live] lets
/// the art move (it still stops off screen and under reduced motion).
/// Content is decorative; the card is one button to screen readers,
/// labelled [semanticsLabel]. [action], if any, sits top-right and stays
/// its own button.
class SoundArtSurface extends StatefulWidget {
  const SoundArtSurface({
    super.key,
    required this.art,
    required this.semanticsLabel,
    required this.onTap,
    required this.child,
    this.live = false,
    this.onLongPress,
    this.selected = false,
    this.enabled = true,
    this.radius = kSoundCardRadius,
    this.action,
    this.topScrim = false,
    this.veiled = false,
  });

  final ArtSubject art;

  /// Darkens the top too, for text set at the top of the art.
  final bool topScrim;

  /// Dims the art: the sound is not on the phone yet.
  final bool veiled;
  final bool live;
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
              ArtCover(subject: widget.art, live: widget.live),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: widget.topScrim
                        ? const [0, 0.45, 0.6, 1]
                        : const [0.4, 1],
                    colors: widget.topScrim
                        ? [
                            _scrim(0.42),
                            Colors.transparent,
                            Colors.transparent,
                            _scrim(0.5),
                          ]
                        : [Colors.transparent, _scrim(0.5)],
                  ),
                ),
              ),
              if (widget.veiled) ColoredBox(color: _scrim(0.28)),
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

/// A sound's icon on a soft disc, on art.
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

/// One sound in the library, as a square tile: tap to layer it into the
/// mix or take it out. Its corner says which: a quiet + while it's out, a
/// tick while it's in. Its art moves while it sounds.
class SoundCard extends StatelessWidget {
  const SoundCard({
    super.key,
    required this.soundId,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.params = const {},
    this.sounding = false,
    this.offer,
  });

  final String soundId;
  final String title;
  final bool selected;

  /// A generated layer's settings (the noise's colour draws its art).
  final Map<String, Object?> params;

  /// In the mix and playing: the art moves.
  final bool sounding;

  /// False when the mix is full and this sound is not in it.
  final bool enabled;
  final VoidCallback onTap;

  /// Set while the sound is not on the phone (the sound pack): the corner
  /// offers the download in place of the +, and a tap downloads, cancels or
  /// retries rather than adds.
  final SoundOffer? offer;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    const pop = MeditejoMotion.expressiveFastSpatial;
    return SoundArtSurface(
      art: ArtSubject.sound(soundId, params),
      live: sounding,
      veiled: offer != null,
      semanticsLabel: offer?.semanticsLabel(context, title) ?? title,
      selected: selected && offer == null,
      // A sound to download is never dimmed by a full mix: it can be fetched.
      enabled: enabled || offer != null,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: AnimatedSwitcher(
                duration: still ? Duration.zero : pop.duration,
                switchInCurve: pop.curve,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: offer != null
                    ? KeyedSubtree(
                        key: ValueKey('offer_${offer!.phase.name}'),
                        child: SoundOfferBadge(
                          offer!,
                          key: ValueKey('sound_offer_$soundId'),
                        ),
                      )
                    : DecoratedBox(
                        key: ValueKey(selected),
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary
                              : Colors.black.withValues(alpha: 0.22),
                          shape: BoxShape.circle,
                          border: selected
                              ? null
                              : Border.all(
                                  color: _onArt.withValues(alpha: 0.7),
                                  width: 1.5,
                                ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            selected
                                ? Symbols.check_rounded
                                : Symbols.add_rounded,
                            key: ValueKey('sound_state_$soundId'),
                            size: 16,
                            weight: 600,
                            color: selected ? scheme.onPrimary : _onArt,
                          ),
                        ),
                      ),
              ),
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

/// A preset's card size: two to one, growing with large text.
Size presetCardSize(BuildContext context) {
  final factor = MediaQuery.textScalerOf(context).scale(14) / 14;
  final h = 136 * (factor > 1.15 ? factor / 1.15 : 1.0);
  return Size(h * 2, h);
}

/// How far the stacked prints show under a preset card.
const kPresetStackDepth = 8.0;

/// A preset as a wide print on a small stack of others (it is several
/// sounds at once): tapping it replaces the mix, so it carries a play
/// button where a sound carries its +. An overline says whose it is, and
/// chips name its layers.
class PresetCard extends StatelessWidget {
  const PresetCard({
    super.key,
    required this.presetId,
    required this.label,
    required this.layers,
    required this.layerTitles,
    required this.builtIn,
    required this.playing,
    required this.onTap,
    this.onDelete,
    this.missing = 0,
  });

  final String presetId;
  final String label;
  final List<SoundLayer> layers;

  /// Its layers' names, loudest first.
  final List<String> layerTitles;

  /// Meditejo's own, rather than the user's.
  final bool builtIn;
  final bool playing;
  final VoidCallback onTap;

  /// Null for a built-in preset, which can't be deleted.
  final VoidCallback? onDelete;

  /// How many of its sounds are not on the phone (the sound pack). It plays
  /// the rest, and the card says so.
  final int missing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final type = context.typography;
    final scheme = Theme.of(context).colorScheme;
    final still = MediaQuery.disableAnimationsOf(context);
    const swap = MeditejoMotion.expressiveFastSpatial;
    final radius = BorderRadius.circular(kPresetCardRadius);
    Widget print(double inset, double drop, Color color) => Positioned(
      left: inset,
      right: inset,
      top: drop,
      bottom: kPresetStackDepth - drop,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: radius),
      ),
    );
    final card = SoundArtSurface(
      art: ArtSubject.layers(presetId, layers),
      live: playing,
      topScrim: true,
      radius: kPresetCardRadius,
      semanticsLabel: [
        if (playing)
          '${l10n.soundsPlayPreset(label)}, ${l10n.soundsPresetPlaying}'
        else
          l10n.soundsPlayPreset(label),
        if (missing > 0) l10n.soundPackPresetMissing(missing),
      ].join(', '),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (builtIn ? l10n.soundsPresetOurs : l10n.soundsPresetYours)
                  .toUpperCase(),
              key: ValueKey('preset_overline_$presetId'),
              style: type.baseline.labelSmall?.copyWith(
                color: _onArt.withValues(alpha: 0.85),
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: type.emphasized.titleMedium?.copyWith(color: _onArt),
            ),
            if (missing > 0)
              Padding(
                key: ValueKey('preset_missing_$presetId'),
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(
                      Symbols.download_rounded,
                      size: 14,
                      color: _onArt,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        l10n.soundPackPresetMissing(missing),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.baseline.labelSmall?.copyWith(
                          color: _onArt.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // As many whole chips as fit on one line, then "+n".
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Row(
                      children: [
                        for (final (i, chip) in _fitChips(
                          context,
                          layerTitles,
                          box.maxWidth,
                          type.baseline.labelSmall,
                        ).indexed)
                          // Only the first gives way; the rest were measured
                          // to fit beside it.
                          Flexible(
                            flex: i == 0 ? 1 : 0,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _Chip(chip),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: still ? Duration.zero : swap.duration,
                  switchInCurve: swap.curve,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: DecoratedBox(
                    key: ValueKey(playing),
                    decoration: BoxDecoration(
                      color: playing ? scheme.primary : _onArt,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        playing
                            ? Symbols.equalizer_rounded
                            : Symbols.play_arrow_rounded,
                        key: ValueKey('preset_play_$presetId'),
                        fill: 1,
                        size: 24,
                        color: playing ? scheme.onPrimary : Colors.black87,
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
    return Stack(
      children: [
        print(16, kPresetStackDepth, scheme.surfaceContainerHighest),
        print(8, kPresetStackDepth / 2, scheme.outlineVariant),
        Positioned.fill(bottom: kPresetStackDepth, child: card),
      ],
    );
  }
}

/// Space a chip takes beyond its text: padding and the gap after it.
const _chipChrome = 7.0 * 2 + 4;

/// Which of [titles] fit on one line of [width] as whole chips, followed by
/// "+n" for the rest. The first always shows (it ellipsises if it must).
List<String> _fitChips(
  BuildContext context,
  List<String> titles,
  double width,
  TextStyle? style,
) {
  double measure(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = painter.width + _chipChrome;
    painter.dispose();
    return w;
  }

  final out = <String>[];
  var used = 0.0;
  for (var i = 0; i < titles.length; i++) {
    final rest = titles.length - i - 1;
    final more = rest > 0 ? measure('+$rest') : 0.0;
    final w = measure(titles[i]);
    if (i > 0 && used + w + more > width) {
      out.add('+${titles.length - i}');
      return out;
    }
    out.add(titles[i]);
    used += w;
  }
  return out;
}

/// A small label on art.
class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.typography.baseline.labelSmall?.copyWith(color: _onArt),
      ),
    ),
  );
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
