// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get downloads => 'Downloads';

  @override
  String get volume => 'Volume';

  @override
  String get home => 'Home';

  @override
  String get backgroundSoundDownloadFailed =>
      'Couldn\'t download. Tap to try again.';

  @override
  String get none => 'None';

  @override
  String get removed => 'Removed';

  @override
  String get undo => 'Undo';

  @override
  String get reorder => 'Reorder';

  @override
  String get emptyDownloadsMessage =>
      'It looks like you haven\'t downloaded anything yet. Downloads are useful to save mobile data or to access sessions in places without signal.';

  @override
  String get meanWhileListen => 'Meanwhile, you can listen to your';

  @override
  String get retry => 'Retry';

  @override
  String get shareStatsText =>
      'My meditation practice with Meditejo. https://github.com/beejsbj/meditejo';

  @override
  String get backgroundSounds => 'Background Sound';

  @override
  String get searchMeditations => 'Search meditations';

  @override
  String get search => 'Search';

  @override
  String get searchEmptyHint =>
      'Find a pack or a session. Try sleep, anxiety or focus.';

  @override
  String get share => 'Share';

  @override
  String get tapToShare => 'Tap to share';

  @override
  String get id => 'id';

  @override
  String get email => 'email';

  @override
  String get appVersion => 'appVersion';

  @override
  String get buildNumber => 'buildNumber';

  @override
  String get debugInfo => 'Debug info';

  @override
  String get explore => 'Explore';

  @override
  String get thanksForSharing => 'Thanks for sharing  💜';

  @override
  String get thanksForSharingNeutral => 'Neutral face';

  @override
  String get thanksForSharingHappy => 'Happy face';

  @override
  String get thanksForSharingSad => 'Sad face';

  @override
  String get ratingAskTitle => 'Could you leave Meditejo a rating?';

  @override
  String get ratingAskBody =>
      'It only takes a moment, and it helps more people find free meditation.';

  @override
  String get ratingAskCta => 'Rate Meditejo';

  @override
  String get min => 'min';

  @override
  String get someThingWentWrong => 'Something went wrong';

  @override
  String get connectionTimeout => 'Error connection timeout';

  @override
  String get anErrorOccurred =>
      'An unknown error occurred. Either we\'re having issues or you\'re offline.';

  @override
  String get unableToLoadAudio =>
      'Unable to load audio. Please go back and try again';

  @override
  String get timeout =>
      'Oops! It seems like there was an error. If the problem persists, Close the app and try again.';

  @override
  String get howDoYouFeel => 'How do you feel after this session?';

  @override
  String get settings => 'Settings';

  @override
  String get stats => 'Stats';

  @override
  String get history => 'History';

  @override
  String get cancel => 'Cancel';

  @override
  String get healthSyncPermissionDenied =>
      'Health sync is off. You can allow access in Settings whenever you’re ready.';

  @override
  String get syncWithHealth => 'Sync with Apple Health';

  @override
  String get syncWithHealthConnect => 'Sync with Health Connect';

  @override
  String get permissionExplanation =>
      'Permissions set. To change them, go to Settings > Privacy and Security > Health > Meditejo';

  @override
  String get permissionExplanationAndroid =>
      'Permissions set. To change them, open Health Connect from your device settings.';

  @override
  String get healthConnectNotInstalled =>
      'Health Connect is required to sync. Install it from the Play Store?';

  @override
  String get confirmDeletionFromPlayerTitle => 'Already Downloaded';

  @override
  String get confirmDeletionFromPlayerMessage =>
      'This meditation is already in your downloads. Do you want to delete it?';

  @override
  String get delete => 'Delete';

  @override
  String get copy => 'Copy';

  @override
  String get debugInfoCopied => 'Debug info copied to clipboard';

  @override
  String get goToDownloads => 'Go to Downloads';

  @override
  String get backgroundSoundsDisabled =>
      'Background sounds are disabled for this track';

  @override
  String get neww => 'New';

  @override
  String get loading => 'Loading...';

  @override
  String get currentStreak => 'Current Streak';

  @override
  String get longestStreak => 'Longest Streak';

  @override
  String get consistencyScore => 'Consistency Score';

  @override
  String get totalTracksCompleted => 'Total Tracks Completed';

  @override
  String get totalTimeListened => 'Total Time Listened';

  @override
  String get days => 'days';

  @override
  String get day => 'day';

  @override
  String get hours => 'h';

  @override
  String get hoursFull => 'hours';

  @override
  String get hourFull => 'hour';

  @override
  String get minute => 'minute';

  @override
  String get alwaysShowStreakOnHomepage => 'Always show streak on homepage';

  @override
  String get gotIt => 'Got it';

  @override
  String get goBack => 'Go Back';

  @override
  String get editStatsTitle => 'Edit stats';

  @override
  String get path => 'Path';

  @override
  String get completed => 'Completed';

  @override
  String get submit => 'Submit';

  @override
  String get duration => 'Duration';

  @override
  String get monday => 'M';

  @override
  String get tuesday => 'T';

  @override
  String get wednesday => 'W';

  @override
  String get thursday => 'T';

  @override
  String get friday => 'F';

  @override
  String get saturday => 'S';

  @override
  String get sunday => 'S';

  @override
  String get dailyPracticeMessage =>
      'Practicing daily grows your streak, but it also makes you more mindful and happier!';

  @override
  String get dayStreak => 'day streak';

  @override
  String get addToSiri => 'Add to Siri';

  @override
  String get shareTrack => 'Share Track';

  @override
  String get open => 'Open';

  @override
  String shareTrackText(Object link, Object trackName) {
    return 'Take a moment to breathe. Try this meditation session: \"$trackName\" on Meditejo. $link';
  }

  @override
  String sharePackText(Object link, Object packName) {
    return 'Check out $packName on Meditejo! $link #Meditation #Mindfulness';
  }

  @override
  String get invalidDeepLink => 'Invalid deep link';

  @override
  String get deepLinkError => 'Unable to handle deep link';

  @override
  String get shortcutsTitle => 'Shortcuts';

  @override
  String get carouselTitle => 'Featured';

  @override
  String get quoteTitle => 'Daily Quote';

  @override
  String get customization => 'Customisation';

  @override
  String get customiseHomeLayout => 'Organize Home Layout';

  @override
  String get helpLegal => 'Help & Legal';

  @override
  String get advanced => 'Advanced';

  @override
  String get restore => 'Restore';

  @override
  String daysSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days selected',
      one: '1 day selected',
    );
    return '$_temp0';
  }

  @override
  String get newStreak => 'New streak';

  @override
  String get newSessions => 'New sessions';

  @override
  String get addSessionsToSelectedDays => 'Add sessions to selected days';

  @override
  String addSessionsTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count sessions',
      one: 'Add 1 session',
    );
    return '$_temp0';
  }

  @override
  String daysAlreadyHaveSession(int filled, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      filled,
      locale: localeName,
      other:
          '$filled of $total days already have a session and will be skipped.',
      one: '1 of $total days already has a session and will be skipped.',
    );
    return '$_temp0';
  }

  @override
  String get minutesPerDayOptional => 'Minutes per day (optional)';

  @override
  String get onboarding => 'Onboarding';

  @override
  String get enableNotificationsTitle =>
      'Stay on Track with Meditation Reminders';

  @override
  String get enableNotificationsBody =>
      'Enable notifications so you never miss a session.';

  @override
  String get enableNotificationsTitleLearn => 'Keep the learning going';

  @override
  String get enableNotificationsTitleHabit => 'Build the habit you\'re after';

  @override
  String get enableNotificationsTitleStress => 'Make it part of your day';

  @override
  String get notificationPreviewTimestamp => 'now';

  @override
  String get notificationPreviewTitleB => 'A quieter mind starts here';

  @override
  String get notificationPreviewBodyB =>
      'Your daily breath is waiting. Just tap to begin.';

  @override
  String onboardingStepIndicator(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String onboardingReminderCurrentlySet(String time) {
    return 'Daily reminder set for $time';
  }

  @override
  String get reminderChipsQuestion => 'When will you meditate?';

  @override
  String get reminderSlotMorning => 'Morning';

  @override
  String get reminderSlotEvening => 'Evening';

  @override
  String get reminderSlotNight => 'Night';

  @override
  String get reminderSlotCustom => 'Pick my own time';

  @override
  String get notificationsBlockedTitle => 'Notifications are turned off';

  @override
  String get notificationsBlockedBody =>
      'Meditejo can\'t send reminders because notifications are switched off for the app in your phone\'s settings. You can switch them back on there.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get turnOnInSettings => 'Turn On in Settings';

  @override
  String get notificationsBlockedSubtitle => 'Switched off in phone settings';

  @override
  String get reminderPrimerTitle => 'One quick thing';

  @override
  String get reminderPrimerBody =>
      'Your phone will ask you to allow notifications next. Say yes so that we can send you a daily nudge to meditate.';

  @override
  String get reminderPrimerContinue => 'Continue';

  @override
  String get reminderCustomCancelled =>
      'No time picked yet — choose one above, or skip for now.';

  @override
  String get reminderTitle => 'Daily reminder';

  @override
  String get reminderOff => 'Off';

  @override
  String get reminderTurnOff => 'Turn off reminders';

  @override
  String get onboardingBatteryTitle => 'One Setting, Smoother Meditations';

  @override
  String get onboardingBatteryBody =>
      'Your phone can pause Meditejo mid-session. One quick change prevents this.';

  @override
  String get onboardingBatteryOptimize => 'Update Setting';

  @override
  String get skipForNow => 'Skip for Now';

  @override
  String get skip => 'Skip';

  @override
  String get notNow => 'Not Now';

  @override
  String get errorNoInternetMessage => 'No internet connection';

  @override
  String get errorTimeoutMessage => 'Connection timed out';

  @override
  String get errorNotFoundMessage => 'Content not found';

  @override
  String get errorServerMessage => 'Server error, please try again later';

  @override
  String get errorUnknownMessage => 'Something went wrong, please try again';

  @override
  String get enableDndDuringMeditation => 'Silence phone during meditation';

  @override
  String get zenMode => 'Zen Mode';

  @override
  String get zenModeEnabledMessage => 'Stats will be hidden throughout the app';

  @override
  String get zenModeOn => 'On';

  @override
  String get zenModeOff => 'Off';

  @override
  String get zenModeOffDescription =>
      'Show your streak, stats and consistency score.';

  @override
  String get zenModeOnDescription =>
      'Hide your streak, stats and consistency score everywhere in the app.';

  @override
  String get zenModeFootnote => 'Your progress is recorded either way.';

  @override
  String get dndOn => 'On';

  @override
  String get dndOff => 'Off';

  @override
  String get dndOnDescription =>
      'Turn on Do Not Disturb while a session plays and turn it off again when it ends. Alarms still sound.';

  @override
  String get dndOffDescription =>
      'Leave your phone\'s notifications as they are during sessions.';

  @override
  String get dndFootnote =>
      'Needs Do Not Disturb access on Android. Meditejo only changes it during a session.';

  @override
  String get dndAccessTitle => 'Allow Do Not Disturb access';

  @override
  String get dndAccessBody =>
      'To silence your phone during meditation, Android needs to give Meditejo Do Not Disturb access. On the next screen, find Meditejo in the list and turn it on, then come back to the app.';

  @override
  String get currency => 'Currency';

  @override
  String get custom => 'Custom Amount';

  @override
  String get impactCardHelpMessage =>
      'Help millions worldwide access free meditation';

  @override
  String get impactCardTestimonial =>
      '\"Medito pulled me through a seriously dark period in my life\" - Medito meditator';

  @override
  String get favorites => 'Favorites';

  @override
  String get noFavoriteTracksYet => 'No favorite tracks yet';

  @override
  String get noFavoritePacksYet => 'No favorite packs yet';

  @override
  String get noFavoritesYet => 'No favorites yet';

  @override
  String get addItemsToFavoritesMessage =>
      'Add items to your favorites to see them here';

  @override
  String get all => 'All';

  @override
  String get tracks => 'Tracks';

  @override
  String get packs => 'Packs';

  @override
  String get noResultsFound => 'No results found for your search';

  @override
  String get consistencyScoreInfoTitle => 'Consistency Score';

  @override
  String get consistencyScoreInfoMessage =>
      'Your consistency score reflects how regularly you\'ve meditated since you started. Recent days carry more weight, but earlier missed days still gently affect the score. Unlike streaks, it doesn\'t reset on a missed day.';

  @override
  String get systemLanguage => 'System';

  @override
  String get english => 'English';

  @override
  String get german => 'Deutsch';

  @override
  String get spanish => 'Español (beta)';

  @override
  String get helpLegalSection => 'Help';

  @override
  String get customizationSection => 'Customisation';

  @override
  String get addHomeScreenWidget => 'Add Home Screen Widget';

  @override
  String get addWidgetSheetTitle => 'Add a Meditejo widget';

  @override
  String get addWidgetStepHold =>
      'Touch and hold an empty spot on your Home Screen until the apps jiggle.';

  @override
  String get addWidgetStepEdit =>
      'Tap Edit in the top corner, then Add Widget. On older iOS versions, tap +.';

  @override
  String get addWidgetStepSearch =>
      'Search for Meditejo and choose Streak, Consistency or Continue.';

  @override
  String get addWidgetStepAdd => 'Tap Add Widget, then Done.';

  @override
  String get addWidgetFootnote =>
      'Your widget updates after every meditation. For your Lock Screen, touch and hold it, then tap Customise and Add Widgets.';

  @override
  String get themeTitle => 'Theme';

  @override
  String get appIconTitle => 'App Icon';

  @override
  String get appIconNearBlack => 'Dark';

  @override
  String get appIconDusk => 'Dusk';

  @override
  String get appIconPurple => 'Purple';

  @override
  String get appIconClassic => 'Classic';

  @override
  String get appIconBlush => 'Blush';

  @override
  String get appIconOcean => 'Ocean';

  @override
  String get appIconForest => 'Forest';

  @override
  String get appIconPink => 'Golden';

  @override
  String get appIconChanged => 'Icon updated. Restarting…';

  @override
  String get systemTheme => 'System';

  @override
  String get systemThemeDescription => 'Follows your device setting';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get selectTheme => 'Select Theme';

  @override
  String get dailyReminders => 'Daily Reminders';

  @override
  String get turnOnReminders => 'Turn on reminders';

  @override
  String get reminderPromptDismissedMessage =>
      'You can turn reminders on or off in Settings';

  @override
  String get reminderDay1TitleVar1 => 'Keep your streak going 🌱';

  @override
  String reminderDay1BodyVar1(String streak) {
    return 'You are on a $streak day streak. Keep it going?';
  }

  @override
  String get reminderDay1TitleVar2 => 'Strong step ✨';

  @override
  String reminderDay1BodyVar2(String consistency) {
    return 'Consistency $consistency%. Let’s keep it going.';
  }

  @override
  String get reminderDay1TitleVar3 => 'Tiny wins add up 💜';

  @override
  String get reminderDay1BodyVar3 =>
      'A few minutes now keeps your momentum alive.';

  @override
  String get reminderDay1TitleVar4 => 'Your practice awaits 🌸';

  @override
  String get reminderDay1BodyVar4 =>
      'Take a moment to reconnect with yourself.';

  @override
  String get reminderDay1TitleVar5 => 'One breath at a time 🫧';

  @override
  String get reminderDay1BodyVar5 =>
      'Every session counts, no matter how short.';

  @override
  String get reminderDay2TitleVar1 => 'Keep the flow 🔁';

  @override
  String get reminderDay2BodyVar1 =>
      'Let’s get that streak going again. Just a few minutes can make a big difference.';

  @override
  String get reminderDay2TitleVar2 => 'Build your rhythm 🧘';

  @override
  String get reminderDay2BodyVar2 => 'Another gentle practice awaits.';

  @override
  String get reminderDay2TitleVar3 => 'You have got this 🌟';

  @override
  String get reminderDay2BodyVar3 =>
      'Return to your breath, one moment at a time.';

  @override
  String get reminderDay2TitleVar4 => 'Small steps forward 🚶';

  @override
  String get reminderDay2BodyVar4 =>
      'Consistency builds strength. Start with just a few minutes.';

  @override
  String get reminderDay2TitleVar5 => 'Gentle return 💚';

  @override
  String get reminderDay2BodyVar5 =>
      'Your mindful practice is here whenever you are ready.';

  @override
  String get reminderDay3TitleVar1 => 'Build the habit 📆';

  @override
  String get reminderDay3BodyVar1 => 'Momentum matters. You have got this.';

  @override
  String get reminderDay3TitleVar2 => 'Three day spark ✴️';

  @override
  String get reminderDay3BodyVar2 => 'Your practice is taking shape.';

  @override
  String get reminderDay3TitleVar3 => 'A gentle nudge 🤍';

  @override
  String get reminderDay3BodyVar3 => 'Two mindful minutes is enough.';

  @override
  String get reminderDay3TitleVar4 => 'Growing stronger 🌿';

  @override
  String get reminderDay3BodyVar4 =>
      'Each day you practice, you build something meaningful.';

  @override
  String get reminderDay3TitleVar5 => 'Find your calm 🕊️';

  @override
  String get reminderDay3BodyVar5 => 'A brief pause can reset your entire day.';

  @override
  String get reminderDay4Title => 'Small steps 🪴';

  @override
  String get reminderDay4Body =>
      'It has been 4 days since you meditated. Resume your practice with a short session.';

  @override
  String get reminderDay5Title => 'Time to reconnect 💪';

  @override
  String get reminderDay5Body =>
      'It has been 5 days. A calm pause now can help you get back on track.';

  @override
  String get reminderDay6Title => 'Almost a week ⏰';

  @override
  String get reminderDay6Body =>
      'It has been almost a week since you meditated. Close the loop with a mindful moment.';

  @override
  String get reminderDay7Title => 'One week check in 📅';

  @override
  String get reminderDay7Body =>
      'It has been a week since you meditated. Take a moment for yourself now.';

  @override
  String get reminderDay8Title => 'Fresh start 🌤️';

  @override
  String get reminderDay8Body =>
      'It has been over a week. A fresh start with just a few mindful minutes.';

  @override
  String get reminderDay9Title => 'Find your centre 🎯';

  @override
  String get reminderDay9Body => 'A short session can reset your day.';

  @override
  String get reminderDay10Title => 'Double digits 🔟';

  @override
  String get reminderDay10Body =>
      'It has been 10 days since you meditated. Pick up where you left off.';

  @override
  String get reminderDay11Title => 'Gentle nudge 🤍';

  @override
  String get reminderDay11Body => 'Pause, breathe, and notice how you feel.';

  @override
  String get reminderDay12Title => 'Keep steady 🧭';

  @override
  String get reminderDay12Body => 'A calm moment is waiting for you.';

  @override
  String get reminderDay13Title => 'Approaching two weeks ⏳';

  @override
  String get reminderDay13Body =>
      'It has been almost two weeks since you meditated. Try a two minute restart.';

  @override
  String get reminderDay14Title => 'Two week check in 🔔';

  @override
  String get reminderDay14Body =>
      'It has been 14 days since you meditated. Resume your practice now, gently.';

  @override
  String get reminderDay15Title => 'Pausing reminders 🌿';

  @override
  String get reminderDay15Body =>
      'We\'re pausing reminders for now. We are here whenever you are ready.';

  @override
  String get reminderDay30Title => 'A gentle nudge 🤗';

  @override
  String get reminderDay30Body =>
      'It\'s been a month since you meditated. Just 2 minutes can help you feel better. We\'re here when you\'re ready.';

  @override
  String get repeatModeOnce => 'Repeat Once';

  @override
  String get repeatModeForever => 'Repeat Forever';

  @override
  String get repeatModeOff => 'Off';

  @override
  String get repeatModeOffDescription => 'Play once, then finish.';

  @override
  String get repeatModeOnceDescription => 'Play it twice, then finish.';

  @override
  String get repeatModeForeverDescription => 'Keep playing until you stop it.';

  @override
  String get addSession => 'Add Session';

  @override
  String get deleteSessionTitle => 'Delete Session';

  @override
  String get deleteSessionConfirmation =>
      'Are you sure you want to delete this session? This will update your streak and stats.';

  @override
  String get deleteSessionError => 'Failed to delete session.';

  @override
  String get time => 'Time';

  @override
  String get singleDay => 'Single day';

  @override
  String get dateRange => 'Date range';

  @override
  String get startDate => 'Start date';

  @override
  String get endDate => 'End date';

  @override
  String get endDateBeforeStartError =>
      'End date must be on or after the start date';

  @override
  String get selectTime => 'Select time';

  @override
  String get minutes => 'Minutes';

  @override
  String get optional => 'Optional';

  @override
  String get morningMeditation => 'Morning meditation';

  @override
  String get afternoonMeditation => 'Afternoon meditation';

  @override
  String get eveningMeditation => 'Evening meditation';

  @override
  String get nightMeditation => 'Night meditation';

  @override
  String get add => 'Add';

  @override
  String get manuallyAddedSession => 'Manually added session';

  @override
  String get addSessionExplanation =>
      'If you\'ve done a meditation session outside the app, you can add it here to track it in your stats.';

  @override
  String get cannotAddFutureSession => 'Cannot add sessions in the future';

  @override
  String get completedAt => 'Completed at';

  @override
  String get upNextTitle => 'Continue';

  @override
  String upNextProgress(int completed, int total) {
    return '$completed of $total';
  }

  @override
  String upNextPackCompletedTitle(String packTitle) {
    return 'You finished $packTitle';
  }

  @override
  String upNextPackCompletedSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions complete',
      one: '1 session complete',
    );
    return '$_temp0';
  }

  @override
  String get upNextPackCompletedCta => 'Start the next pack';

  @override
  String upNextPackCompletedCtaNamed(String packTitle) {
    return 'Start $packTitle';
  }

  @override
  String get upNextPathCompletedTitle =>
      'You\'ve finished every pack in the series';

  @override
  String get upNextPathCompletedSubtitle =>
      'Explore the library to find what\'s next.';

  @override
  String upNextNextPackPinnedSnack(String packTitle) {
    return '$packTitle is ready on Home';
  }

  @override
  String get manageDefaults => 'Manage Defaults';

  @override
  String get defaultGuideName => 'Default Guide Name';

  @override
  String get defaultDuration => 'Default Duration';

  @override
  String get defaultGuideNameCleared => 'Default guide name cleared';

  @override
  String get notSet => 'Not set';

  @override
  String get defaultsNote =>
      'These defaults are set from your last selection on any track. Home uses them to skip the selection screen when you continue a pack.';

  @override
  String get streakFreezeUsed => 'Streak freeze used';

  @override
  String get session => 'session';

  @override
  String get sessions => 'sessions';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get skipBackward10Seconds => 'Skip back 10 seconds';

  @override
  String get skipForward10Seconds => 'Skip forward 10 seconds';

  @override
  String get repeat => 'Repeat';

  @override
  String get close => 'Close';

  @override
  String get downloadAudio => 'Download audio';

  @override
  String get deleteDownload => 'Delete download';

  @override
  String get playbackSpeed => 'Playback speed';

  @override
  String get speedReset => 'Reset';

  @override
  String get backgroundSoundsSection => 'Sounds';

  @override
  String get viewStreak => 'View streak';

  @override
  String get refresh => 'Refresh';

  @override
  String get upNext => 'Continue';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get clearDefault => 'Clear default guide';

  @override
  String get onboardingExperienceQuestion => 'Have you meditated before?';

  @override
  String get onboardingExperienceSubtext =>
      'This helps us show you the right starting point.';

  @override
  String get onboardingExperienceNever => 'Never tried it';

  @override
  String get onboardingExperienceALittle => 'A little, here and there';

  @override
  String get onboardingExperienceRegular => 'I have a regular practice';

  @override
  String get onboardingResultCta => 'Get started';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get addedToFavorites => 'Added to Favorites';

  @override
  String get removedFromFavorites => 'Removed from Favorites';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get openPack => 'Open pack';

  @override
  String get yourPathAllDone => 'All sessions done';

  @override
  String get markAllComplete => 'Mark all complete';

  @override
  String get markAllIncomplete => 'Mark all incomplete';

  @override
  String get markTrackComplete => 'Mark complete';

  @override
  String get markTrackIncomplete => 'Mark incomplete';

  @override
  String get tagSleep => 'Sleep';

  @override
  String get tagStress => 'Stress';

  @override
  String get tagAnxiety => 'Anxiety';

  @override
  String get tagLowMood => 'Low mood';

  @override
  String get tagFocus => 'Focus';

  @override
  String get tagCalm => 'Calm';

  @override
  String get tagSelfCompassion => 'Self-compassion';

  @override
  String get tagGratitude => 'Gratitude';

  @override
  String get tagEmotions => 'Difficult emotions';

  @override
  String get tagPain => 'Pain';

  @override
  String get tagConfidence => 'Confidence';

  @override
  String get tagRelationships => 'Relationships';

  @override
  String get tagGrief => 'Grief';

  @override
  String get tagHabitBuilding => 'Habit building';

  @override
  String get tagBreathing => 'Breathing';

  @override
  String get tagBodyScan => 'Body scan';

  @override
  String get tagLovingKindness => 'Loving-kindness';

  @override
  String get tagOpenAwareness => 'Open awareness';

  @override
  String get tagVisualization => 'Visualisation';

  @override
  String get tagMantra => 'Mantra';

  @override
  String get tagWalking => 'Walking';

  @override
  String get tagReflection => 'Reflection';

  @override
  String get tagSound => 'Sound';

  @override
  String get tagGuidedMeditation => 'Guided meditation';

  @override
  String get tagTalk => 'Talks';

  @override
  String get tagSleepStory => 'Sleep stories';

  @override
  String get tagMusic => 'Music';

  @override
  String get tagNatureSounds => 'Nature sounds';

  @override
  String get tagCourseLesson => 'Course lessons';

  @override
  String get tagBeginners => 'For beginners';

  @override
  String get tagExperienced => 'Experienced';

  @override
  String get tagTeensStudents => 'Teens & students';

  @override
  String get tagTeachers => 'Teachers';

  @override
  String get tagWorkplace => 'Work';

  @override
  String get tagKids => 'Kids';

  @override
  String get tagMorning => 'Morning';

  @override
  String get tagEvening => 'Evening';

  @override
  String get tagSos => 'SOS';

  @override
  String get tagOnTheGo => 'On the go';

  @override
  String get tagCrisis => 'Times of crisis';

  @override
  String get tagSpanish => 'Español';

  @override
  String get tagNoTracks => 'No sessions with this tag yet';

  @override
  String get sessionBells => 'Session bells';

  @override
  String get sessionBellsDescription =>
      'A bell at the beginning, middle and end';

  @override
  String get upNextStartHere => 'Start here';

  @override
  String get removeFromHomeShort => 'Remove';

  @override
  String get removeFromHome => 'Remove from Home';

  @override
  String get removedFromHome => 'Removed from Home.';

  @override
  String get packStart => 'Start';

  @override
  String get packContinue => 'Resume';

  @override
  String get packAddedToHome =>
      'Added to Home so you can pick up where you left off.';

  @override
  String get timerTitle => 'Timer';

  @override
  String get timerModeStopwatch => 'Stopwatch';

  @override
  String get timerHoursLabel => 'Hours';

  @override
  String get timerMinutesLabel => 'Minutes';

  @override
  String get timerStopwatchCaption =>
      'The time counts up from zero. Tap stop when you\'re done and the session is saved.';

  @override
  String get timerStart => 'Start';

  @override
  String get timerEndSession => 'End session';

  @override
  String get timerElapsed => 'elapsed';

  @override
  String get timerTooShort => 'Sessions under a minute aren\'t saved';

  @override
  String timerHistoryTitle(String duration) {
    return 'Timer · $duration';
  }

  @override
  String timerPresetSemantics(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get soundNeedsConnection => 'Not downloaded. Connect to play';

  @override
  String get timerStopwatchTitle => 'Sit for as long as you like';

  @override
  String get openTimer => 'Open timer';

  @override
  String get downloadingAudio => 'Downloading';

  @override
  String get playbackPosition => 'Playback position';

  @override
  String playbackPositionValue(String position, String duration) {
    return '$position of $duration';
  }

  @override
  String get dayMeditated => 'Meditated';

  @override
  String get dayNotMeditated => 'Not meditated';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String searchResultsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count results',
      one: '1 result',
    );
    return '$_temp0';
  }

  @override
  String get clearField => 'Clear';

  @override
  String get externalLink => 'External link';

  @override
  String get meditatedToday => 'Meditated today';

  @override
  String get endScreenDone => 'Done';

  @override
  String endScreenRestoredLastNight(String title) {
    return 'Welcome back. You finished “$title” last night.';
  }

  @override
  String endScreenRestoredEarlierToday(String title) {
    return 'Welcome back. You finished “$title” earlier today.';
  }

  @override
  String endScreenRestoredYesterday(String title) {
    return 'Welcome back. You finished “$title” yesterday.';
  }

  @override
  String endScreenRestoredTimerLastNight(int minutes) {
    return 'Welcome back. You finished a $minutes-minute timer last night.';
  }

  @override
  String endScreenRestoredTimerEarlierToday(int minutes) {
    return 'Welcome back. You finished a $minutes-minute timer earlier today.';
  }

  @override
  String endScreenRestoredTimerYesterday(int minutes) {
    return 'Welcome back. You finished a $minutes-minute timer yesterday.';
  }

  @override
  String get localHomeHeading => 'Time to sit.';

  @override
  String get localIntroBeginHeading => 'A little time to begin.';

  @override
  String get localIntroReturnHeading => 'Ease back into your practice.';

  @override
  String get localIntroPracticeHeading => 'Space for your practice.';

  @override
  String get localIntroBeginBody =>
      'Find a comfortable seat, set a short timer, and notice your breath. When your attention wanders, gently begin again.';

  @override
  String get localIntroReturnBody =>
      'Start with a few quiet minutes. The timer is ready whenever you are.';

  @override
  String get localIntroPracticeBody =>
      'Use the timer for an unguided sit, with the bells and duration you prefer.';

  @override
  String get localIntroDeviceOnlyNote =>
      'Your practice history, favourites and settings stay on this device.';

  @override
  String get aboutMeditejo => 'About Meditejo';

  @override
  String get forkCredit =>
      'Meditejo is based on Medito by the Medito Foundation (meditofoundation.org), licensed under AGPL-3.0.';

  @override
  String get sourceCode => 'Source code';

  @override
  String get upstreamProject => 'Upstream project';

  @override
  String get dharmaSeedLibrary => 'Dharma Seed library';

  @override
  String dharmaSeedSyncProgress(String what, int done, int total) {
    return 'Updating $what: $done of $total';
  }

  @override
  String get dharmaSeedTeachers => 'teachers';

  @override
  String get dharmaSeedRetreats => 'retreats';

  @override
  String get dharmaSeedTalks => 'talks';

  @override
  String dharmaSeedUpToDate(String when) {
    return 'Up to date · $when';
  }

  @override
  String get dharmaSeedNeverSynced => 'Not synced yet. Tap to sync.';

  @override
  String dharmaSeedSyncFailed(String error) {
    return 'Sync paused ($error). Tap to retry.';
  }

  @override
  String get exploreKindPractice => 'Practice';

  @override
  String get exploreKindTalks => 'Talks';

  @override
  String get exploreSavedCourses => 'Saved courses';

  @override
  String get exploreSavedTeachers => 'Saved teachers';

  @override
  String get exploreCourses => 'Courses';

  @override
  String get exploreTeachers => 'Teachers';

  @override
  String get exploreLatestPractice => 'Latest guided practice';

  @override
  String get exploreLatestTalks => 'Latest talks';

  @override
  String get exploreSyncingTitle => 'Setting up your Dharma Seed library';

  @override
  String get exploreSyncingBody =>
      'Courses and teachers appear here as they arrive. The first time takes a minute or two.';

  @override
  String get exploreNoLibraryTitle => 'The library is not synced yet';

  @override
  String get exploreNoLibraryBody =>
      'Connect to the internet and pull down to try again.';

  @override
  String get exploreNothingInGroup =>
      'Nothing here yet. More arrives as the library syncs.';

  @override
  String get searchDharmaHint => 'Search teachers, courses and talks';

  @override
  String get searchTryHint => 'Try a teacher, a theme or a retreat';

  @override
  String get searchTeachers => 'Teachers';

  @override
  String get searchCourses => 'Courses';

  @override
  String get searchTalks => 'Talks';

  @override
  String get searchTalkLength => 'Talk length';

  @override
  String get searchLengthAny => 'Any';

  @override
  String get searchLengthUnder10 => 'Under 10 min';

  @override
  String get searchLength10to20 => '10–20 min';

  @override
  String get searchLength20to30 => '20–30 min';

  @override
  String get searchLength30to45 => '30–45 min';

  @override
  String get searchLengthOver45 => 'Over 45 min';

  @override
  String courseLeft(int count, int total) {
    return '$count of $total left';
  }

  @override
  String courseAllPlayed(int total) {
    return 'All $total played';
  }

  @override
  String get courseSave => 'Add to library';

  @override
  String get courseSaved => 'In library';

  @override
  String get courseSessionsTab => 'Sessions';

  @override
  String get courseSummaryTab => 'Summary';

  @override
  String get courseTeacherTab => 'Teacher';

  @override
  String get courseNoSummary => 'This course has no written summary.';

  @override
  String courseDay(int number) {
    return 'Day $number';
  }

  @override
  String get courseSessionDownloaded => 'Downloaded';

  @override
  String courseSessionLength(int minutes) {
    return '$minutes min';
  }

  @override
  String get teacherSave => 'Add to library';

  @override
  String get teacherCourses => 'Courses';

  @override
  String get teacherTalks => 'Talks';

  @override
  String get teacherShowMore => 'Show more talks';

  @override
  String get teacherNotFound => 'This teacher is not in the library yet.';

  @override
  String get teacherNoBio => 'No biography on Dharma Seed.';

  @override
  String get teacherWebsite => 'Website';

  @override
  String attributionViewOn(String source) {
    return 'View on $source';
  }

  @override
  String get attributionUnmodified => 'Streamed as recorded, unmodified.';

  @override
  String attributionLicence(String license) {
    return 'Licence: $license';
  }

  @override
  String teacherTalkCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count talks',
      one: '1 talk',
    );
    return '$_temp0';
  }

  @override
  String teacherCourseCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count courses',
      one: '1 course',
    );
    return '$_temp0';
  }

  @override
  String aboutVersion(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateUpToDate => 'Up to date';

  @override
  String updateLastChecked(String when) {
    return 'Last checked $when';
  }

  @override
  String updateAvailable(String version) {
    return 'Update available: $version';
  }

  @override
  String get updateAction => 'Update';

  @override
  String get updateWhatsNew => 'What\'s new';

  @override
  String updateDownloading(int percent) {
    return 'Downloading… $percent%';
  }

  @override
  String get updateVerifying => 'Checking the download…';

  @override
  String get updateInstalling => 'Handing it to Android…';

  @override
  String get updatePermissionExplanation =>
      'To install updates, Android needs “Install unknown apps” switched on for Meditejo. The next screen is Android’s own; switch it on, then come back here and the update will continue.';

  @override
  String get updatePermissionWaiting =>
      'Waiting for “Install unknown apps”. Switch it on for Meditejo, then come back.';

  @override
  String get updateOpenSettings => 'Open settings';

  @override
  String get updateTryAgain => 'Try again';

  @override
  String get updateErrorOffline =>
      'Couldn’t reach GitHub. Check your connection and try again.';

  @override
  String get updateErrorRateLimited =>
      'GitHub is asking for a pause. Try again in an hour or so.';

  @override
  String get updateErrorUnavailable =>
      'The update information isn’t available right now. Try again later.';

  @override
  String get updateErrorDownload =>
      'The download didn’t finish. Try again when you’re ready.';

  @override
  String get updateErrorHash =>
      'The download doesn’t match what was published, so it wasn’t installed. Try downloading it again.';

  @override
  String get updateErrorSignature =>
      'This file wasn’t signed with Meditejo’s key, so it wasn’t installed.';

  @override
  String get updateErrorNotMeditejo =>
      'This file isn’t the Meditejo update it should be, so it wasn’t installed.';

  @override
  String get updateErrorInstall => 'Android couldn’t install the update.';

  @override
  String homeUpdateNotice(String version) {
    return 'Meditejo $version is available';
  }

  @override
  String get homeUpdateView => 'View';

  @override
  String get homeUpdateDismiss => 'Dismiss';

  @override
  String get libraryTitle => 'Your library';

  @override
  String get libraryAdd => 'Add';

  @override
  String get libraryPractice => 'Practice';

  @override
  String get libraryTalks => 'Talks';

  @override
  String get libraryTeachers => 'Teachers';

  @override
  String get librarySeeAll => 'See all';

  @override
  String get libraryEmptyTitle => 'Your library is empty';

  @override
  String get libraryEmptyBody =>
      'Add a course, a talk or a recording from a link or a file.';

  @override
  String get libraryEmptyHome =>
      'Paste a link, share one from another app, or pick a file.';

  @override
  String get libraryMoveToPractice => 'Move to Practice';

  @override
  String get libraryMoveToTalks => 'Move to Talks';

  @override
  String get libraryRename => 'Rename';

  @override
  String get libraryRemove => 'Remove from library';

  @override
  String get libraryRemoveTitle => 'Remove from your library?';

  @override
  String get libraryRemoveImported =>
      'The audio copied to this device for it will be deleted.';

  @override
  String get libraryRemoveCatalogue =>
      'It stays in Explore, and you can add it again.';

  @override
  String get libraryRenameTitle => 'Rename';

  @override
  String get libraryRenameHint => 'Name in your library';

  @override
  String get libraryRenameSave => 'Save';

  @override
  String librarySessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get libraryAddedSnack => 'Added to your library';

  @override
  String get libraryAlreadyIn => 'Already in your library';

  @override
  String get libraryOpen => 'Open';

  @override
  String get libraryRemovedSnack => 'Removed from your library';

  @override
  String get libraryAddToLibrary => 'Add to library';

  @override
  String get libraryInLibrary => 'In library';

  @override
  String libraryResumeAt(String position) {
    return 'Resume at $position';
  }

  @override
  String get importTitle => 'Add to your library';

  @override
  String get importFieldHint => 'Paste a link';

  @override
  String get importHelp =>
      'Dharma Seed pages, podcast feeds, audio links, or files on your phone.';

  @override
  String get importPaste => 'Paste';

  @override
  String get importPreviewAction => 'Preview';

  @override
  String importClipboard(String host) {
    return 'Link on your clipboard: $host';
  }

  @override
  String get importUseClipboard => 'Use';

  @override
  String get importChooseFiles => 'Choose files';

  @override
  String get importChooseFolder => 'Choose a folder';

  @override
  String get importLooking => 'Looking at the link…';

  @override
  String get importPrimary => 'Add to library';

  @override
  String get importAdding => 'Adding…';

  @override
  String get importKindCourse => 'Course';

  @override
  String get importKindSingle => 'Single';

  @override
  String importCaptionCourseAll(int count) {
    return 'All $count episodes, in order';
  }

  @override
  String get importCaptionLatest =>
      'Just one episode: the latest, or one you pick';

  @override
  String get importCaptionFilesCourse => 'One course, in the order shown';

  @override
  String get importCaptionFilesSingles => 'Each file on its own';

  @override
  String get importCountsAs => 'Counts as';

  @override
  String get importGroupPractice => 'Practice';

  @override
  String get importGroupTalk => 'Talk';

  @override
  String get importOrderOldest => 'Oldest first';

  @override
  String get importOrderNewest => 'Newest first';

  @override
  String importAtLeast(String duration) {
    return 'at least $duration';
  }

  @override
  String importSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items without audio were left out',
      one: '1 item without audio was left out',
    );
    return '$_temp0';
  }

  @override
  String get importInLibraryNote => 'This is already in your library.';

  @override
  String get importDefaultTitle => 'Imported audio';

  @override
  String get importTitleLabel => 'Name';

  @override
  String get importFailEmpty => 'Paste a link or choose a file to begin.';

  @override
  String get importFailUnrecognised =>
      'That doesn\'t look like a link or file I can use. Try an address that starts with https://.';

  @override
  String get importFailUnsupportedHost =>
      'Links from that service can\'t be imported. For a podcast, look for its feed address, or its page on Apple Podcasts.';

  @override
  String get importFailOffline =>
      'Couldn\'t reach that address. Check your connection and try again.';

  @override
  String get importFailNotFound =>
      'That page wasn\'t found. Check the link and try again.';

  @override
  String get importFailUnreachable =>
      'That site couldn\'t give us what we asked for. Try again later.';

  @override
  String get importFailNoFeed =>
      'That page has no podcast feed or audio file I can find. If you have the feed address (often ending in .xml or /feed), paste that instead.';

  @override
  String get importFailNoEpisodes => 'This feed has no audio episodes.';

  @override
  String get importFailBrokenFeed =>
      'This feed couldn\'t be read. It may be damaged or not a podcast feed.';

  @override
  String get importFailDharmaSeed =>
      'Dharma Seed doesn\'t have that, or couldn\'t be reached just now.';

  @override
  String get importFailFile => 'That file couldn\'t be found.';

  @override
  String get importFailNoAudio => 'No audio files found there.';

  @override
  String get importFailAdd => 'Couldn\'t add that. Please try again.';

  @override
  String get importEpisodeLabel => 'Episode';

  @override
  String get importEpisodeChange => 'Change';

  @override
  String get importEpisodePickerTitle => 'Choose an episode';

  @override
  String get importEpisodeSearch => 'Search episodes';

  @override
  String get importEpisodeNone => 'No episode matches that.';

  @override
  String get importEpisodeLatest => 'Latest';

  @override
  String get importFolderLooking => 'Looking in the folder…';

  @override
  String importFolderCopying(int done, int total) {
    return 'Copying $done of $total…';
  }

  @override
  String get importFolderCancel => 'Cancel';

  @override
  String importUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items couldn\'t be read and were left out',
      one: '1 item couldn\'t be read and was left out',
    );
    return '$_temp0';
  }

  @override
  String get importFailFolderEmpty => 'That folder is empty.';

  @override
  String get importFailFolderTooLarge =>
      'That folder holds more than 1,000 audio files. Choose a smaller one.';

  @override
  String get importFailFolderNoSpace =>
      'There isn\'t enough free space on this phone to copy that folder.';

  @override
  String get importFailFolderUnreadable =>
      'That folder couldn\'t be read. Try choosing it again, or choose files instead.';

  @override
  String get importFailFolderUnavailable =>
      'This device has no folder picker. Choose files instead.';

  @override
  String get shareArrived => 'Shared with Meditejo';

  @override
  String get exploreLibraryHeading => 'In your library';

  @override
  String get libraryFromStart => 'From the beginning';

  @override
  String get libraryCheckNew => 'Check for new episodes';

  @override
  String get youtubeUnavailable => 'This video isn\'t available right now';

  @override
  String get youtubeCourseCaption => 'All sessions, in playlist order';

  @override
  String get youtubeSingleCaption => 'Just this video';

  @override
  String get youtubeOffline => 'You\'re offline. Connect to play this video';

  @override
  String get youtubePlaylistOffline =>
      'You\'re offline. Connect to load this playlist';

  @override
  String get youtubePlaylistUnavailable =>
      'This playlist isn\'t available right now';

  @override
  String get youtubeAgeRestricted => 'This video is age-restricted';

  @override
  String get youtubePlaylistAgeRestricted =>
      'This playlist contains age-restricted videos';

  @override
  String get youtubePrivate => 'This video is private';

  @override
  String get youtubePlaylistPrivate => 'This playlist is private';

  @override
  String get youtubeRateLimited =>
      'YouTube is busy or asking for a bot check. Try again later';

  @override
  String get youtubePlaylistEmpty =>
      'Sessions aren\'t stored on this device yet. We\'ll try again shortly';

  @override
  String get navLibrary => 'Library';

  @override
  String get exploreSearchHint => 'Search your library and Dharma Seed';

  @override
  String get homeQuickLinksTitle => 'Quick links';

  @override
  String get homePinnedTitle => 'Pinned courses';

  @override
  String get homeCustomize => 'Customize';

  @override
  String get homeCustomizeHint =>
      'Switch sections on or off, and drag to put them in your order.';

  @override
  String get homeContinueEmpty =>
      'Nothing in progress. Add something to your library, or open Explore.';

  @override
  String get homeContinueResume => 'Resume';

  @override
  String get homeContinueStart => 'Start';

  @override
  String homeContinueSessionOf(int number, int total) {
    return 'Session $number of $total';
  }

  @override
  String homeContinueTimeLeft(String time) {
    return '$time left';
  }

  @override
  String get homeQuickAdd => 'Add';

  @override
  String homeQuickPresetTimer(String preset) {
    return 'Start the timer with $preset';
  }

  @override
  String get pinCourse => 'Pin to Home';

  @override
  String get unpinCourse => 'Unpin from Home';

  @override
  String get pinnedLimitReached =>
      'Home holds up to three pinned courses. Unpin one first.';

  @override
  String get pinnedCourseAdded => 'Pinned to Home';

  @override
  String get statsFeedbackNote => 'These numbers are feedback, not a score.';

  @override
  String get soundsYourMix => 'Your mix';

  @override
  String get soundsEmptyMix => 'Tap a sound below to start a mix.';

  @override
  String soundsLayerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sounds',
      one: '1 sound',
    );
    return '$_temp0';
  }

  @override
  String get soundsPlay => 'Play';

  @override
  String get soundsPause => 'Pause';

  @override
  String get soundsStop => 'Stop';

  @override
  String soundsRemove(String sound) {
    return 'Remove $sound';
  }

  @override
  String get soundsDrift => 'Drift';

  @override
  String get soundsDriftHint => 'Let the level rise and fall slowly';

  @override
  String get soundsPresets => 'Presets';

  @override
  String get soundsSavePreset => 'Save mix';

  @override
  String get soundsPresetName => 'Preset name';

  @override
  String soundsPresetSaved(String name) {
    return 'Saved “$name”';
  }

  @override
  String soundsDeletePreset(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get soundsDelete => 'Delete';

  @override
  String get soundsCancel => 'Cancel';

  @override
  String get soundsSave => 'Save';

  @override
  String soundsLayerLimit(int count) {
    return 'A mix holds up to $count sounds';
  }

  @override
  String get soundsCouldNotPlay => 'This sound could not be played';

  @override
  String get soundsUnderSessions => 'Under sessions';

  @override
  String get soundsUnderPractice => 'Play under practice';

  @override
  String get soundsUnderTalks => 'Play under talks';

  @override
  String get soundsUnderSessionsHint =>
      'Your mix plays beneath the session, at its own volume';

  @override
  String get soundsCredits => 'Sound credits';

  @override
  String get soundsNotificationText => 'Playing your mix';

  @override
  String get soundCategoryRain => 'Rain';

  @override
  String get soundCategoryWater => 'Water';

  @override
  String get soundCategoryWind => 'Wind';

  @override
  String get soundCategoryForest => 'Forest and birds';

  @override
  String get soundCategoryFire => 'Fire';

  @override
  String get soundCategoryRoom => 'Rooms and city';

  @override
  String get soundCategoryNight => 'Night';

  @override
  String get soundPresetRainForest => 'Rain on the forest';

  @override
  String get soundPresetNight => 'Night';

  @override
  String get soundPresetHearth => 'Hearth';

  @override
  String get soundPresetShore => 'Shore';

  @override
  String get soundCreditsIntro =>
      'These recordings are shared by their authors under their own licences, not the app’s AGPL. Each was cut to a loop, crossfaded, levelled and re-encoded for Meditejo.';

  @override
  String soundCreditsBy(String original, String author) {
    return '“$original” by $author';
  }

  @override
  String soundCreditsChanges(String changes) {
    return 'Changes: $changes';
  }

  @override
  String get soundCreditsAttributionRequired => 'Attribution required';

  @override
  String get soundCategoryGenerated => 'Generated';

  @override
  String get synthNoise => 'Noise';

  @override
  String get synthDrone => 'Drone';

  @override
  String get synthBinaural => 'Binaural beats';

  @override
  String synthAdjust(String sound) {
    return 'Adjust $sound';
  }

  @override
  String get noiseColour => 'Colour';

  @override
  String get noiseWhite => 'White';

  @override
  String get noisePink => 'Pink';

  @override
  String get noiseBrown => 'Brown';

  @override
  String get noiseBands => 'Bands';

  @override
  String get noiseReset => 'Reset bands';

  @override
  String get droneRoot => 'Root';

  @override
  String get droneTimbre => 'Timbre';

  @override
  String get dronePure => 'Pure';

  @override
  String get droneWarm => 'Warm';

  @override
  String get droneBright => 'Bright';

  @override
  String get droneMovement => 'Movement';

  @override
  String get binauralCarrier => 'Tone';

  @override
  String get binauralBeat => 'Beat';

  @override
  String get binauralHeadphones =>
      'Binaural beats need headphones: each ear hears its own tone.';

  @override
  String get soundPresetStillness => 'Stillness';

  @override
  String get myCourseNew => 'New course';

  @override
  String get myCourseNameHint => 'Course name';

  @override
  String get myCourseCreate => 'Create';

  @override
  String get myCourseDefaultTitle => 'My course';

  @override
  String get myCourseAddTo => 'Add to course…';

  @override
  String get myCourseAddToTitle => 'Add to course';

  @override
  String myCourseAddedSnack(String title) {
    return 'Added to $title';
  }

  @override
  String myCourseAddedCountSnack(int count, String title) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions added to $title',
      one: '1 session added to $title',
    );
    return '$_temp0';
  }

  @override
  String myCourseAlreadyIn(String title) {
    return 'Already in $title';
  }

  @override
  String get myCourseNothingToAdd => 'There are no sessions to add.';

  @override
  String get myCourseAddFailed => 'Could not add it to the course.';

  @override
  String get myCourseNoneYet =>
      'You haven\'t made a course yet. Start one here.';

  @override
  String get myCourseDuplicate => 'Make my own copy';

  @override
  String myCourseCopyTitle(String title) {
    return '$title (my copy)';
  }

  @override
  String get myCourseDuplicateFailed => 'Could not copy this course.';

  @override
  String get myCourseSaveFailed => 'Could not save the course.';

  @override
  String get myCourseEdit => 'Edit course';

  @override
  String get myCourseSave => 'Save';

  @override
  String get myCourseTitleLabel => 'Title';

  @override
  String get myCourseDescriptionLabel => 'Description (optional)';

  @override
  String get myCourseKindLabel => 'Kind';

  @override
  String get myCourseCoverLabel => 'Cover';

  @override
  String get myCourseCoverGenerated => 'Generated cover';

  @override
  String myCourseCoverChoice(int index) {
    return 'Cover $index';
  }

  @override
  String get myCourseSessionsLabel => 'Sessions';

  @override
  String get myCourseAddHeading => 'Add heading';

  @override
  String get myCourseHeadingHint => 'Heading, e.g. Day 1';

  @override
  String get myCourseRemoveRow => 'Remove from course';

  @override
  String get myCourseDragHandle => 'Drag to reorder';

  @override
  String get myCourseEditEmpty =>
      'No sessions yet. Use Add to course… in any session\'s menu.';

  @override
  String get myCourseDiscardTitle => 'Discard your changes?';

  @override
  String get myCourseDiscard => 'Discard';

  @override
  String get myCourseKeepEditing => 'Keep editing';

  @override
  String get myCourseDelete => 'Delete course';

  @override
  String get myCourseDeleteTitle => 'Delete this course?';

  @override
  String get myCourseDeleteBody =>
      'Only the course goes. Its sessions stay in your library, with their downloads and progress.';

  @override
  String get myCourseDeletedSnack => 'Course deleted';

  @override
  String get myCourseEmptyTitle => 'No sessions yet';

  @override
  String get myCourseEmptyBody =>
      'Add sessions from anywhere: a Dharma Seed talk, a YouTube video, an episode or a file. Open its menu and choose Add to course…';

  @override
  String get myCourseUnavailable => 'Unavailable';

  @override
  String get myCourseUnavailableSnack =>
      'This session is no longer available from its source.';

  @override
  String myCourseRemoveWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'It is also in $count of your courses, where it will show as unavailable.',
      one:
          'It is also in one of your courses, where it will show as unavailable.',
    );
    return '$_temp0';
  }

  @override
  String get myCourseMore => 'More options';

  @override
  String get myCourseRemovedSnack => 'Removed from the course';

  @override
  String get myCourseEditAction => 'Edit';

  @override
  String get navYou => 'You';

  @override
  String get soundsMixEmptyTitle => 'Nothing in your mix yet';

  @override
  String get soundsMixEmptyHint => 'Tap a sound or a preset to start a mix.';

  @override
  String soundsMute(String sound) {
    return 'Mute $sound';
  }

  @override
  String soundsUnmute(String sound) {
    return 'Unmute $sound';
  }

  @override
  String get soundsShowMix => 'Show your mix';

  @override
  String get soundsHideMix => 'Hide your mix';

  @override
  String get soundsMixVolume => 'Mix volume';

  @override
  String soundsPlayPreset(String name) {
    return 'Play $name';
  }

  @override
  String get soundsPresetPlaying => 'Playing';

  @override
  String get soundsAdjust => 'Adjust';

  @override
  String get soundsEditMix => 'Edit your mix in Sounds';
}
