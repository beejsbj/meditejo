import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/views/home/home_styles.dart';
import 'package:medito/views/home/widgets/home_mark_layout.dart';
import 'package:medito/views/timer/start_timer.dart';
import 'package:medito/views/timer/timer_format.dart';

// Home's tiles: the grid and the tile Pinned's Timer and presets share.
// There is no Shortcuts section any more (pass 4): the Timer leads Pinned,
// and Sounds is a floating button over every tab.

/// The Timer's length as it is set now: "20 min", or "Open-ended".
String timerLengthLabel(WidgetRef ref, AppLocalizations l10n) {
  final openEnded =
      ref.watch(timerSettingsProvider.select((s) => s.mode)) ==
      TimerMode.stopwatch;
  final minutes = ref.watch(
    cueSettingsProvider(timerCueScope).select((s) => s.durationMinutes),
  );
  return openEnded
      ? l10n.timerOpenEnded
      : formatTimerLength(Duration(minutes: minutes), l10n);
}

/// Home's tiles, laid out: two columns on a phone, more where there is
/// room, every tile the same size.
class ShortcutTileGrid extends StatelessWidget {
  const ShortcutTileGrid({
    super.key,
    required this.tiles,
    this.foldOnFirst = false,
  });

  final List<Widget> tiles;

  /// Marks the first tile as the row Home's mark gives way to.
  final bool foldOnFirst;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = (constraints.maxWidth / 220).floor().clamp(2, 4);
      final width = (constraints.maxWidth - kHomeGap * (columns - 1)) / columns;
      // Padding and icon row stay fixed; the two text lines grow with the
      // user's text size, so the tile does too.
      final scaled = 56 + MediaQuery.textScalerOf(context).scale(44);
      final height = scaled < 116 ? 116.0 : scaled;
      return Wrap(
        spacing: kHomeGap,
        runSpacing: kHomeGap,
        children: [
          for (final (i, tile) in tiles.indexed)
            if (foldOnFirst && i == 0)
              HomeFoldMarker(
                child: SizedBox(width: width, height: height, child: tile),
              )
            else
              SizedBox(width: width, height: height, child: tile),
        ],
      );
    },
  );
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
    this.onLongPress,
  });

  final Color color;
  final Color onColor;
  final Widget Function(Color color) icon;
  final String label;
  final String? caption;
  final String? semanticsLabel;
  final bool starts;
  final VoidCallback onTap;

  /// Opens the tile's actions, where it has any.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final type = context.typography;
    final muted = onColor.withValues(alpha: 0.78);
    return Semantics(
      button: true,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null
          ? null
          : AppLocalizations.of(context)!.homeCardActionsHint,
      child: HomePressable(
        color: color,
        radius: kHomeTileRadius,
        onTap: onTap,
        onLongPress: onLongPress,
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
