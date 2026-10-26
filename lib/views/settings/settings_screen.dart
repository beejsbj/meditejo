import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/you/you_view.dart';

/// Settings, as the tab and the `settings` link know it. The body is the
/// [YouView] (stats summary, then the settings groups); the tab bar's You tab
/// hosts [YouView] directly.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      YouView(title: AppLocalizations.of(context)!.settings);
}
