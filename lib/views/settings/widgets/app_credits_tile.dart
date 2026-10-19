import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';
import 'package:medito/views/settings/about_screen.dart';

class AppCreditsTile extends StatelessWidget {
  const AppCreditsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RowItemWidget(
      icon: const Icon(Icons.info_outline),
      title: l10n.aboutMeditejo,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
    );
  }
}
