import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/player/sleep_timer_provider.dart';

/// The recording player's sleep timer, beside Autoplay under the transport:
/// "Sleep" when off; the time left (or "End of track") while set, in the
/// same rounded highlight Autoplay uses when on.
class SleepTimerButton extends ConsumerStatefulWidget {
  const SleepTimerButton({super.key});

  @override
  ConsumerState<SleepTimerButton> createState() => _SleepTimerButtonState();
}

class _SleepTimerButtonState extends ConsumerState<SleepTimerButton> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTick(bool counting) {
    if (counting && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!counting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sleep = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);
    final left = sleep.remaining(notifier.now());
    _syncTick(left != null);
    final label = left != null
        ? formatSleepRemaining(left)
        : sleep.endOfTrack
        ? l10n.playerSleepEndOfTrack
        : l10n.playerSleep;
    return Tooltip(
      message: l10n.playerSleepTimer,
      child: TextButton.icon(
        key: const ValueKey('player_sleep'),
        onPressed: () => unawaited(showSleepTimerSheet(context)),
        style: TextButton.styleFrom(
          foregroundColor: ColorConstants.white,
          backgroundColor: sleep.isSet
              ? ColorConstants.graphite.withAlpha(200)
              : Colors.transparent,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        icon: Icon(
          sleep.isSet ? Icons.bedtime_rounded : Icons.bedtime_outlined,
        ),
        label: Text(
          label,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
    );
  }
}

/// m:ss, or h:mm:ss past an hour.
String formatSleepRemaining(Duration d) {
  final s = (d.inMilliseconds / 1000).ceil();
  String two(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

Future<void> showSleepTimerSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).bottomSheetTheme.backgroundColor,
      builder: (_) => const SleepTimerSheet(),
    );

/// 5, 10, 15 or 30 minutes, or the end of the track; and off, while set.
/// A choice closes the sheet.
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final sleep = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);
    void choose(Future<void> Function() action) {
      unawaited(action());
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Semantics(
                header: true,
                child: Text(
                  l10n.playerSleepTimer,
                  style: context.typography.emphasized.titleLarge,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in sleepTimerMinutes)
                  ChoiceChip(
                    key: ValueKey('sleep_$minutes'),
                    label: Text(l10n.playerSleepMinutes(minutes)),
                    selected: false,
                    onSelected: (_) =>
                        choose(() => notifier.setMinutes(minutes)),
                  ),
                ChoiceChip(
                  key: const ValueKey('sleep_end_of_track'),
                  label: Text(l10n.playerSleepEndOfTrack),
                  selected: sleep.endOfTrack,
                  onSelected: (_) => choose(notifier.setEndOfTrack),
                ),
              ],
            ),
            if (sleep.isSet) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('sleep_off'),
                  onPressed: () => choose(notifier.cancel),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(l10n.playerSleepOff),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
