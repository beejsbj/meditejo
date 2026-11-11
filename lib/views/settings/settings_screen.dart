import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/debug/debug_info_screen.dart';
import 'package:medito/views/settings/settings_sections.dart';
import 'package:medito/views/you/you_button.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';

/// The Settings tab: every setting, grouped by what a person is trying to do.
/// Stats and history are not here; they are on the You page, which the
/// person button at the top right opens.
///
/// A `*settings*` link other than `meditejo://settings` pushes this screen
/// over the tabs, where its app bar gains a back button.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          // A hidden way to the debug screen, as Settings always had.
          onLongPress: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DebugInfoScreen()),
          ),
          child: Text(l10n.settings),
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: YouButton.inset),
            child: YouButton(),
          ),
        ],
      ),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: const [SettingsSections()],
        ),
      ),
    );
  }
}
