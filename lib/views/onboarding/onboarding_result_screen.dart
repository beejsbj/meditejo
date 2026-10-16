import 'package:flutter/material.dart';
import 'package:medito/constants/styles/widget_styles.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/widgets/onboarding/onboarding_content.dart';
import 'package:medito/widgets/onboarding/onboarding_header_image.dart';

/// Local experience answer used to tailor the introduction.
enum OnboardingResultState { stateA, stateB, stateC }

OnboardingResultState deriveOnboardingState({required int experienceIndex}) =>
    switch (experienceIndex) {
      2 => OnboardingResultState.stateC,
      1 => OnboardingResultState.stateB,
      _ => OnboardingResultState.stateA,
    };

class OnboardingResultScreen extends StatelessWidget {
  const OnboardingResultScreen({
    super.key,
    this.headerImage,
    required this.state,
    required this.onGetStarted,
  });

  final String? headerImage;
  final OnboardingResultState state;
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final heading = switch (state) {
      OnboardingResultState.stateA => l10n.localIntroBeginHeading,
      OnboardingResultState.stateB => l10n.localIntroReturnHeading,
      OnboardingResultState.stateC => l10n.localIntroPracticeHeading,
    };
    final body = switch (state) {
      OnboardingResultState.stateA => l10n.localIntroBeginBody,
      OnboardingResultState.stateB => l10n.localIntroReturnBody,
      OnboardingResultState.stateC => l10n.localIntroPracticeBody,
    };

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerImage != null)
            OnboardingHeaderImage(imagePath: headerImage!),
          OnboardingContent(
            child: Padding(
              padding: const EdgeInsets.all(padding24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  Text(body, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  Text(
                    l10n.localIntroDeviceOnlyNote,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onGetStarted,
                      child: Text(l10n.onboardingResultCta),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
