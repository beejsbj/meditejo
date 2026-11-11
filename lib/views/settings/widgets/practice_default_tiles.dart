import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/day_boundary_offset_provider.dart';
import 'package:medito/providers/player/playback_speed_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/player/widgets/bottom_actions/widgets/speed_sheet.dart';
import 'package:medito/views/settings/widgets/day_boundary_offset_dialog.dart';

/// When a new day starts for streaks and stats.
class DayStartTile extends ConsumerWidget {
  const DayStartTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final offset = ref.watch(dayBoundaryOffsetProvider).value ?? 0;
    return RowItemWidget(
      icon: Icon(
        Icons.bedtime_outlined,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.settingsDayStarts,
      subTitle: offset == 0
          ? l10n.settingsDayStartsMidnight
          : l10n.settingsDayStartsAt(offset),
      hasUnderline: hasUnderline,
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (_) => DayBoundaryOffsetDialog(currentHours: offset),
        );
        if (picked != null && picked != offset) {
          await ref
              .read(dayBoundaryOffsetProvider.notifier)
              .setOffsetHours(picked);
        }
      },
    );
  }
}

/// The bells, cues and background sound a kind of session starts with: the
/// Customize sheet, opened for Practice or for Talks without a session.
class CueDefaultsTile extends StatelessWidget {
  const CueDefaultsTile({
    super.key,
    required this.kind,
    this.hasUnderline = true,
  });

  final CueKind kind;
  final bool hasUnderline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final practice = kind == CueKind.practice;
    return RowItemWidget(
      key: ValueKey('cue_defaults_${kind.name}'),
      icon: Icon(
        practice
            ? Icons.self_improvement_outlined
            : Icons.record_voice_over_outlined,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: practice ? l10n.settingsPracticeCues : l10n.settingsTalksCues,
      subTitle: practice
          ? l10n.settingsPracticeCuesCaption
          : l10n.settingsTalksCuesCaption,
      hasUnderline: hasUnderline,
      onTap: () => showCustomizeModal<void>(
        context,
        (_) => CustomizeSheet(
          scope: CueScope(kind),
          // No session, so no "Finishes at" line.
          showFinishes: false,
        ),
      ),
    );
  }
}

/// The speed each kind of session starts at, side by side, opening the
/// player's speed sheet without a session.
class PlaybackSpeedTile extends ConsumerWidget {
  const PlaybackSpeedTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final practice = ref.watch(playbackSpeedProvider(CueKind.practice));
    final talks = ref.watch(playbackSpeedProvider(CueKind.talks));
    return RowItemWidget(
      key: const ValueKey('settings_playback_speed'),
      icon: Icon(
        Icons.speed_rounded,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.settingsPlaybackSpeed,
      subTitle: l10n.settingsPlaybackSpeedCaption(
        formatSpeed(practice),
        formatSpeed(talks),
      ),
      hasUnderline: hasUnderline,
      onTap: () => showSpeedSheet(context),
    );
  }
}
