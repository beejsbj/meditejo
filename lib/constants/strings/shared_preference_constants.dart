class SharedPreferenceConstants {
  static const String bgSoundVolume = 'bgSoundVolume';
  static const String bgSound = 'bgSound';
  static const String listBgSound = 'listBgSound';
  static const String bgSoundCatalog = 'bgSoundCatalog';
  static const String downloads = 'downloads';
  static const String currentPlayingTrack = 'currentPlayingTrack';
  static const String savedHours = 'savedHours';
  static const String savedMinutes = 'savedMinutes';
  static const String lastSelectedGuideName = 'lastSelectedGuideName';
  static const String favorites = 'favorites';
  static const String localAllStatsKey = 'local_all_stats';
  static const String streakCircleDisplayPreference =
      'streak_circle_display_preference';
  static const String dayBoundaryOffsetHours = 'day_boundary_offset_hours';
  static const String homeWidgetOrder = 'homeWidgetOrder';
  static const String dndEnabled = 'dnd_enabled';
  static const String localePreference = 'locale_preference';
  static const String themePreference = 'theme_preference';
  static const String dailyReminderEnabled = 'daily_reminder_enabled';
  static const String reminderPromptDismissedForever =
      'reminder_prompt_dismissed_forever';
  static const String notifPermissionFixNeeded = 'notif_permission_fix_needed';
  static const String reminderFlagRepaired = 'reminder_flag_repair_v1';
  static const String reminderPromptSnoozeUntil =
      'reminder_prompt_snooze_until';
  static const String zenModeEnabled = 'zen_mode_enabled';
  static const String consistencyScoreHistory = 'consistency_score_history';
  static const String upNextPackId = 'up_next_pack_id';
  static const String upNextReturnPackId = 'up_next_return_pack_id';
  static const String lastMainTabIndex = 'last_main_tab_index';

  /// Which tab bar wrote [lastMainTabIndex]: absent for Home · Explore ·
  /// Search · Settings, 2 for Home · Explore · Library · Settings, 3 for
  /// Home · Explore · Sounds · Library · You ([MainTab.layout]).
  static const String mainTabLayout = 'main_tab_layout';
  static const String homeWidgetHidden = 'homeWidgetHidden';
  static const String pinnedCourseIds = 'pinned_course_ids';

  /// How the Library tab sorts and lays out what is kept.
  static const String librarySort = 'library_sort';
  static const String libraryLayout = 'library_layout';
  static const String installedVersionHistory = 'installed_version_history';
  static const String onboardingExperienceLevel = 'onboarding_experience_level';
  static const String timerMinutes = 'timer_minutes';
  static const String sessionBellsEnabled = 'session_bells_enabled';
  static const String timerSessionBellsEnabled = 'timer_session_bells_enabled';
}
