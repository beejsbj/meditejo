import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/utils/utils.dart';
import 'package:medito/views/home/widgets/header/home_header_widget.dart';
import 'package:medito/views/home/widgets/home_gradient_border.dart';
import 'package:medito/views/player/widgets/bottom_actions/single_back_action_bar.dart';
import 'package:medito/views/settings/widgets/update_section.dart';
import 'package:medito/widgets/adaptive/adaptive_page_body.dart';

/// Settings → Advanced → About Meditejo: the installed version, credits, and
/// (on Android) whether a newer build is out.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final installed = ref.watch(installedBuildProvider).value;

    return Scaffold(
      bottomNavigationBar: SingleBackButtonActionBar(
        onBackPressed: () => Navigator.pop(context),
      ),
      body: AdaptivePageBody(
        maxWidth: 760,
        child: SafeArea(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                centerTitle: false,
                automaticallyImplyLeading: false,
                backgroundColor: theme.scaffoldBackgroundColor,
                toolbarHeight: 56.0,
                pinned: true,
                floating: true,
                elevation: 0.0,
                title: HomeHeaderWidget(greeting: l10n.aboutMeditejo),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(padding16),
                sliver: SliverList.list(
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/app_icons/placeholder.png',
                          width: 48,
                          height: 48,
                        ),
                        const SizedBox(width: padding16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Meditejo', style: theme.textTheme.titleLarge),
                              if (installed != null)
                                Text(
                                  l10n.aboutVersion(
                                    installed.versionName,
                                    '${installed.versionCode}',
                                  ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: padding16),
                    HomeGradientBorder(
                      backgroundColor: theme.cardColor,
                      borderRadius: 14,
                      borderWidth: 0.5,
                      child: const Material(
                        type: MaterialType.transparency,
                        child: UpdateSection(),
                      ),
                    ),
                    const SizedBox(height: padding16),
                    Text(l10n.forkCredit, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: padding8),
                    Wrap(
                      spacing: padding8,
                      children: [
                        TextButton(
                          onPressed: () => launchURLInBrowser(
                            'https://github.com/beejsbj/meditejo',
                          ),
                          child: Text(l10n.sourceCode),
                        ),
                        TextButton(
                          onPressed: () => launchURLInBrowser(
                            'https://meditofoundation.org',
                          ),
                          child: Text(l10n.upstreamProject),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
