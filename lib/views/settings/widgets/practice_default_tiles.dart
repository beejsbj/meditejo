import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/day_boundary_offset_provider.dart';
import 'package:medito/providers/duration_preference_provider.dart';
import 'package:medito/providers/guide_name_preference_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/settings/widgets/day_boundary_offset_dialog.dart';
import 'package:medito/widgets/snackbar_widget.dart' show showSnackBar;

/// The guide chosen on the last track, with a way to forget it.
class DefaultGuideTile extends ConsumerWidget {
  const DefaultGuideTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final guide = ref.watch(guideNamePreferenceProvider);
    return RowItemWidget(
      icon: Icon(
        Icons.face_outlined,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.defaultGuideName,
      subTitle: guide ?? l10n.notSet,
      hasUnderline: hasUnderline,
      isTrailingIcon: false,
      trailing: guide == null
          ? null
          : IconButton(
              tooltip: l10n.clearDefault,
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                ref.read(guideNamePreferenceProvider.notifier).clearGuideName();
                showSnackBar(context, l10n.defaultGuideNameCleared);
              },
            ),
    );
  }
}

/// The length chosen on the last track; opens a sheet to change it.
class DefaultLengthTile extends ConsumerWidget {
  const DefaultLengthTile({super.key, this.hasUnderline = true});

  final bool hasUnderline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final duration = ref.watch(durationPreferenceProvider);
    return RowItemWidget(
      icon: Icon(
        Icons.access_time_outlined,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      title: l10n.defaultDuration,
      subTitle: duration == null
          ? l10n.notSet
          : '${duration ~/ 60000} ${l10n.min}',
      hasUnderline: hasUnderline,
      // With nothing chosen yet there is nothing to adjust: the first track
      // played sets it.
      onTap: duration == null
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Theme.of(
                context,
              ).bottomSheetTheme.backgroundColor,
              builder: (_) => const DefaultLengthSheet(),
            ),
    );
  }
}

class DefaultLengthSheet extends ConsumerWidget {
  const DefaultLengthSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final duration = ref.watch(durationPreferenceProvider) ?? 600000;
    final minutes = (duration / 60000).clamp(1, 60).toDouble();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.defaultDuration,
              style: context.typography.emphasized.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${minutes.round()} ${l10n.min}',
              style: context.typography.baseline.bodyLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Slider(
              value: minutes,
              min: 1,
              max: 60,
              divisions: 59,
              // Otherwise read as a percentage of the range.
              semanticFormatterCallback: (v) =>
                  l10n.timerPresetSemantics(v.round()),
              onChanged: (v) => ref
                  .read(durationPreferenceProvider.notifier)
                  .setDuration((v * 60000).round()),
            ),
            Text(
              l10n.defaultsNote,
              style: context.typography.baseline.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      onTap: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
        builder: (_) => CustomizeSheet(
          scope: CueScope(kind),
          // No session, so no "Finishes at" line.
          showFinishes: false,
        ),
      ),
    );
  }
}
