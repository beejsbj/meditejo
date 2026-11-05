import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/icons/medito_icons.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/settings/settings_providers.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/home/widgets/pinned/pinned_list_view.dart';
import 'package:medito/views/settings/settings_sections.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/stats_summary_card.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';
import 'package:medito/widgets/medito_icon.dart';

/// The You page: the practice kept on this device and the user's own things.
/// The stats summary (which opens the full stats page), then session history
/// and everything pinned. No settings: those are the Settings tab.
///
/// Pushed over the tabs by the person button at the top right of Home,
/// Library and Settings (`YouButton`) and by the `meditejo://you` link.
class YouView extends ConsumerWidget {
  const YouView({super.key});

  static void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    // Zen Mode hides the streak and stats everywhere.
    final zen = ref.watch(zenModeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navYou)),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (!zen) ...[const StatsSummaryCard(), const SizedBox(height: 28)],
            SettingsGroup.rows(
              key: const ValueKey('you_practice'),
              title: l10n.youSectionPractice,
              rows: [
                (last) => RowItemWidget(
                  key: const ValueKey('you_session_history'),
                  icon: MeditoIcon(
                    assetName: MeditoIcons.calendar,
                    color: onSurface,
                  ),
                  title: l10n.settingsSessionHistory,
                  hasUnderline: !last,
                  onTap: () =>
                      _push(context, const StatsScreen(initialTabIndex: 1)),
                ),
                // Home shows three pins and only while its Pinned section is
                // on; the whole list is always here.
                (last) => RowItemWidget(
                  key: const ValueKey('you_pinned'),
                  icon: Icon(Icons.push_pin_outlined, color: onSurface),
                  title: l10n.homePinnedTitle,
                  hasUnderline: !last,
                  onTap: () => openPinnedList(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
