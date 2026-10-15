import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/constants/constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/views/onboarding/battery_optimization_screen.dart';
import 'package:medito/views/onboarding/notifications_screen.dart';
import 'package:medito/views/onboarding/onboarding_question_screen.dart';
import 'package:medito/views/onboarding/onboarding_result_screen.dart';
import 'package:medito/widgets/onboarding/progress_indicator_widget.dart';

class OnboardingPagerScreen extends ConsumerStatefulWidget {
  const OnboardingPagerScreen({super.key});

  @override
  ConsumerState<OnboardingPagerScreen> createState() =>
      OnboardingPagerScreenState();
}

class OnboardingPagerScreenState extends ConsumerState<OnboardingPagerScreen> {
  final PageController _controller = PageController();
  int _currentPage = 0;
  int _experienceIndex = 0;
  bool _showBatteryScreen = false;
  bool _advancing = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _checkBatteryGuidance();
  }

  Future<void> _checkBatteryGuidance() async {
    try {
      final show = await shouldShowBatteryOptimizationScreen();
      // Do not insert a setup page underneath someone who has already reached
      // the result while the device query was pending.
      if (mounted && _currentPage < 2) {
        setState(() => _showBatteryScreen = show);
      }
    } catch (_) {
      // Device-specific guidance is optional; onboarding can always continue.
    }
  }

  Future<void> _nextPage() async {
    if (_advancing || _completed || !_controller.hasClients) return;
    _advancing = true;
    try {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeIn,
      );
    } finally {
      _advancing = false;
    }
  }

  Future<void> _onExperienceSelected(int index) async {
    if (_advancing || _completed) return;
    setState(() => _experienceIndex = index);
    await ref
        .read(sharedPreferencesProvider)
        .setInt(SharedPreferenceConstants.onboardingExperienceLevel, index);
    if (mounted) await _nextPage();
  }

  void _onGetStarted() {
    if (_completed || !mounted) return;
    _completed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final pages = <Widget>[
      OnboardingQuestionScreen(
        headerImage: AssetConstants.onboardingImage1,
        question: l10n.onboardingExperienceQuestion,
        subtext: l10n.onboardingExperienceSubtext,
        options: [
          l10n.onboardingExperienceNever,
          l10n.onboardingExperienceALittle,
          l10n.onboardingExperienceRegular,
        ],
        onOptionSelected: _onExperienceSelected,
      ),
      NotificationsScreen(
        headerImage: AssetConstants.onboardingImage3,
        onNext: _nextPage,
      ),
      if (_showBatteryScreen)
        BatteryOptimizationScreen(
          headerImage: AssetConstants.onboardingImage3,
          onNext: _nextPage,
        ),
      OnboardingResultScreen(
        headerImage: AssetConstants.onboardingImage3,
        state: deriveOnboardingState(experienceIndex: _experienceIndex),
        onGetStarted: _onGetStarted,
      ),
    ];
    final setupSteps = pages.length - 1;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => pages[index],
              ),
            ),
            if (_currentPage < setupSteps)
              OnboardingProgressIndicator(
                currentIndex: _currentPage,
                totalSteps: setupSteps,
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
