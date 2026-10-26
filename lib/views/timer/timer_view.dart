import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/timer/timer_session.dart';
import 'package:medito/providers/timer/timer_settings_provider.dart';
import 'package:medito/views/cues/customize_sheet.dart';
import 'package:medito/views/timer/start_timer.dart';
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
  static const _scope = timerCueScope;
  bool _starting = false;
  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await startTimerSession(context, ref);
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
          child: Padding(
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
                Expanded(
                  child: IgnorePointer(
                    ignoring: _starting,
                    child: CustomizeSheet(
                      scope: _scope,
                      isTimer: true,
                      onStart: _start,
                      showFinishes: !stopwatch,
                      timerMinutes: stopwatch ? 0 : null,
                    ),
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
