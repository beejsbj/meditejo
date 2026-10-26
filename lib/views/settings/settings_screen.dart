import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/you/you_view.dart';

/// Settings, as the `settings` link opens it: the [YouView] body (stats summary,
/// then the settings groups) under the title "Settings". The You tab hosts
/// [YouView] directly.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      YouView(title: AppLocalizations.of(context)!.settings);
}
