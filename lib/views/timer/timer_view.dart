import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/providers/player/player_provider.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/services/audio/timer_audio_file.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/player/player_view.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/inputs/medito_segmented_tabs.dart';

/// The timer is the same Customize surface as a guided session. A silent
/// local file carries its duration through native, screen-off playback.
class TimerView extends ConsumerStatefulWidget {
  const TimerView({super.key});
  @override
  ConsumerState<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends ConsumerState<TimerView> {
  static const _scope = CueScope(CueKind.practice);
  bool _starting = false;
  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    final l10n = AppLocalizations.of(context)!;
    final mode = ref.read(timerSettingsProvider).mode;
    final cues = ref.read(cueSettingsProvider(_scope));
    final duration = mode == TimerMode.stopwatch
        ? kStopwatchMaxDuration
        : Duration(minutes: cues.durationMinutes);
    unawaited(HapticFeedback.mediumImpact());
    try {
      final path = await TimerAudioFile.prepare(duration);
      if (!mounted) return;
      ref
          .read(playerProvider.notifier)
          .prepare(
            timerPlaybackRequest(
              mode: mode,
              duration: duration,
              filePath: path,
              title: mode == TimerMode.stopwatch
                  ? l10n.timerModeStopwatch
                  : l10n.timerTitle,
            ),
          );
      unawaited(
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlayerView()),
        ),
      );
    } catch (e, st) {
      AppLogger.e('TIMER', 'Failed to start timer', e, st);
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.unableToLoadAudio)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(timerSettingsProvider);
    final stopwatch = settings.mode == TimerMode.stopwatch;
    return Scaffold(
      bottomNavigationBar: SingleBackButtonActionBar(
        onBackPressed: () => Navigator.pop(context),
      ),
      body: AdaptivePageBody(
        maxWidth: 600,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MeditoSegmentedTabs(
                  labels: [l10n.timerTitle, l10n.timerModeStopwatch],
                  selectedIndex: settings.mode.index,
                  onChanged: (index) => ref
                      .read(timerSettingsProvider.notifier)
                      .setMode(TimerMode.values[index]),
                ),
                const SizedBox(height: 16),
                if (stopwatch) ...[
                  Text(
                    l10n.timerStopwatchTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.timerStopwatchCaption),
                  const SizedBox(height: 16),
                ],
                IgnorePointer(
                  ignoring: _starting,
                  child: CustomizeSheet(
                    scope: _scope,
                    isTimer: true,
                    embedded: true,
                    onStart: _start,
                    showFinishes: !stopwatch,
                    timerMinutes: stopwatch ? 0 : null,
                  ),
                ),
                if (_starting) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
