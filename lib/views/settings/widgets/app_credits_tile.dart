import 'package:flutter/material.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/home/widgets/bottom_sheet/row_item_widget.dart';

class AppCreditsTile extends StatelessWidget {
  const AppCreditsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return RowItemWidget(
      icon: const Icon(Icons.info_outline),
      title: l10n.aboutMeditejo,
      onTap: () => showAboutDialog(
        context: context,
        applicationName: l10n.appName,
        applicationIcon: Image.asset(
          'assets/images/app_icons/placeholder.png',
          width: 48,
          height: 48,
        ),
        applicationLegalese: l10n.forkCredit,
        children: [
          TextButton(
            onPressed: () =>
                launchURLInBrowser('https://github.com/beejsbj/meditejo'),
            child: Text(l10n.sourceCode),
          ),
          TextButton(
            onPressed: () => launchURLInBrowser('https://meditofoundation.org'),
            child: Text(l10n.upstreamProject),
          ),
        ],
      ),
    );
  }
}
