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

  /// Favourites from before #79, read once to move them into pins and kept
  /// for builds without pins. Nothing writes it any more.
  static const String legacyFavorites = 'favorites';

  /// Set once the favourites have been moved into pins.
  static const String favouritesMigrated = 'favourites_migrated_v1';

  /// Titles kept for pins whose content may be gone, as a JSON map of id to
  /// title (from the favourites they were).
  static const String pinnedTitles = 'pinned_titles';
  static const String localAllStatsKey = 'local_all_stats';
  static const String streakCircleDisplayPreference =
      'streak_circle_display_preference';
  static const String dayBoundaryOffsetHours = 'day_boundary_offset_hours';
  static const String homeWidgetOrder = 'homeWidgetOrder';
  static const String dndEnabled = 'dnd_enabled';
  static const String localePreference = 'locale_preference';
  static const String themePreference = 'theme_preference';

  /// The identity palette: `daily`, or a palette's id. Unset is Tidewater.
  static const String identityPalette = 'identity_palette';

  /// A pinned Home mark, as frozen geometry (`MarkSpec` JSON). Unset is the
  /// daily mark.
  static const String identityPinnedMark = 'identity_pinned_mark';

  /// The local day (`YYYY-MM-DD`) Home's mark was last seen on. A day after
  /// it, Home turns that day's mark into today's, once.
  static const String homeMarkSeenDay = 'home_mark_seen_day';
  static const String dailyReminderEnabled = 'daily_reminder_enabled';
  static const String reminderPromptDismissedForever =
      'reminder_prompt_dismissed_forever';
  static const String notifPermissionFixNeeded = 'notif_permission_fix_needed';
  static const String reminderFlagRepaired = 'reminder_flag_repair_v1';
  static const String reminderPromptSnoozeUntil =
      'reminder_prompt_snooze_until';
  static const String zenModeEnabled = 'zen_mode_enabled';
  static const String autoUpdateCheckEnabled = 'auto_update_check_enabled';
  static const String consistencyScoreHistory = 'consistency_score_history';
  static const String upNextPackId = 'up_next_pack_id';
  static const String upNextReturnPackId = 'up_next_return_pack_id';
  static const String homeWidgetHidden = 'homeWidgetHidden';

  /// Everything pinned to Home, courses and sessions, oldest first.
  static const String pinnedCourseIds = 'pinned_course_ids';

  /// Which of [pinnedCourseIds] are single sessions.
  static const String pinnedSessionIds = 'pinned_session_ids';

  /// Items taken off Home's Continue: `key|millis` each.
  static const String continueDismissed = 'continue_dismissed';

  /// How the Library tab sorts and lays out what is kept.
  static const String librarySort = 'library_sort';
  static const String libraryLayout = 'library_layout';
  static const String installedVersionHistory = 'installed_version_history';

  /// Medito's questionnaire answer. Nothing writes it since #87 removed the
  /// questionnaire; read once so whoever answered it never sees the intro.
  static const String onboardingExperienceLevel = 'onboarding_experience_level';

  /// Set once the first-launch intro ("What Meditejo is") has been left, or
  /// on an install that was in use before the intro existed.
  static const String introSeen = 'intro_seen_v1';

  /// Set once the battery page has been offered after a reminder was turned
  /// on, so it is offered only that once.
  static const String batteryGuidanceOffered = 'battery_guidance_offered_v1';
  static const String timerMinutes = 'timer_minutes';
  static const String sessionBellsEnabled = 'session_bells_enabled';
  static const String timerSessionBellsEnabled = 'timer_session_bells_enabled';

  /// The library items' practices for their covers (`artPractices`), as
  /// JSON, so covers draw the same art from the first frame of a launch.
  static const String artPractices = 'art_practices';
}
