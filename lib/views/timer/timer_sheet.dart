import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/timer/start_timer.dart';

/// Opens the Timer: the Customize sheet in its timer form, with the length
/// on its dial (∞ at the top: open-ended) and Start at its foot. Start
/// closes the sheet and opens the player on the timer as it is set.
///
/// [openEnded] rests the dial on ∞ first: what an old link to the stopwatch
/// asks for.
Future<void> showTimerSheet(
  BuildContext context, {
  bool openEnded = false,
}) async {
  if (openEnded) {
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(timerSettingsProvider.notifier).setMode(TimerMode.stopwatch);
  }
  final start = await showCustomizeModal<bool>(
    context,
    (sheetContext) => CustomizeSheet(
      scope: timerCueScope,
      isTimer: true,
      onStart: () => Navigator.of(sheetContext).pop(true),
    ),
  );
  if (start != true || !context.mounted) return;
  await startTimerSession(context);
}
