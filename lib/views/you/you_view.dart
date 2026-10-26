import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/theme/expressive_typography.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/settings/settings_providers.dart';
import 'package:medito/views/debug/debug_info_screen.dart';
import 'package:medito/views/settings/settings_sections.dart';
import 'package:medito/views/you/stats_summary_card.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';

/// The You tab: a summary of the practice kept on this device, which opens
/// the full stats page, and below it every setting, grouped by what a person
/// is trying to do.
///
/// One widget, hosted by the You tab as `const YouView()`. [title] defaults to
/// "You"; [SettingsScreen] (the `settings` link) shows the same body under its
/// own name.
class YouView extends ConsumerWidget {
  const YouView({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // Zen Mode hides the streak and stats everywhere.
    final zen = ref.watch(zenModeProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AdaptivePageBody(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                // A hidden way to the debug screen, as Settings always had.
                onLongPress: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const DebugInfoScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 20),
                  child: Semantics(
                    header: true,
                    child: Text(
                      title ?? l10n.navYou,
                      style: context.typography.emphasized.headlineMedium,
                    ),
                  ),
                ),
              ),
              if (!zen) ...[
                const StatsSummaryCard(),
                const SizedBox(height: 28),
              ],
              const SettingsSections(),
            ],
          ),
        ),
      ),
    );
  }
}
