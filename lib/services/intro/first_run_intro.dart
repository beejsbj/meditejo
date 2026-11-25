import 'package:shared_preferences/shared_preferences.dart';

import 'package:medito/constants/strings/shared_preference_constants.dart';

/// Whether the first-launch intro ("What Meditejo is") is still to be shown.
///
/// It is shown once, on a fresh install, and never as a gate: leaving it in
/// any way counts as seen. Settings › About opens it again.
abstract final class FirstRunIntro {
  /// True until the intro has been left once.
  static bool isDue(SharedPreferences prefs) =>
      !(prefs.getBool(SharedPreferenceConstants.introSeen) ?? false);

  static Future<void> markSeen(SharedPreferences prefs) =>
      prefs.setBool(SharedPreferenceConstants.introSeen, true);

  /// Run at startup, before this launch records its version. An install that
  /// was in use before the intro existed has already met the app, so it
  /// skips the intro: anyone who answered Medito's questionnaire, and any
  /// install with a recorded version, practice stats or pins. A fresh install
  /// left on the intro (the app closed under it) has recorded its version by
  /// the next launch, so the intro is still shown only once.
  static Future<void> settleForExistingInstall(SharedPreferences prefs) async {
    if (prefs.containsKey(SharedPreferenceConstants.introSeen)) return;
    const inUse = [
      SharedPreferenceConstants.onboardingExperienceLevel,
      SharedPreferenceConstants.installedVersionHistory,
      SharedPreferenceConstants.localAllStatsKey,
      SharedPreferenceConstants.pinnedCourseIds,
    ];
    if (inUse.any(prefs.containsKey)) await markSeen(prefs);
  }
}
