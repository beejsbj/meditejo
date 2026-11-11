class TypeConstants {
  static const String link = 'link';
  static const String pack = 'pack';
  static const String track = 'track';
  static const String teacher = 'teacher';
  static const String email = 'email';
  static const String url = 'url';
  static const String flow = 'flow';
  static const String fileIdKey = 'fileId';
  static const String trackIdKey = 'trackId';
  static const String timestampIdKey = 'timestamp';
  static const String guideIdKey = 'guide';
  static const String durationIdKey = 'duration';

  /// Real time a completion took at the speed it was played at; absent from
  /// payloads saved before it was recorded (read as [durationIdKey]).
  static const String realDurationIdKey = 'realDuration';
  static const String downloads = 'downloads';
  static const String customiseHomeLayout = 'customiseHomeLayout';
  static const String route = 'route';
  static const String toggle = 'toggle';
  static const String toggleDnd = 'toggle_dnd';
  static const String toggleStreakFreeze = 'toggle_streak_freeze';
  static const String toggleZenMode = 'toggle_zen_mode';
  static const String theme = 'theme';
  static const String addWidget = 'add_widget';

  /// Deep links that select a tab: `meditejo://library` and so on.
  static const String tabHome = 'home';
  static const String tabExplore = 'explore';
  static const String tabSearch = 'search';
  static const String tabLibrary = 'library';
  static const String tabSettings = 'settings';

  /// `meditejo://sounds` opens the Sounds sheet over Home. Sounds was a tab
  /// before it became a sheet.
  static const String sounds = 'sounds';

  /// `meditejo://you` opens the You page (stats and history) over the tabs.
  /// You was the fifth tab before Settings took its place.
  static const String tabYou = 'you';

  // New constants for path view
  static const String article = 'article';
  static const String session = 'session';
  static const String meditationOutsideApp = 'meditation_outside_app';
  static const String addedManually = 'added_manually';

  // Manual session IDs based on time of day
  static const String manual1 = 'manual1'; // Morning (5:00-11:59)
  static const String manual2 = 'manual2'; // Afternoon (12:00-17:59)
  static const String manual3 = 'manual3'; // Evening (18:00-22:59)
  static const String manual4 = 'manual4'; // Night (23:00-4:59)

  static const String streakFreeze = 'streak-freeze';
}

class RouteConstants {
  static const String stats = 'stats';

  /// The Timer, opened as the Customize sheet.
  static const String timer = 'timer';

  /// The Timer with its length on ∞ (open-ended, counting up): what a link
  /// to the stopwatch means.
  static const String stopwatch = 'stopwatch';
}

class LocaleConstants {
  static const String system = 'system';
  static const String english = 'en';
  static const String spanish = 'es';
  static const String german = 'de';
}
