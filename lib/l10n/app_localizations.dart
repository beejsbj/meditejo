import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @backgroundSoundDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download. Tap to try again.'**
  String get backgroundSoundDownloadFailed;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get removed;

  /// Snackbar action that reverses the removal just made
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Accessibility label for a drag handle that reorders a list item
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @emptyDownloadsMessage.
  ///
  /// In en, this message translates to:
  /// **'It looks like you haven\'t downloaded anything yet. Downloads are useful to save mobile data or to access sessions in places without signal.'**
  String get emptyDownloadsMessage;

  /// No description provided for @meanWhileListen.
  ///
  /// In en, this message translates to:
  /// **'Meanwhile, you can listen to your'**
  String get meanWhileListen;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @shareStatsText.
  ///
  /// In en, this message translates to:
  /// **'My meditation practice with Meditejo. https://github.com/beejsbj/meditejo'**
  String get shareStatsText;

  /// No description provided for @backgroundSounds.
  ///
  /// In en, this message translates to:
  /// **'Background Sound'**
  String get backgroundSounds;

  /// No description provided for @searchMeditations.
  ///
  /// In en, this message translates to:
  /// **'Search meditations'**
  String get searchMeditations;

  /// Label of the search button in the floating navigation bar
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Shown on the search page before anything is typed
  ///
  /// In en, this message translates to:
  /// **'Find a pack or a session. Try sleep, anxiety or focus.'**
  String get searchEmptyHint;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @tapToShare.
  ///
  /// In en, this message translates to:
  /// **'Tap to share'**
  String get tapToShare;

  /// No description provided for @id.
  ///
  /// In en, this message translates to:
  /// **'id'**
  String get id;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'email'**
  String get email;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'appVersion'**
  String get appVersion;

  /// No description provided for @buildNumber.
  ///
  /// In en, this message translates to:
  /// **'buildNumber'**
  String get buildNumber;

  /// No description provided for @debugInfo.
  ///
  /// In en, this message translates to:
  /// **'Debug info'**
  String get debugInfo;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @thanksForSharing.
  ///
  /// In en, this message translates to:
  /// **'Thanks for sharing  💜'**
  String get thanksForSharing;

  /// No description provided for @thanksForSharingNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral face'**
  String get thanksForSharingNeutral;

  /// No description provided for @thanksForSharingHappy.
  ///
  /// In en, this message translates to:
  /// **'Happy face'**
  String get thanksForSharingHappy;

  /// No description provided for @thanksForSharingSad.
  ///
  /// In en, this message translates to:
  /// **'Sad face'**
  String get thanksForSharingSad;

  /// Title of the one-time ask for a store rating, shown on the end screen after the user taps the happy face
  ///
  /// In en, this message translates to:
  /// **'Could you leave Meditejo a rating?'**
  String get ratingAskTitle;

  /// No description provided for @ratingAskBody.
  ///
  /// In en, this message translates to:
  /// **'It only takes a moment, and it helps more people find free meditation.'**
  String get ratingAskBody;

  /// Button that opens the App Store / Play Store review page
  ///
  /// In en, this message translates to:
  /// **'Rate Meditejo'**
  String get ratingAskCta;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get min;

  /// No description provided for @someThingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get someThingWentWrong;

  /// No description provided for @connectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Error connection timeout'**
  String get connectionTimeout;

  /// No description provided for @anErrorOccurred.
  ///
  /// In en, this message translates to:
  /// **'An unknown error occurred. Either we\'re having issues or you\'re offline.'**
  String get anErrorOccurred;

  /// No description provided for @unableToLoadAudio.
  ///
  /// In en, this message translates to:
  /// **'Unable to load audio. Please go back and try again'**
  String get unableToLoadAudio;

  /// No description provided for @timeout.
  ///
  /// In en, this message translates to:
  /// **'Oops! It seems like there was an error. If the problem persists, Close the app and try again.'**
  String get timeout;

  /// No description provided for @howDoYouFeel.
  ///
  /// In en, this message translates to:
  /// **'How do you feel after this session?'**
  String get howDoYouFeel;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @healthSyncPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Health sync is off. You can allow access in Settings whenever you’re ready.'**
  String get healthSyncPermissionDenied;

  /// No description provided for @syncWithHealth.
  ///
  /// In en, this message translates to:
  /// **'Sync with Apple Health'**
  String get syncWithHealth;

  /// No description provided for @syncWithHealthConnect.
  ///
  /// In en, this message translates to:
  /// **'Sync with Health Connect'**
  String get syncWithHealthConnect;

  /// No description provided for @permissionExplanation.
  ///
  /// In en, this message translates to:
  /// **'Permissions set. To change them, go to Settings > Privacy and Security > Health > Meditejo'**
  String get permissionExplanation;

  /// No description provided for @permissionExplanationAndroid.
  ///
  /// In en, this message translates to:
  /// **'Permissions set. To change them, open Health Connect from your device settings.'**
  String get permissionExplanationAndroid;

  /// No description provided for @healthConnectNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Health Connect is required to sync. Install it from the Play Store?'**
  String get healthConnectNotInstalled;

  /// No description provided for @confirmDeletionFromPlayerTitle.
  ///
  /// In en, this message translates to:
  /// **'Already Downloaded'**
  String get confirmDeletionFromPlayerTitle;

  /// No description provided for @confirmDeletionFromPlayerMessage.
  ///
  /// In en, this message translates to:
  /// **'This meditation is already in your downloads. Do you want to delete it?'**
  String get confirmDeletionFromPlayerMessage;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @debugInfoCopied.
  ///
  /// In en, this message translates to:
  /// **'Debug info copied to clipboard'**
  String get debugInfoCopied;

  /// No description provided for @goToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Go to Downloads'**
  String get goToDownloads;

  /// No description provided for @backgroundSoundsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Background sounds are disabled for this track'**
  String get backgroundSoundsDisabled;

  /// No description provided for @neww.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get neww;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @currentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current Streak'**
  String get currentStreak;

  /// No description provided for @longestStreak.
  ///
  /// In en, this message translates to:
  /// **'Longest Streak'**
  String get longestStreak;

  /// No description provided for @consistencyScore.
  ///
  /// In en, this message translates to:
  /// **'Consistency Score'**
  String get consistencyScore;

  /// No description provided for @totalTracksCompleted.
  ///
  /// In en, this message translates to:
  /// **'Total Tracks Completed'**
  String get totalTracksCompleted;

  /// No description provided for @totalTimeListened.
  ///
  /// In en, this message translates to:
  /// **'Total Time Listened'**
  String get totalTimeListened;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get day;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get hours;

  /// No description provided for @hoursFull.
  ///
  /// In en, this message translates to:
  /// **'hours'**
  String get hoursFull;

  /// No description provided for @hourFull.
  ///
  /// In en, this message translates to:
  /// **'hour'**
  String get hourFull;

  /// No description provided for @minute.
  ///
  /// In en, this message translates to:
  /// **'minute'**
  String get minute;

  /// No description provided for @alwaysShowStreakOnHomepage.
  ///
  /// In en, this message translates to:
  /// **'Always show streak on homepage'**
  String get alwaysShowStreakOnHomepage;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @editStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit stats'**
  String get editStatsTitle;

  /// No description provided for @path.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get path;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get duration;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'M'**
  String get monday;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'T'**
  String get tuesday;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get wednesday;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'T'**
  String get thursday;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get friday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get saturday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get sunday;

  /// No description provided for @dailyPracticeMessage.
  ///
  /// In en, this message translates to:
  /// **'Practicing daily grows your streak, but it also makes you more mindful and happier!'**
  String get dailyPracticeMessage;

  /// No description provided for @dayStreak.
  ///
  /// In en, this message translates to:
  /// **'day streak'**
  String get dayStreak;

  /// No description provided for @addToSiri.
  ///
  /// In en, this message translates to:
  /// **'Add to Siri'**
  String get addToSiri;

  /// No description provided for @shareTrack.
  ///
  /// In en, this message translates to:
  /// **'Share Track'**
  String get shareTrack;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @shareTrackText.
  ///
  /// In en, this message translates to:
  /// **'Take a moment to breathe. Try this meditation session: \"{trackName}\" on Meditejo. {link}'**
  String shareTrackText(Object link, Object trackName);

  /// No description provided for @sharePackText.
  ///
  /// In en, this message translates to:
  /// **'Check out {packName} on Meditejo! {link} #Meditation #Mindfulness'**
  String sharePackText(Object link, Object packName);

  /// No description provided for @invalidDeepLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid deep link'**
  String get invalidDeepLink;

  /// No description provided for @deepLinkError.
  ///
  /// In en, this message translates to:
  /// **'Unable to handle deep link'**
  String get deepLinkError;

  /// No description provided for @shortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get shortcutsTitle;

  /// No description provided for @carouselTitle.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get carouselTitle;

  /// No description provided for @quoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Quote'**
  String get quoteTitle;

  /// No description provided for @customization.
  ///
  /// In en, this message translates to:
  /// **'Customisation'**
  String get customization;

  /// No description provided for @customiseHomeLayout.
  ///
  /// In en, this message translates to:
  /// **'Organize Home Layout'**
  String get customiseHomeLayout;

  /// No description provided for @helpLegal.
  ///
  /// In en, this message translates to:
  /// **'Help & Legal'**
  String get helpLegal;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @daysSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day selected} other{{count} days selected}}'**
  String daysSelected(int count);

  /// No description provided for @newStreak.
  ///
  /// In en, this message translates to:
  /// **'New streak'**
  String get newStreak;

  /// No description provided for @newSessions.
  ///
  /// In en, this message translates to:
  /// **'New sessions'**
  String get newSessions;

  /// No description provided for @addSessionsToSelectedDays.
  ///
  /// In en, this message translates to:
  /// **'Add sessions to selected days'**
  String get addSessionsToSelectedDays;

  /// No description provided for @addSessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Add 1 session} other{Add {count} sessions}}'**
  String addSessionsTitle(int count);

  /// No description provided for @daysAlreadyHaveSession.
  ///
  /// In en, this message translates to:
  /// **'{filled, plural, =1{1 of {total} days already has a session and will be skipped.} other{{filled} of {total} days already have a session and will be skipped.}}'**
  String daysAlreadyHaveSession(int filled, int total);

  /// No description provided for @minutesPerDayOptional.
  ///
  /// In en, this message translates to:
  /// **'Minutes per day (optional)'**
  String get minutesPerDayOptional;

  /// Title for the onboarding section in settings
  ///
  /// In en, this message translates to:
  /// **'Onboarding'**
  String get onboarding;

  /// No description provided for @enableNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay on Track with Meditation Reminders'**
  String get enableNotificationsTitle;

  /// No description provided for @enableNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications so you never miss a session.'**
  String get enableNotificationsBody;

  /// Notifications screen title for users who want to learn to meditate (intent: learn_properly)
  ///
  /// In en, this message translates to:
  /// **'Keep the learning going'**
  String get enableNotificationsTitleLearn;

  /// Notifications screen title for users who want to build a habit (intent: build_habit)
  ///
  /// In en, this message translates to:
  /// **'Build the habit you\'re after'**
  String get enableNotificationsTitleHabit;

  /// Notifications screen title for users managing stress, sleep, or emotions (intent: stress_sleep_emotions)
  ///
  /// In en, this message translates to:
  /// **'Make it part of your day'**
  String get enableNotificationsTitleStress;

  /// Timestamp shown on a fake iOS notification preview, mirroring iOS's 'now' label for a notification that just arrived
  ///
  /// In en, this message translates to:
  /// **'now'**
  String get notificationPreviewTimestamp;

  /// Title of the fake notification shown in the onboarding notifications screen preview
  ///
  /// In en, this message translates to:
  /// **'A quieter mind starts here'**
  String get notificationPreviewTitleB;

  /// Body of the fake notification shown in the onboarding notifications screen preview
  ///
  /// In en, this message translates to:
  /// **'Your daily breath is waiting. Just tap to begin.'**
  String get notificationPreviewBodyB;

  /// Progress label under the onboarding pages, next to the circular progress ring
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String onboardingStepIndicator(int current, int total);

  /// Shown on the onboarding reminder screen when a reminder is already set, above the chips that let the user change it
  ///
  /// In en, this message translates to:
  /// **'Daily reminder set for {time}'**
  String onboardingReminderCurrentlySet(String time);

  /// Question above the time-of-day chips in the onboarding notifications screen (chips arm of the reminder experiment)
  ///
  /// In en, this message translates to:
  /// **'When will you meditate?'**
  String get reminderChipsQuestion;

  /// Time-of-day chip label; shown with a concrete time, e.g. 'Morning · 7:00 AM'
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get reminderSlotMorning;

  /// Time-of-day chip label; shown with a concrete time, e.g. 'Evening · 8:00 PM'
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get reminderSlotEvening;

  /// Time-of-day chip label; shown with a concrete time, e.g. 'Night · 10:00 PM'
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get reminderSlotNight;

  /// Option below the time-of-day chips that opens a time picker
  ///
  /// In en, this message translates to:
  /// **'Pick my own time'**
  String get reminderSlotCustom;

  /// Title of the dialog shown when notification permission is permanently denied, so no OS prompt can be raised and the phone's settings are the only route
  ///
  /// In en, this message translates to:
  /// **'Notifications are turned off'**
  String get notificationsBlockedTitle;

  /// Body of the dialog shown when notification permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Meditejo can\'t send reminders because notifications are switched off for the app in your phone\'s settings. You can switch them back on there.'**
  String get notificationsBlockedBody;

  /// Button that opens the phone's settings app on the Meditejo page
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Call to action replacing 'Turn on Daily reminders' when notification permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Turn On in Settings'**
  String get turnOnInSettings;

  /// Subtitle on the settings daily-reminder tile when notification permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Switched off in phone settings'**
  String get notificationsBlockedSubtitle;

  /// Title of the confirmation dialog shown before the OS notification permission prompt on the end-screen reminder card
  ///
  /// In en, this message translates to:
  /// **'One quick thing'**
  String get reminderPrimerTitle;

  /// Body of the confirmation dialog shown before the OS notification permission prompt
  ///
  /// In en, this message translates to:
  /// **'Your phone will ask you to allow notifications next. Say yes so that we can send you a daily nudge to meditate.'**
  String get reminderPrimerBody;

  /// Button on the pre-permission dialog that proceeds to the OS notification permission prompt
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get reminderPrimerContinue;

  /// Feedback shown when the user opens the custom time picker and dismisses it without choosing, so the tap is not a silent dead end
  ///
  /// In en, this message translates to:
  /// **'No time picked yet — choose one above, or skip for now.'**
  String get reminderCustomCancelled;

  /// Title of the settings tile that opens the reminder time bottom sheet (replaced the Daily reminders switch)
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get reminderTitle;

  /// Subtitle on the settings reminder tile when no daily reminder is scheduled
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get reminderOff;

  /// Last row of the reminder time bottom sheet; cancels the scheduled reminders
  ///
  /// In en, this message translates to:
  /// **'Turn off reminders'**
  String get reminderTurnOff;

  /// No description provided for @onboardingBatteryTitle.
  ///
  /// In en, this message translates to:
  /// **'One Setting, Smoother Meditations'**
  String get onboardingBatteryTitle;

  /// No description provided for @onboardingBatteryBody.
  ///
  /// In en, this message translates to:
  /// **'Your phone can pause Meditejo mid-session. One quick change prevents this.'**
  String get onboardingBatteryBody;

  /// No description provided for @onboardingBatteryOptimize.
  ///
  /// In en, this message translates to:
  /// **'Update Setting'**
  String get onboardingBatteryOptimize;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for Now'**
  String get skipForNow;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get notNow;

  /// No description provided for @errorNoInternetMessage.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get errorNoInternetMessage;

  /// No description provided for @errorTimeoutMessage.
  ///
  /// In en, this message translates to:
  /// **'Connection timed out'**
  String get errorTimeoutMessage;

  /// No description provided for @errorNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'Content not found'**
  String get errorNotFoundMessage;

  /// No description provided for @errorServerMessage.
  ///
  /// In en, this message translates to:
  /// **'Server error, please try again later'**
  String get errorServerMessage;

  /// No description provided for @errorUnknownMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong, please try again'**
  String get errorUnknownMessage;

  /// No description provided for @enableDndDuringMeditation.
  ///
  /// In en, this message translates to:
  /// **'Silence phone during meditation'**
  String get enableDndDuringMeditation;

  /// Title for zen mode setting in customization section
  ///
  /// In en, this message translates to:
  /// **'Zen Mode'**
  String get zenMode;

  /// Message shown when zen mode is enabled
  ///
  /// In en, this message translates to:
  /// **'Stats will be hidden throughout the app'**
  String get zenModeEnabledMessage;

  /// Zen Mode state label; button in the sheet and subtitle on the settings row
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get zenModeOn;

  /// Zen Mode state label; button in the sheet and subtitle on the settings row
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get zenModeOff;

  /// Description under the Off option in the Zen Mode sheet
  ///
  /// In en, this message translates to:
  /// **'Show your streak, stats and consistency score.'**
  String get zenModeOffDescription;

  /// Description under the On option in the Zen Mode sheet
  ///
  /// In en, this message translates to:
  /// **'Hide your streak, stats and consistency score everywhere in the app.'**
  String get zenModeOnDescription;

  /// Small note under the Zen Mode options
  ///
  /// In en, this message translates to:
  /// **'Your progress is recorded either way.'**
  String get zenModeFootnote;

  /// State label for 'Silence phone during meditation'; option in the sheet and subtitle on the settings row
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get dndOn;

  /// State label for 'Silence phone during meditation'; option in the sheet and subtitle on the settings row
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get dndOff;

  /// Description under the On option in the silence-phone sheet
  ///
  /// In en, this message translates to:
  /// **'Turn on Do Not Disturb while a session plays and turn it off again when it ends. Alarms still sound.'**
  String get dndOnDescription;

  /// Description under the Off option in the silence-phone sheet
  ///
  /// In en, this message translates to:
  /// **'Leave your phone\'s notifications as they are during sessions.'**
  String get dndOffDescription;

  /// Small note under the silence-phone options explaining the Android permission
  ///
  /// In en, this message translates to:
  /// **'Needs Do Not Disturb access on Android. Meditejo only changes it during a session.'**
  String get dndFootnote;

  /// Title of the dialog shown when the user turns on silence-phone without the Android permission
  ///
  /// In en, this message translates to:
  /// **'Allow Do Not Disturb access'**
  String get dndAccessTitle;

  /// Body of the dialog explaining the Android Do Not Disturb access permission before opening system settings
  ///
  /// In en, this message translates to:
  /// **'To silence your phone during meditation, Android needs to give Meditejo Do Not Disturb access. On the next screen, find Meditejo in the list and turn it on, then come back to the app.'**
  String get dndAccessBody;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom Amount'**
  String get custom;

  /// No description provided for @impactCardHelpMessage.
  ///
  /// In en, this message translates to:
  /// **'Help millions worldwide access free meditation'**
  String get impactCardHelpMessage;

  /// No description provided for @impactCardTestimonial.
  ///
  /// In en, this message translates to:
  /// **'\"Medito pulled me through a seriously dark period in my life\" - Medito meditator'**
  String get impactCardTestimonial;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @noFavoriteTracksYet.
  ///
  /// In en, this message translates to:
  /// **'No favorite tracks yet'**
  String get noFavoriteTracksYet;

  /// No description provided for @noFavoritePacksYet.
  ///
  /// In en, this message translates to:
  /// **'No favorite packs yet'**
  String get noFavoritePacksYet;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @addItemsToFavoritesMessage.
  ///
  /// In en, this message translates to:
  /// **'Add items to your favorites to see them here'**
  String get addItemsToFavoritesMessage;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @tracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get tracks;

  /// No description provided for @packs.
  ///
  /// In en, this message translates to:
  /// **'Packs'**
  String get packs;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found for your search'**
  String get noResultsFound;

  /// No description provided for @consistencyScoreInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Consistency Score'**
  String get consistencyScoreInfoTitle;

  /// No description provided for @consistencyScoreInfoMessage.
  ///
  /// In en, this message translates to:
  /// **'Your consistency score reflects how regularly you\'ve meditated since you started. Recent days carry more weight, but earlier missed days still gently affect the score. Unlike streaks, it doesn\'t reset on a missed day.'**
  String get consistencyScoreInfoMessage;

  /// No description provided for @systemLanguage.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get german;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Español (beta)'**
  String get spanish;

  /// Section title for help settings
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get helpLegalSection;

  /// Section title for customization settings
  ///
  /// In en, this message translates to:
  /// **'Customisation'**
  String get customizationSection;

  /// Title for adding home screen widget option in customization section
  ///
  /// In en, this message translates to:
  /// **'Add Home Screen Widget'**
  String get addHomeScreenWidget;

  /// Title of the iOS sheet explaining how to add a home screen widget
  ///
  /// In en, this message translates to:
  /// **'Add a Meditejo widget'**
  String get addWidgetSheetTitle;

  /// Step 1 of adding an iOS home screen widget
  ///
  /// In en, this message translates to:
  /// **'Touch and hold an empty spot on your Home Screen until the apps jiggle.'**
  String get addWidgetStepHold;

  /// Step 2 of adding an iOS home screen widget; Edit / Add Widget are iOS button labels
  ///
  /// In en, this message translates to:
  /// **'Tap Edit in the top corner, then Add Widget. On older iOS versions, tap +.'**
  String get addWidgetStepEdit;

  /// Step 3; Streak, Consistency and Continue are the iOS widget gallery names (English-only in the widget extension), keep them untranslated
  ///
  /// In en, this message translates to:
  /// **'Search for Meditejo and choose Streak, Consistency or Continue.'**
  String get addWidgetStepSearch;

  /// Step 4; Add Widget / Done are iOS button labels
  ///
  /// In en, this message translates to:
  /// **'Tap Add Widget, then Done.'**
  String get addWidgetStepAdd;

  /// Footnote under the add-widget steps
  ///
  /// In en, this message translates to:
  /// **'Your widget updates after every meditation. For your Lock Screen, touch and hold it, then tap Customise and Add Widgets.'**
  String get addWidgetFootnote;

  /// Title for theme selection setting in customization section
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get themeTitle;

  /// Title for app icon selection setting in customization section
  ///
  /// In en, this message translates to:
  /// **'App Icon'**
  String get appIconTitle;

  /// Label for the near-black app icon option
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appIconNearBlack;

  /// Label for the dusk gradient app icon option (now the default)
  ///
  /// In en, this message translates to:
  /// **'Dusk'**
  String get appIconDusk;

  /// Label for the original purple app icon option
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get appIconPurple;

  /// Label for the classic app icon option (purple M on white)
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get appIconClassic;

  /// Label for the blush pink gradient app icon option
  ///
  /// In en, this message translates to:
  /// **'Blush'**
  String get appIconBlush;

  /// Label for the ocean blue gradient app icon option
  ///
  /// In en, this message translates to:
  /// **'Ocean'**
  String get appIconOcean;

  /// Label for the forest green gradient app icon option
  ///
  /// In en, this message translates to:
  /// **'Forest'**
  String get appIconForest;

  /// Label for the pink-to-gold sunset gradient app icon option
  ///
  /// In en, this message translates to:
  /// **'Golden'**
  String get appIconPink;

  /// Snackbar message shown on Android after changing the app icon
  ///
  /// In en, this message translates to:
  /// **'Icon updated. Restarting…'**
  String get appIconChanged;

  /// System theme option that follows device settings
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// Description under the System option in the theme sheet
  ///
  /// In en, this message translates to:
  /// **'Follows your device setting'**
  String get systemThemeDescription;

  /// Light theme option
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// Dark theme option
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// Dialog title for theme selection
  ///
  /// In en, this message translates to:
  /// **'Select Theme'**
  String get selectTheme;

  /// Label for the daily reminders opt-in card on the end screen
  ///
  /// In en, this message translates to:
  /// **'Daily Reminders'**
  String get dailyReminders;

  /// Button text to enable daily reminders
  ///
  /// In en, this message translates to:
  /// **'Turn on reminders'**
  String get turnOnReminders;

  /// Message shown when user dismisses the reminder prompt on the end screen
  ///
  /// In en, this message translates to:
  /// **'You can turn reminders on or off in Settings'**
  String get reminderPromptDismissedMessage;

  /// Daily reminder day 1 title variant 1
  ///
  /// In en, this message translates to:
  /// **'Keep your streak going 🌱'**
  String get reminderDay1TitleVar1;

  /// Daily reminder day 1 body variant 1
  ///
  /// In en, this message translates to:
  /// **'You are on a {streak} day streak. Keep it going?'**
  String reminderDay1BodyVar1(String streak);

  /// Daily reminder day 1 title variant 2
  ///
  /// In en, this message translates to:
  /// **'Strong step ✨'**
  String get reminderDay1TitleVar2;

  /// Daily reminder day 1 body variant 2
  ///
  /// In en, this message translates to:
  /// **'Consistency {consistency}%. Let’s keep it going.'**
  String reminderDay1BodyVar2(String consistency);

  /// Daily reminder day 1 title variant 3
  ///
  /// In en, this message translates to:
  /// **'Tiny wins add up 💜'**
  String get reminderDay1TitleVar3;

  /// Daily reminder day 1 body variant 3
  ///
  /// In en, this message translates to:
  /// **'A few minutes now keeps your momentum alive.'**
  String get reminderDay1BodyVar3;

  /// Daily reminder day 1 title variant 4
  ///
  /// In en, this message translates to:
  /// **'Your practice awaits 🌸'**
  String get reminderDay1TitleVar4;

  /// Daily reminder day 1 body variant 4
  ///
  /// In en, this message translates to:
  /// **'Take a moment to reconnect with yourself.'**
  String get reminderDay1BodyVar4;

  /// Daily reminder day 1 title variant 5
  ///
  /// In en, this message translates to:
  /// **'One breath at a time 🫧'**
  String get reminderDay1TitleVar5;

  /// Daily reminder day 1 body variant 5
  ///
  /// In en, this message translates to:
  /// **'Every session counts, no matter how short.'**
  String get reminderDay1BodyVar5;

  /// Daily reminder day 2 title variant 1
  ///
  /// In en, this message translates to:
  /// **'Keep the flow 🔁'**
  String get reminderDay2TitleVar1;

  /// Daily reminder day 2 body variant 1
  ///
  /// In en, this message translates to:
  /// **'Let’s get that streak going again. Just a few minutes can make a big difference.'**
  String get reminderDay2BodyVar1;

  /// Daily reminder day 2 title variant 2
  ///
  /// In en, this message translates to:
  /// **'Build your rhythm 🧘'**
  String get reminderDay2TitleVar2;

  /// Daily reminder day 2 body variant 2
  ///
  /// In en, this message translates to:
  /// **'Another gentle practice awaits.'**
  String get reminderDay2BodyVar2;

  /// Daily reminder day 2 title variant 3
  ///
  /// In en, this message translates to:
  /// **'You have got this 🌟'**
  String get reminderDay2TitleVar3;

  /// Daily reminder day 2 body variant 3
  ///
  /// In en, this message translates to:
  /// **'Return to your breath, one moment at a time.'**
  String get reminderDay2BodyVar3;

  /// Daily reminder day 2 title variant 4
  ///
  /// In en, this message translates to:
  /// **'Small steps forward 🚶'**
  String get reminderDay2TitleVar4;

  /// Daily reminder day 2 body variant 4
  ///
  /// In en, this message translates to:
  /// **'Consistency builds strength. Start with just a few minutes.'**
  String get reminderDay2BodyVar4;

  /// Daily reminder day 2 title variant 5
  ///
  /// In en, this message translates to:
  /// **'Gentle return 💚'**
  String get reminderDay2TitleVar5;

  /// Daily reminder day 2 body variant 5
  ///
  /// In en, this message translates to:
  /// **'Your mindful practice is here whenever you are ready.'**
  String get reminderDay2BodyVar5;

  /// Daily reminder day 3 title variant 1
  ///
  /// In en, this message translates to:
  /// **'Build the habit 📆'**
  String get reminderDay3TitleVar1;

  /// Daily reminder day 3 body variant 1
  ///
  /// In en, this message translates to:
  /// **'Momentum matters. You have got this.'**
  String get reminderDay3BodyVar1;

  /// Daily reminder day 3 title variant 2
  ///
  /// In en, this message translates to:
  /// **'Three day spark ✴️'**
  String get reminderDay3TitleVar2;

  /// Daily reminder day 3 body variant 2
  ///
  /// In en, this message translates to:
  /// **'Your practice is taking shape.'**
  String get reminderDay3BodyVar2;

  /// Daily reminder day 3 title variant 3
  ///
  /// In en, this message translates to:
  /// **'A gentle nudge 🤍'**
  String get reminderDay3TitleVar3;

  /// Daily reminder day 3 body variant 3
  ///
  /// In en, this message translates to:
  /// **'Two mindful minutes is enough.'**
  String get reminderDay3BodyVar3;

  /// Daily reminder day 3 title variant 4
  ///
  /// In en, this message translates to:
  /// **'Growing stronger 🌿'**
  String get reminderDay3TitleVar4;

  /// Daily reminder day 3 body variant 4
  ///
  /// In en, this message translates to:
  /// **'Each day you practice, you build something meaningful.'**
  String get reminderDay3BodyVar4;

  /// Daily reminder day 3 title variant 5
  ///
  /// In en, this message translates to:
  /// **'Find your calm 🕊️'**
  String get reminderDay3TitleVar5;

  /// Daily reminder day 3 body variant 5
  ///
  /// In en, this message translates to:
  /// **'A brief pause can reset your entire day.'**
  String get reminderDay3BodyVar5;

  /// Daily reminder day 4 title
  ///
  /// In en, this message translates to:
  /// **'Small steps 🪴'**
  String get reminderDay4Title;

  /// Daily reminder day 4 body
  ///
  /// In en, this message translates to:
  /// **'It has been 4 days since you meditated. Resume your practice with a short session.'**
  String get reminderDay4Body;

  /// Daily reminder day 5 title
  ///
  /// In en, this message translates to:
  /// **'Time to reconnect 💪'**
  String get reminderDay5Title;

  /// Daily reminder day 5 body
  ///
  /// In en, this message translates to:
  /// **'It has been 5 days. A calm pause now can help you get back on track.'**
  String get reminderDay5Body;

  /// Daily reminder day 6 title
  ///
  /// In en, this message translates to:
  /// **'Almost a week ⏰'**
  String get reminderDay6Title;

  /// Daily reminder day 6 body
  ///
  /// In en, this message translates to:
  /// **'It has been almost a week since you meditated. Close the loop with a mindful moment.'**
  String get reminderDay6Body;

  /// Daily reminder day 7 title
  ///
  /// In en, this message translates to:
  /// **'One week check in 📅'**
  String get reminderDay7Title;

  /// Daily reminder day 7 body
  ///
  /// In en, this message translates to:
  /// **'It has been a week since you meditated. Take a moment for yourself now.'**
  String get reminderDay7Body;

  /// Daily reminder day 8 title
  ///
  /// In en, this message translates to:
  /// **'Fresh start 🌤️'**
  String get reminderDay8Title;

  /// Daily reminder day 8 body
  ///
  /// In en, this message translates to:
  /// **'It has been over a week. A fresh start with just a few mindful minutes.'**
  String get reminderDay8Body;

  /// Daily reminder day 9 title
  ///
  /// In en, this message translates to:
  /// **'Find your centre 🎯'**
  String get reminderDay9Title;

  /// Daily reminder day 9 body
  ///
  /// In en, this message translates to:
  /// **'A short session can reset your day.'**
  String get reminderDay9Body;

  /// Daily reminder day 10 title
  ///
  /// In en, this message translates to:
  /// **'Double digits 🔟'**
  String get reminderDay10Title;

  /// Daily reminder day 10 body
  ///
  /// In en, this message translates to:
  /// **'It has been 10 days since you meditated. Pick up where you left off.'**
  String get reminderDay10Body;

  /// Daily reminder day 11 title
  ///
  /// In en, this message translates to:
  /// **'Gentle nudge 🤍'**
  String get reminderDay11Title;

  /// Daily reminder day 11 body
  ///
  /// In en, this message translates to:
  /// **'Pause, breathe, and notice how you feel.'**
  String get reminderDay11Body;

  /// Daily reminder day 12 title
  ///
  /// In en, this message translates to:
  /// **'Keep steady 🧭'**
  String get reminderDay12Title;

  /// Daily reminder day 12 body
  ///
  /// In en, this message translates to:
  /// **'A calm moment is waiting for you.'**
  String get reminderDay12Body;

  /// Daily reminder day 13 title
  ///
  /// In en, this message translates to:
  /// **'Approaching two weeks ⏳'**
  String get reminderDay13Title;

  /// Daily reminder day 13 body
  ///
  /// In en, this message translates to:
  /// **'It has been almost two weeks since you meditated. Try a two minute restart.'**
  String get reminderDay13Body;

  /// Daily reminder day 14 title
  ///
  /// In en, this message translates to:
  /// **'Two week check in 🔔'**
  String get reminderDay14Title;

  /// Daily reminder day 14 body
  ///
  /// In en, this message translates to:
  /// **'It has been 14 days since you meditated. Resume your practice now, gently.'**
  String get reminderDay14Body;

  /// Daily reminder day 15 title
  ///
  /// In en, this message translates to:
  /// **'Pausing reminders 🌿'**
  String get reminderDay15Title;

  /// Daily reminder day 15 body
  ///
  /// In en, this message translates to:
  /// **'We\'re pausing reminders for now. We are here whenever you are ready.'**
  String get reminderDay15Body;

  /// Daily reminder day 30 title
  ///
  /// In en, this message translates to:
  /// **'A gentle nudge 🤗'**
  String get reminderDay30Title;

  /// Daily reminder day 30 body
  ///
  /// In en, this message translates to:
  /// **'It\'s been a month since you meditated. Just 2 minutes can help you feel better. We\'re here when you\'re ready.'**
  String get reminderDay30Body;

  /// Tooltip text for repeat mode when set to repeat once
  ///
  /// In en, this message translates to:
  /// **'Repeat Once'**
  String get repeatModeOnce;

  /// Tooltip text for repeat mode when set to repeat forever
  ///
  /// In en, this message translates to:
  /// **'Repeat Forever'**
  String get repeatModeForever;

  /// Repeat sheet option: no repeat
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get repeatModeOff;

  /// Repeat sheet: description of no repeat
  ///
  /// In en, this message translates to:
  /// **'Play once, then finish.'**
  String get repeatModeOffDescription;

  /// Repeat sheet: description of repeat once
  ///
  /// In en, this message translates to:
  /// **'Play it twice, then finish.'**
  String get repeatModeOnceDescription;

  /// Repeat sheet: description of repeat forever
  ///
  /// In en, this message translates to:
  /// **'Keep playing until you stop it.'**
  String get repeatModeForeverDescription;

  /// Title for adding a manual meditation session
  ///
  /// In en, this message translates to:
  /// **'Add Session'**
  String get addSession;

  /// Title for the dialog confirming deletion of a tracked session
  ///
  /// In en, this message translates to:
  /// **'Delete Session'**
  String get deleteSessionTitle;

  /// Confirmation message shown when the user long-presses a session to delete it
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this session? This will update your streak and stats.'**
  String get deleteSessionConfirmation;

  /// Error snackbar shown when deleting a session fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete session.'**
  String get deleteSessionError;

  /// Label for time selection
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// Tab label for adding a session on a single day
  ///
  /// In en, this message translates to:
  /// **'Single day'**
  String get singleDay;

  /// Tab label for adding sessions across a range of days
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get dateRange;

  /// Label for the start date in a range picker
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get startDate;

  /// Label for the end date in a range picker
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get endDate;

  /// Validation error when the end date precedes the start date
  ///
  /// In en, this message translates to:
  /// **'End date must be on or after the start date'**
  String get endDateBeforeStartError;

  /// Placeholder text for time selection
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get selectTime;

  /// Short placeholder text for duration input
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// Text to indicate an optional field
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// Title for morning meditation sessions
  ///
  /// In en, this message translates to:
  /// **'Morning meditation'**
  String get morningMeditation;

  /// Title for afternoon meditation sessions
  ///
  /// In en, this message translates to:
  /// **'Afternoon meditation'**
  String get afternoonMeditation;

  /// Title for evening meditation sessions
  ///
  /// In en, this message translates to:
  /// **'Evening meditation'**
  String get eveningMeditation;

  /// Title for night meditation sessions
  ///
  /// In en, this message translates to:
  /// **'Night meditation'**
  String get nightMeditation;

  /// Button text to add a session
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Placeholder text shown for manually added sessions when no custom title is provided
  ///
  /// In en, this message translates to:
  /// **'Manually added session'**
  String get manuallyAddedSession;

  /// Explanation text for the add session dialog
  ///
  /// In en, this message translates to:
  /// **'If you\'ve done a meditation session outside the app, you can add it here to track it in your stats.'**
  String get addSessionExplanation;

  /// Error message shown when trying to add a session with a future date/time
  ///
  /// In en, this message translates to:
  /// **'Cannot add sessions in the future'**
  String get cannotAddFutureSession;

  /// Label prefix for meditation completion time
  ///
  /// In en, this message translates to:
  /// **'Completed at'**
  String get completedAt;

  /// The Continue section's name in Customize, and its screen-reader heading on Home (not drawn)
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get upNextTitle;

  /// Caption next to the pack progress bar on the Your Path card, e.g. 3 of 7
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total}'**
  String upNextProgress(int completed, int total);

  /// Headline on the Up Next card when every session in the pinned pack is complete
  ///
  /// In en, this message translates to:
  /// **'You finished {packTitle}'**
  String upNextPackCompletedTitle(String packTitle);

  /// Supporting line on the completed Up Next card
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session complete} other{{count} sessions complete}}'**
  String upNextPackCompletedSubtitle(int count);

  /// Fallback button label on the completed Up Next card, used while the next pack's title is still loading
  ///
  /// In en, this message translates to:
  /// **'Start the next pack'**
  String get upNextPackCompletedCta;

  /// Button on the completed Up Next card, naming the next pack it will pin
  ///
  /// In en, this message translates to:
  /// **'Start {packTitle}'**
  String upNextPackCompletedCtaNamed(String packTitle);

  /// Headline shown when the user finishes the final pack in the curated sequence
  ///
  /// In en, this message translates to:
  /// **'You\'ve finished every pack in the series'**
  String get upNextPathCompletedTitle;

  /// Supporting line shown when there is no next pack to offer
  ///
  /// In en, this message translates to:
  /// **'Explore the library to find what\'s next.'**
  String get upNextPathCompletedSubtitle;

  /// Snackbar after the completed hero's button puts the next pack in the series on Home
  ///
  /// In en, this message translates to:
  /// **'{packTitle} is ready on Home'**
  String upNextNextPackPinnedSnack(String packTitle);

  /// Title for the manage defaults screen
  ///
  /// In en, this message translates to:
  /// **'Manage Defaults'**
  String get manageDefaults;

  /// Label for default guide name setting
  ///
  /// In en, this message translates to:
  /// **'Default Guide Name'**
  String get defaultGuideName;

  /// Label for default duration setting
  ///
  /// In en, this message translates to:
  /// **'Default Duration'**
  String get defaultDuration;

  /// Message shown when default guide name is cleared
  ///
  /// In en, this message translates to:
  /// **'Default guide name cleared'**
  String get defaultGuideNameCleared;

  /// Text shown when a default value is not set
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// Note explaining how defaults work in Up Next
  ///
  /// In en, this message translates to:
  /// **'These defaults are set from your last selection on any track. Home uses them to skip the selection screen when you continue a pack.'**
  String get defaultsNote;

  /// Text shown when a streak freeze was used on a particular day
  ///
  /// In en, this message translates to:
  /// **'Streak freeze used'**
  String get streakFreezeUsed;

  /// Singular form of session
  ///
  /// In en, this message translates to:
  /// **'session'**
  String get session;

  /// Plural form of sessions
  ///
  /// In en, this message translates to:
  /// **'sessions'**
  String get sessions;

  /// Accessibility label for the play button in the player
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// Accessibility label for the pause button in the player
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Accessibility label for the skip-back button in the player
  ///
  /// In en, this message translates to:
  /// **'Skip back 10 seconds'**
  String get skipBackward10Seconds;

  /// Accessibility label for the skip-forward button in the player
  ///
  /// In en, this message translates to:
  /// **'Skip forward 10 seconds'**
  String get skipForward10Seconds;

  /// Accessibility label for the repeat button in the player
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// Accessibility label for the close button in the player
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Accessibility label for the download button in the player
  ///
  /// In en, this message translates to:
  /// **'Download audio'**
  String get downloadAudio;

  /// Accessibility label for the delete-download button in the player
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get deleteDownload;

  /// Accessibility label for the playback speed control in the player
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// Speed sheet: button that sets playback speed back to 1.0x
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get speedReset;

  /// Background sound sheet: label above the list of ambient sounds
  ///
  /// In en, this message translates to:
  /// **'Sounds'**
  String get backgroundSoundsSection;

  /// Accessibility label for the streak circle button on the home screen
  ///
  /// In en, this message translates to:
  /// **'View streak'**
  String get viewStreak;

  /// Accessibility label for the retry/refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Accessibility label prefix for the home hero card
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get upNext;

  /// Accessibility label for dismiss/close buttons
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Accessibility label for the clear search button
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get clearSearch;

  /// Accessibility label for the button that clears the saved default guide preference
  ///
  /// In en, this message translates to:
  /// **'Clear default guide'**
  String get clearDefault;

  /// Question on onboarding screen 1 — asking about the user's meditation experience
  ///
  /// In en, this message translates to:
  /// **'Have you meditated before?'**
  String get onboardingExperienceQuestion;

  /// Subtext below the question on onboarding screen 1
  ///
  /// In en, this message translates to:
  /// **'This helps us show you the right starting point.'**
  String get onboardingExperienceSubtext;

  /// Option 1 on onboarding screen 1 — user has never meditated
  ///
  /// In en, this message translates to:
  /// **'Never tried it'**
  String get onboardingExperienceNever;

  /// Option 2 on onboarding screen 1 — user has meditated a little
  ///
  /// In en, this message translates to:
  /// **'A little, here and there'**
  String get onboardingExperienceALittle;

  /// Option 3 on onboarding screen 1 — user has a regular meditation practice
  ///
  /// In en, this message translates to:
  /// **'I have a regular practice'**
  String get onboardingExperienceRegular;

  /// CTA button label on the onboarding result screen
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingResultCta;

  /// Accessibility label for the favorite button when the item is not yet favorited
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// Snackbar after the star button adds a pack or track to Favorites
  ///
  /// In en, this message translates to:
  /// **'Added to Favorites'**
  String get addedToFavorites;

  /// Snackbar after the star button removes a pack or track from Favorites
  ///
  /// In en, this message translates to:
  /// **'Removed from Favorites'**
  String get removedFromFavorites;

  /// Accessibility label for the favorite button when the item is already favorited
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// Swipe action on the home Your Path card that opens the pack
  ///
  /// In en, this message translates to:
  /// **'Open pack'**
  String get openPack;

  /// Pack screen status row subtitle when every session in Your Path is complete
  ///
  /// In en, this message translates to:
  /// **'All sessions done'**
  String get yourPathAllDone;

  /// Button at the bottom of a pack track list that marks every track complete
  ///
  /// In en, this message translates to:
  /// **'Mark all complete'**
  String get markAllComplete;

  /// Button at the bottom of a pack track list that clears completion on every track
  ///
  /// In en, this message translates to:
  /// **'Mark all incomplete'**
  String get markAllIncomplete;

  /// Accessibility label for the per-track toggle when the track is not complete
  ///
  /// In en, this message translates to:
  /// **'Mark complete'**
  String get markTrackComplete;

  /// Accessibility label for the per-track toggle when the track is complete
  ///
  /// In en, this message translates to:
  /// **'Mark incomplete'**
  String get markTrackIncomplete;

  /// Content tag chip label (server tag id: sleep)
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get tagSleep;

  /// Content tag chip label (server tag id: stress)
  ///
  /// In en, this message translates to:
  /// **'Stress'**
  String get tagStress;

  /// Content tag chip label (server tag id: anxiety)
  ///
  /// In en, this message translates to:
  /// **'Anxiety'**
  String get tagAnxiety;

  /// Content tag chip label (server tag id: low_mood)
  ///
  /// In en, this message translates to:
  /// **'Low mood'**
  String get tagLowMood;

  /// Content tag chip label (server tag id: focus)
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get tagFocus;

  /// Content tag chip label (server tag id: calm)
  ///
  /// In en, this message translates to:
  /// **'Calm'**
  String get tagCalm;

  /// Content tag chip label (server tag id: self_compassion)
  ///
  /// In en, this message translates to:
  /// **'Self-compassion'**
  String get tagSelfCompassion;

  /// Content tag chip label (server tag id: gratitude)
  ///
  /// In en, this message translates to:
  /// **'Gratitude'**
  String get tagGratitude;

  /// Content tag chip label (server tag id: emotions)
  ///
  /// In en, this message translates to:
  /// **'Difficult emotions'**
  String get tagEmotions;

  /// Content tag chip label (server tag id: pain)
  ///
  /// In en, this message translates to:
  /// **'Pain'**
  String get tagPain;

  /// Content tag chip label (server tag id: confidence)
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get tagConfidence;

  /// Content tag chip label (server tag id: relationships)
  ///
  /// In en, this message translates to:
  /// **'Relationships'**
  String get tagRelationships;

  /// Content tag chip label (server tag id: grief)
  ///
  /// In en, this message translates to:
  /// **'Grief'**
  String get tagGrief;

  /// Content tag chip label (server tag id: habit_building)
  ///
  /// In en, this message translates to:
  /// **'Habit building'**
  String get tagHabitBuilding;

  /// Content tag chip label (server tag id: breathing)
  ///
  /// In en, this message translates to:
  /// **'Breathing'**
  String get tagBreathing;

  /// Content tag chip label (server tag id: body_scan)
  ///
  /// In en, this message translates to:
  /// **'Body scan'**
  String get tagBodyScan;

  /// Content tag chip label (server tag id: loving_kindness)
  ///
  /// In en, this message translates to:
  /// **'Loving-kindness'**
  String get tagLovingKindness;

  /// Content tag chip label (server tag id: open_awareness)
  ///
  /// In en, this message translates to:
  /// **'Open awareness'**
  String get tagOpenAwareness;

  /// Content tag chip label (server tag id: visualization)
  ///
  /// In en, this message translates to:
  /// **'Visualisation'**
  String get tagVisualization;

  /// Content tag chip label (server tag id: mantra)
  ///
  /// In en, this message translates to:
  /// **'Mantra'**
  String get tagMantra;

  /// Content tag chip label (server tag id: walking)
  ///
  /// In en, this message translates to:
  /// **'Walking'**
  String get tagWalking;

  /// Content tag chip label (server tag id: reflection)
  ///
  /// In en, this message translates to:
  /// **'Reflection'**
  String get tagReflection;

  /// Content tag chip label (server tag id: sound)
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get tagSound;

  /// Content tag chip label (server tag id: guided_meditation)
  ///
  /// In en, this message translates to:
  /// **'Guided meditation'**
  String get tagGuidedMeditation;

  /// Content tag chip label (server tag id: talk)
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get tagTalk;

  /// Content tag chip label (server tag id: sleep_story)
  ///
  /// In en, this message translates to:
  /// **'Sleep stories'**
  String get tagSleepStory;

  /// Content tag chip label (server tag id: music)
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get tagMusic;

  /// Content tag chip label (server tag id: nature_sounds)
  ///
  /// In en, this message translates to:
  /// **'Nature sounds'**
  String get tagNatureSounds;

  /// Content tag chip label (server tag id: course_lesson)
  ///
  /// In en, this message translates to:
  /// **'Course lessons'**
  String get tagCourseLesson;

  /// Content tag chip label (server tag id: beginners)
  ///
  /// In en, this message translates to:
  /// **'For beginners'**
  String get tagBeginners;

  /// Content tag chip label (server tag id: experienced)
  ///
  /// In en, this message translates to:
  /// **'Experienced'**
  String get tagExperienced;

  /// Content tag chip label (server tag id: teens_students)
  ///
  /// In en, this message translates to:
  /// **'Teens & students'**
  String get tagTeensStudents;

  /// Content tag chip label (server tag id: teachers)
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get tagTeachers;

  /// Content tag chip label (server tag id: workplace)
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get tagWorkplace;

  /// Content tag chip label (server tag id: kids)
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get tagKids;

  /// Content tag chip label (server tag id: morning)
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get tagMorning;

  /// Content tag chip label (server tag id: evening)
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get tagEvening;

  /// Content tag chip label (server tag id: sos)
  ///
  /// In en, this message translates to:
  /// **'SOS'**
  String get tagSos;

  /// Content tag chip label (server tag id: on_the_go)
  ///
  /// In en, this message translates to:
  /// **'On the go'**
  String get tagOnTheGo;

  /// Content tag chip label (server tag id: crisis)
  ///
  /// In en, this message translates to:
  /// **'Times of crisis'**
  String get tagCrisis;

  /// Content tag chip label (server tag id: spanish)
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get tagSpanish;

  /// Empty state on a tag page
  ///
  /// In en, this message translates to:
  /// **'No sessions with this tag yet'**
  String get tagNoTracks;

  /// No description provided for @sessionBells.
  ///
  /// In en, this message translates to:
  /// **'Session bells'**
  String get sessionBells;

  /// No description provided for @sessionBellsDescription.
  ///
  /// In en, this message translates to:
  /// **'A bell at the beginning, middle and end'**
  String get sessionBellsDescription;

  /// Eyebrow on the home hero when nothing in the pack has been played yet, e.g. START HERE · Getting started
  ///
  /// In en, this message translates to:
  /// **'Start here'**
  String get upNextStartHere;

  /// Short label on the home hero swipe tile for Remove from Home (tiles are narrow)
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeFromHomeShort;

  /// Swipe action on the home hero that stops showing this pack there (Home falls back to Getting started)
  ///
  /// In en, this message translates to:
  /// **'Remove from Home'**
  String get removeFromHome;

  /// Snackbar after removing a pack from the home hero; offers Undo
  ///
  /// In en, this message translates to:
  /// **'Removed from Home.'**
  String get removedFromHome;

  /// Pack screen play button when nothing in the pack has been played; also puts the pack on Home
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get packStart;

  /// Pack screen play button once some sessions are done; also puts the pack on Home
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get packContinue;

  /// Snackbar after the pack screen Start/Continue button puts a new pack on Home; offers Undo
  ///
  /// In en, this message translates to:
  /// **'Added to Home so you can pick up where you left off.'**
  String get packAddedToHome;

  /// Title of the home Timer screen and of a timer session in the player
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get timerTitle;

  /// Timer screen mode toggle: counts up until the user ends the session
  ///
  /// In en, this message translates to:
  /// **'Stopwatch'**
  String get timerModeStopwatch;

  /// Label under the hours wheel on the Timer screen
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get timerHoursLabel;

  /// Label under the minutes wheel on the Timer screen
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get timerMinutesLabel;

  /// Body of the card explaining Stopwatch mode on the Timer screen
  ///
  /// In en, this message translates to:
  /// **'The time counts up from zero. Tap stop when you\'re done and the session is saved.'**
  String get timerStopwatchCaption;

  /// Timer screen primary button
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get timerStart;

  /// Player button that ends a timer session early (or finishes a stopwatch) and records it
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get timerEndSession;

  /// Caption under the elapsed time in a stopwatch session
  ///
  /// In en, this message translates to:
  /// **'elapsed'**
  String get timerElapsed;

  /// Snackbar when a timer session is ended before one minute
  ///
  /// In en, this message translates to:
  /// **'Sessions under a minute aren\'t saved'**
  String get timerTooShort;

  /// History row for a timer session, e.g. 'Timer · 20 min'
  ///
  /// In en, this message translates to:
  /// **'Timer · {duration}'**
  String timerHistoryTitle(String duration);

  /// Screen reader label of a duration chip on the Timer screen
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String timerPresetSemantics(int minutes);

  /// Background sound row offline when the sound was never downloaded, so it cannot play
  ///
  /// In en, this message translates to:
  /// **'Not downloaded. Connect to play'**
  String get soundNeedsConnection;

  /// Title of the card explaining Stopwatch mode on the Timer screen
  ///
  /// In en, this message translates to:
  /// **'Sit for as long as you like'**
  String get timerStopwatchTitle;

  /// Offline screen link that opens the Timer, which works without a connection
  ///
  /// In en, this message translates to:
  /// **'Open timer'**
  String get openTimer;

  /// Screen-reader label for the player's download button while a download is in progress (value is the percentage)
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get downloadingAudio;

  /// Screen-reader label for the player's seek bar
  ///
  /// In en, this message translates to:
  /// **'Playback position'**
  String get playbackPosition;

  /// Screen-reader value for the seek bar, e.g. 3:12 of 10:00
  ///
  /// In en, this message translates to:
  /// **'{position} of {duration}'**
  String playbackPositionValue(String position, String duration);

  /// Screen-reader status for a day on the streak row / calendar when the user meditated that day, read after the weekday
  ///
  /// In en, this message translates to:
  /// **'Meditated'**
  String get dayMeditated;

  /// Screen-reader status for a day on the streak row / calendar with no meditation
  ///
  /// In en, this message translates to:
  /// **'Not meditated'**
  String get dayNotMeditated;

  /// Screen-reader label of the stats calendar's previous-month arrow
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// Screen-reader label of the stats calendar's next-month arrow
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// Screen-reader count on a search filter tab, read after the tab name
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 result} other{{count} results}}'**
  String searchResultsCount(int count);

  /// Tooltip / screen-reader label of an icon button that clears a text field
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearField;

  /// Screen-reader label of the link icon on pack rows that open a web page
  ///
  /// In en, this message translates to:
  /// **'External link'**
  String get externalLink;

  /// Screen-reader suffix on the Home streak circle once today's meditation is done
  ///
  /// In en, this message translates to:
  /// **'Meditated today'**
  String get meditatedToday;

  /// Button that closes an end screen shown on the next launch and returns to Home
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get endScreenDone;

  /// Top line of an end screen shown on the next launch because the app was closed before it could appear (e.g. the user fell asleep). The session ended between 6pm yesterday and 5am today.
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished “{title}” last night.'**
  String endScreenRestoredLastNight(String title);

  /// As endScreenRestoredLastNight, for a session that ended earlier today
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished “{title}” earlier today.'**
  String endScreenRestoredEarlierToday(String title);

  /// As endScreenRestoredLastNight, for a session that ended yesterday during the day
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished “{title}” yesterday.'**
  String endScreenRestoredYesterday(String title);

  /// As endScreenRestoredLastNight, for a Timer session of {minutes} minutes
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished a {minutes}-minute timer last night.'**
  String endScreenRestoredTimerLastNight(int minutes);

  /// As endScreenRestoredEarlierToday, for a Timer session
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished a {minutes}-minute timer earlier today.'**
  String endScreenRestoredTimerEarlierToday(int minutes);

  /// As endScreenRestoredYesterday, for a Timer session
  ///
  /// In en, this message translates to:
  /// **'Welcome back. You finished a {minutes}-minute timer yesterday.'**
  String endScreenRestoredTimerYesterday(int minutes);

  /// Calm home heading above the locally available meditation timer.
  ///
  /// In en, this message translates to:
  /// **'Time to sit.'**
  String get localHomeHeading;

  /// Local introduction heading for someone new to meditation.
  ///
  /// In en, this message translates to:
  /// **'A little time to begin.'**
  String get localIntroBeginHeading;

  /// Local introduction heading for someone with some meditation experience.
  ///
  /// In en, this message translates to:
  /// **'Ease back into your practice.'**
  String get localIntroReturnHeading;

  /// Local introduction heading for someone with a regular meditation practice.
  ///
  /// In en, this message translates to:
  /// **'Space for your practice.'**
  String get localIntroPracticeHeading;

  /// Instructions for a first unguided meditation using the local timer.
  ///
  /// In en, this message translates to:
  /// **'Find a comfortable seat, set a short timer, and notice your breath. When your attention wanders, gently begin again.'**
  String get localIntroBeginBody;

  /// Encouragement to resume practice using the local timer.
  ///
  /// In en, this message translates to:
  /// **'Start with a few quiet minutes. The timer is ready whenever you are.'**
  String get localIntroReturnBody;

  /// Introduction to the local timer and its configurable bells and duration.
  ///
  /// In en, this message translates to:
  /// **'Use the timer for an unguided sit, with the bells and duration you prefer.'**
  String get localIntroPracticeBody;

  /// Explains that practice history, favourites and preferences are stored on the device.
  ///
  /// In en, this message translates to:
  /// **'Your practice history, favourites and settings stay on this device.'**
  String get localIntroDeviceOnlyNote;

  /// No description provided for @aboutMeditejo.
  ///
  /// In en, this message translates to:
  /// **'About Meditejo'**
  String get aboutMeditejo;

  /// No description provided for @forkCredit.
  ///
  /// In en, this message translates to:
  /// **'Meditejo is based on Medito by the Medito Foundation (meditofoundation.org), licensed under AGPL-3.0.'**
  String get forkCredit;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get sourceCode;

  /// No description provided for @upstreamProject.
  ///
  /// In en, this message translates to:
  /// **'Upstream project'**
  String get upstreamProject;

  /// Settings row for the built-in Dharma Seed catalogue sync
  ///
  /// In en, this message translates to:
  /// **'Dharma Seed library'**
  String get dharmaSeedLibrary;

  /// Sync progress, e.g. Updating talks: 500 of 48994
  ///
  /// In en, this message translates to:
  /// **'Updating {what}: {done} of {total}'**
  String dharmaSeedSyncProgress(String what, int done, int total);

  /// Record kind inside dharmaSeedSyncProgress
  ///
  /// In en, this message translates to:
  /// **'teachers'**
  String get dharmaSeedTeachers;

  /// Record kind inside dharmaSeedSyncProgress
  ///
  /// In en, this message translates to:
  /// **'retreats'**
  String get dharmaSeedRetreats;

  /// Record kind inside dharmaSeedSyncProgress
  ///
  /// In en, this message translates to:
  /// **'talks'**
  String get dharmaSeedTalks;

  /// Last successful sync; when is a formatted date and time
  ///
  /// In en, this message translates to:
  /// **'Up to date · {when}'**
  String dharmaSeedUpToDate(String when);

  /// Shown before the first Dharma Seed sync
  ///
  /// In en, this message translates to:
  /// **'Not synced yet. Tap to sync.'**
  String get dharmaSeedNeverSynced;

  /// Sync stopped on an error; error is a short reason
  ///
  /// In en, this message translates to:
  /// **'Sync paused ({error}). Tap to retry.'**
  String dharmaSeedSyncFailed(String error);

  /// Explore chip: guided meditations and chanting
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get exploreKindPractice;

  /// Explore chip: dharma talks, Q&A and other recordings
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get exploreKindTalks;

  /// Explore section title
  ///
  /// In en, this message translates to:
  /// **'Saved courses'**
  String get exploreSavedCourses;

  /// Explore section title
  ///
  /// In en, this message translates to:
  /// **'Saved teachers'**
  String get exploreSavedTeachers;

  /// Section title for retreats shown as courses
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get exploreCourses;

  /// Section title for teachers
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get exploreTeachers;

  /// Explore section title under the Practice chip
  ///
  /// In en, this message translates to:
  /// **'Latest guided practice'**
  String get exploreLatestPractice;

  /// Explore section title under the Talks chip
  ///
  /// In en, this message translates to:
  /// **'Latest talks'**
  String get exploreLatestTalks;

  /// Explore empty state while the first sync runs
  ///
  /// In en, this message translates to:
  /// **'Setting up your Dharma Seed library'**
  String get exploreSyncingTitle;

  /// Explore empty state body
  ///
  /// In en, this message translates to:
  /// **'Courses and teachers appear here as they arrive. The first time takes a minute or two.'**
  String get exploreSyncingBody;

  /// Explore empty state after a failed or missing first sync
  ///
  /// In en, this message translates to:
  /// **'The library is not synced yet'**
  String get exploreNoLibraryTitle;

  /// Explore empty state body
  ///
  /// In en, this message translates to:
  /// **'Connect to the internet and pull down to try again.'**
  String get exploreNoLibraryBody;

  /// Explore empty state for a chip with no results
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet. More arrives as the library syncs.'**
  String get exploreNothingInGroup;

  /// Search field hint
  ///
  /// In en, this message translates to:
  /// **'Search teachers, courses and talks'**
  String get searchDharmaHint;

  /// Search landing text above the suggestions
  ///
  /// In en, this message translates to:
  /// **'Try a teacher, a theme or a retreat'**
  String get searchTryHint;

  /// Search result group
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get searchTeachers;

  /// Search result group
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get searchCourses;

  /// Search result group
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get searchTalks;

  /// Label for the session-length filter
  ///
  /// In en, this message translates to:
  /// **'Talk length'**
  String get searchTalkLength;

  /// Session-length filter: no limit
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get searchLengthAny;

  /// Session-length filter
  ///
  /// In en, this message translates to:
  /// **'Under 10 min'**
  String get searchLengthUnder10;

  /// Session-length filter
  ///
  /// In en, this message translates to:
  /// **'10–20 min'**
  String get searchLength10to20;

  /// Session-length filter
  ///
  /// In en, this message translates to:
  /// **'20–30 min'**
  String get searchLength20to30;

  /// Session-length filter
  ///
  /// In en, this message translates to:
  /// **'30–45 min'**
  String get searchLength30to45;

  /// Session-length filter
  ///
  /// In en, this message translates to:
  /// **'Over 45 min'**
  String get searchLengthOver45;

  /// Course progress line
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} left'**
  String courseLeft(int count, int total);

  /// Course progress line when every session is done
  ///
  /// In en, this message translates to:
  /// **'All {total} played'**
  String courseAllPlayed(int total);

  /// Button to save a course
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get courseSave;

  /// Button state for a saved course or teacher
  ///
  /// In en, this message translates to:
  /// **'In library'**
  String get courseSaved;

  /// Course page tab
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get courseSessionsTab;

  /// Course page tab
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get courseSummaryTab;

  /// Course page tab
  ///
  /// In en, this message translates to:
  /// **'Teacher'**
  String get courseTeacherTab;

  /// Summary tab when the description is empty
  ///
  /// In en, this message translates to:
  /// **'This course has no written summary.'**
  String get courseNoSummary;

  /// Group heading in a long course
  ///
  /// In en, this message translates to:
  /// **'Day {number}'**
  String courseDay(int number);

  /// Row state for a session saved for offline listening
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get courseSessionDownloaded;

  /// Session length in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String courseSessionLength(int minutes);

  /// Button to save a teacher
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get teacherSave;

  /// Teacher page section
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get teacherCourses;

  /// Teacher page section
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get teacherTalks;

  /// Teacher page button to load another page of talks
  ///
  /// In en, this message translates to:
  /// **'Show more talks'**
  String get teacherShowMore;

  /// Teacher page error
  ///
  /// In en, this message translates to:
  /// **'This teacher is not in the library yet.'**
  String get teacherNotFound;

  /// Teacher page when the bio is empty
  ///
  /// In en, this message translates to:
  /// **'No biography on Dharma Seed.'**
  String get teacherNoBio;

  /// Teacher page link
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get teacherWebsite;

  /// Link to the item on its source site
  ///
  /// In en, this message translates to:
  /// **'View on {source}'**
  String attributionViewOn(String source);

  /// Licence note under the credit
  ///
  /// In en, this message translates to:
  /// **'Streamed as recorded, unmodified.'**
  String get attributionUnmodified;

  /// Credit line naming the licence
  ///
  /// In en, this message translates to:
  /// **'Licence: {license}'**
  String attributionLicence(String license);

  /// Number of talks a teacher gave
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 talk} other{{count} talks}}'**
  String teacherTalkCount(int count);

  /// Number of courses (retreats) a teacher gave
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 course} other{{count} courses}}'**
  String teacherCourseCount(int count);

  /// Installed version name and build number
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String aboutVersion(String version, String build);

  /// Button that asks GitHub for a newer Meditejo
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheck;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// Shown when the installed build is the newest
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get updateUpToDate;

  /// when is a formatted date and time
  ///
  /// In en, this message translates to:
  /// **'Last checked {when}'**
  String updateLastChecked(String when);

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String updateAvailable(String version);

  /// Button that downloads and installs the update
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateAction;

  /// Heading above the release notes
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateWhatsNew;

  /// No description provided for @updateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading… {percent}%'**
  String updateDownloading(int percent);

  /// No description provided for @updateVerifying.
  ///
  /// In en, this message translates to:
  /// **'Checking the download…'**
  String get updateVerifying;

  /// No description provided for @updateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Handing it to Android…'**
  String get updateInstalling;

  /// Shown once, before opening Android's settings
  ///
  /// In en, this message translates to:
  /// **'To install updates, Android needs “Install unknown apps” switched on for Meditejo. The next screen is Android’s own; switch it on, then come back here and the update will continue.'**
  String get updatePermissionExplanation;

  /// No description provided for @updatePermissionWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for “Install unknown apps”. Switch it on for Meditejo, then come back.'**
  String get updatePermissionWaiting;

  /// No description provided for @updateOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get updateOpenSettings;

  /// No description provided for @updateTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get updateTryAgain;

  /// No description provided for @updateErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach GitHub. Check your connection and try again.'**
  String get updateErrorOffline;

  /// No description provided for @updateErrorRateLimited.
  ///
  /// In en, this message translates to:
  /// **'GitHub is asking for a pause. Try again in an hour or so.'**
  String get updateErrorRateLimited;

  /// No description provided for @updateErrorUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The update information isn’t available right now. Try again later.'**
  String get updateErrorUnavailable;

  /// No description provided for @updateErrorDownload.
  ///
  /// In en, this message translates to:
  /// **'The download didn’t finish. Try again when you’re ready.'**
  String get updateErrorDownload;

  /// No description provided for @updateErrorHash.
  ///
  /// In en, this message translates to:
  /// **'The download doesn’t match what was published, so it wasn’t installed. Try downloading it again.'**
  String get updateErrorHash;

  /// No description provided for @updateErrorSignature.
  ///
  /// In en, this message translates to:
  /// **'This file wasn’t signed with Meditejo’s key, so it wasn’t installed.'**
  String get updateErrorSignature;

  /// No description provided for @updateErrorNotMeditejo.
  ///
  /// In en, this message translates to:
  /// **'This file isn’t the Meditejo update it should be, so it wasn’t installed.'**
  String get updateErrorNotMeditejo;

  /// No description provided for @updateErrorInstall.
  ///
  /// In en, this message translates to:
  /// **'Android couldn’t install the update.'**
  String get updateErrorInstall;

  /// One quiet line on Home
  ///
  /// In en, this message translates to:
  /// **'Meditejo {version} is available'**
  String homeUpdateNotice(String version);

  /// Opens About Meditejo
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get homeUpdateView;

  /// Accessibility label of the close button
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get homeUpdateDismiss;

  /// Heading of the screen and Home section listing what the user added
  ///
  /// In en, this message translates to:
  /// **'Your library'**
  String get libraryTitle;

  /// Button that opens the import screen
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get libraryAdd;

  /// Library section for guided practice
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get libraryPractice;

  /// Library section for talks and Q&A
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get libraryTalks;

  /// Library section for followed teachers
  ///
  /// In en, this message translates to:
  /// **'Teachers'**
  String get libraryTeachers;

  /// Link from the Home library section to the library screen
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get librarySeeAll;

  /// Empty library heading
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get libraryEmptyTitle;

  /// Empty library explanation
  ///
  /// In en, this message translates to:
  /// **'Add a course, a talk or a recording from a link or a file.'**
  String get libraryEmptyBody;

  /// Home library section when nothing is added
  ///
  /// In en, this message translates to:
  /// **'Paste a link, share one from another app, or pick a file.'**
  String get libraryEmptyHome;

  /// Menu item that reclassifies a library entry as practice
  ///
  /// In en, this message translates to:
  /// **'Move to Practice'**
  String get libraryMoveToPractice;

  /// Menu item that reclassifies a library entry as a talk
  ///
  /// In en, this message translates to:
  /// **'Move to Talks'**
  String get libraryMoveToTalks;

  /// Menu item that renames a library entry
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get libraryRename;

  /// Menu item that removes a library entry
  ///
  /// In en, this message translates to:
  /// **'Remove from library'**
  String get libraryRemove;

  /// Confirmation title for removing a library entry
  ///
  /// In en, this message translates to:
  /// **'Remove from your library?'**
  String get libraryRemoveTitle;

  /// Confirmation text when the entry was imported by the user
  ///
  /// In en, this message translates to:
  /// **'The audio copied to this device for it will be deleted.'**
  String get libraryRemoveImported;

  /// Confirmation text when the entry comes from a catalogue
  ///
  /// In en, this message translates to:
  /// **'It stays in Explore, and you can add it again.'**
  String get libraryRemoveCatalogue;

  /// Title of the rename dialog
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get libraryRenameTitle;

  /// Hint in the rename field
  ///
  /// In en, this message translates to:
  /// **'Name in your library'**
  String get libraryRenameHint;

  /// Save button of the rename dialog
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get libraryRenameSave;

  /// Number of sessions in a course
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String librarySessions(int count);

  /// Shown after something is added to the library
  ///
  /// In en, this message translates to:
  /// **'Added to your library'**
  String get libraryAddedSnack;

  /// Shown when the thing was already in the library
  ///
  /// In en, this message translates to:
  /// **'Already in your library'**
  String get libraryAlreadyIn;

  /// Action that opens a library entry
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get libraryOpen;

  /// Shown after removing from the library
  ///
  /// In en, this message translates to:
  /// **'Removed from your library'**
  String get libraryRemovedSnack;

  /// Button that adds a course, talk or teacher to the library
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get libraryAddToLibrary;

  /// Button state when the item is already in the library
  ///
  /// In en, this message translates to:
  /// **'In library'**
  String get libraryInLibrary;

  /// Row label for a session left partway, with the position
  ///
  /// In en, this message translates to:
  /// **'Resume at {position}'**
  String libraryResumeAt(String position);

  /// Title of the import screen
  ///
  /// In en, this message translates to:
  /// **'Add to your library'**
  String get importTitle;

  /// Hint in the link field
  ///
  /// In en, this message translates to:
  /// **'Paste a link'**
  String get importFieldHint;

  /// Help under the link field
  ///
  /// In en, this message translates to:
  /// **'Dharma Seed pages, podcast feeds, audio links, or files on your phone.'**
  String get importHelp;

  /// Button that pastes from the clipboard
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get importPaste;

  /// Button that looks at the typed link
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get importPreviewAction;

  /// Suggestion when the clipboard holds a link
  ///
  /// In en, this message translates to:
  /// **'Link on your clipboard: {host}'**
  String importClipboard(String host);

  /// Button that uses the clipboard link
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get importUseClipboard;

  /// Button that picks audio files
  ///
  /// In en, this message translates to:
  /// **'Choose files'**
  String get importChooseFiles;

  /// Button that picks a folder of audio files
  ///
  /// In en, this message translates to:
  /// **'Choose a folder'**
  String get importChooseFolder;

  /// Shown while a link is being read
  ///
  /// In en, this message translates to:
  /// **'Looking at the link…'**
  String get importLooking;

  /// The one primary action of the import preview
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get importPrimary;

  /// Shown while the import is stored
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get importAdding;

  /// Import choice: a course
  ///
  /// In en, this message translates to:
  /// **'Course'**
  String get importKindCourse;

  /// Import choice: a single recording
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get importKindSingle;

  /// Caption under the Course choice for a feed
  ///
  /// In en, this message translates to:
  /// **'All {count} episodes, in order'**
  String importCaptionCourseAll(int count);

  /// Caption under the Single choice for a feed
  ///
  /// In en, this message translates to:
  /// **'Just one episode: the latest, or one you pick'**
  String get importCaptionLatest;

  /// Caption under the Course choice for several files
  ///
  /// In en, this message translates to:
  /// **'One course, in the order shown'**
  String get importCaptionFilesCourse;

  /// Caption under the Single choice for several files
  ///
  /// In en, this message translates to:
  /// **'Each file on its own'**
  String get importCaptionFilesSingles;

  /// Label above the Practice/Talk choice
  ///
  /// In en, this message translates to:
  /// **'Counts as'**
  String get importCountsAs;

  /// Import choice: practice
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get importGroupPractice;

  /// Import choice: talk
  ///
  /// In en, this message translates to:
  /// **'Talk'**
  String get importGroupTalk;

  /// Episode order: oldest first
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get importOrderOldest;

  /// Episode order: newest first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get importOrderNewest;

  /// A total length that is a lower bound because some sessions have no length
  ///
  /// In en, this message translates to:
  /// **'at least {duration}'**
  String importAtLeast(String duration);

  /// Note that some feed items had no audio
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item without audio was left out} other{{count} items without audio were left out}}'**
  String importSkipped(int count);

  /// Shown in the preview when it is already added
  ///
  /// In en, this message translates to:
  /// **'This is already in your library.'**
  String get importInLibraryNote;

  /// Default name for several imported files
  ///
  /// In en, this message translates to:
  /// **'Imported audio'**
  String get importDefaultTitle;

  /// Label of the title field in the preview
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get importTitleLabel;

  /// Calm failure: nothing entered
  ///
  /// In en, this message translates to:
  /// **'Paste a link or choose a file to begin.'**
  String get importFailEmpty;

  /// Calm failure: not a usable link
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a link or file I can use. Try an address that starts with https://.'**
  String get importFailUnrecognised;

  /// Calm failure: a service with no readable feed
  ///
  /// In en, this message translates to:
  /// **'Links from that service can\'t be imported. For a podcast, look for its feed address, or its page on Apple Podcasts.'**
  String get importFailUnsupportedHost;

  /// Calm failure: no connection
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach that address. Check your connection and try again.'**
  String get importFailOffline;

  /// Calm failure: 404
  ///
  /// In en, this message translates to:
  /// **'That page wasn\'t found. Check the link and try again.'**
  String get importFailNotFound;

  /// Calm failure: server error
  ///
  /// In en, this message translates to:
  /// **'That site couldn\'t give us what we asked for. Try again later.'**
  String get importFailUnreachable;

  /// Calm failure: page with no feed or audio
  ///
  /// In en, this message translates to:
  /// **'That page has no podcast feed or audio file I can find. If you have the feed address (often ending in .xml or /feed), paste that instead.'**
  String get importFailNoFeed;

  /// Calm failure: feed without audio
  ///
  /// In en, this message translates to:
  /// **'This feed has no audio episodes.'**
  String get importFailNoEpisodes;

  /// Calm failure: unreadable feed
  ///
  /// In en, this message translates to:
  /// **'This feed couldn\'t be read. It may be damaged or not a podcast feed.'**
  String get importFailBrokenFeed;

  /// Calm failure: Dharma Seed item missing
  ///
  /// In en, this message translates to:
  /// **'Dharma Seed doesn\'t have that, or couldn\'t be reached just now.'**
  String get importFailDharmaSeed;

  /// Calm failure: file missing
  ///
  /// In en, this message translates to:
  /// **'That file couldn\'t be found.'**
  String get importFailFile;

  /// Calm failure: no audio files
  ///
  /// In en, this message translates to:
  /// **'No audio files found there.'**
  String get importFailNoAudio;

  /// Calm failure: storing failed
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that. Please try again.'**
  String get importFailAdd;

  /// The row naming the episode a Single will add
  ///
  /// In en, this message translates to:
  /// **'Episode'**
  String get importEpisodeLabel;

  /// Opens the episode picker
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get importEpisodeChange;

  /// Title of the episode picker
  ///
  /// In en, this message translates to:
  /// **'Choose an episode'**
  String get importEpisodePickerTitle;

  /// Hint in the episode picker's search field
  ///
  /// In en, this message translates to:
  /// **'Search episodes'**
  String get importEpisodeSearch;

  /// Shown when the episode search finds nothing
  ///
  /// In en, this message translates to:
  /// **'No episode matches that.'**
  String get importEpisodeNone;

  /// Marks a feed's newest episode in the picker
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get importEpisodeLatest;

  /// Shown while a picked folder is listed
  ///
  /// In en, this message translates to:
  /// **'Looking in the folder…'**
  String get importFolderLooking;

  /// Progress while a folder's audio is copied into the app
  ///
  /// In en, this message translates to:
  /// **'Copying {done} of {total}…'**
  String importFolderCopying(int done, int total);

  /// Stops copying a folder
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get importFolderCancel;

  /// Note that some items in a folder could not be read
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item couldn\'t be read and was left out} other{{count} items couldn\'t be read and were left out}}'**
  String importUnreadable(int count);

  /// Calm failure: empty folder
  ///
  /// In en, this message translates to:
  /// **'That folder is empty.'**
  String get importFailFolderEmpty;

  /// Calm failure: too many files
  ///
  /// In en, this message translates to:
  /// **'That folder holds more than 1,000 audio files. Choose a smaller one.'**
  String get importFailFolderTooLarge;

  /// Calm failure: storage full
  ///
  /// In en, this message translates to:
  /// **'There isn\'t enough free space on this phone to copy that folder.'**
  String get importFailFolderNoSpace;

  /// Calm failure: folder could not be read
  ///
  /// In en, this message translates to:
  /// **'That folder couldn\'t be read. Try choosing it again, or choose files instead.'**
  String get importFailFolderUnreadable;

  /// Calm failure: no folder picker
  ///
  /// In en, this message translates to:
  /// **'This device has no folder picker. Choose files instead.'**
  String get importFailFolderUnavailable;

  /// Shown when a link or file was shared into the app
  ///
  /// In en, this message translates to:
  /// **'Shared with Meditejo'**
  String get shareArrived;

  /// Heading above the library courses on Explore
  ///
  /// In en, this message translates to:
  /// **'In your library'**
  String get exploreLibraryHeading;

  /// Button that plays a session from the start instead of resuming
  ///
  /// In en, this message translates to:
  /// **'From the beginning'**
  String get libraryFromStart;

  /// Switch on an imported feed course: look for new episodes now and then
  ///
  /// In en, this message translates to:
  /// **'Check for new episodes'**
  String get libraryCheckNew;

  /// Calm one-line YouTube extraction or playback failure
  ///
  /// In en, this message translates to:
  /// **'This video isn\'t available right now'**
  String get youtubeUnavailable;

  /// No description provided for @youtubeCourseCaption.
  ///
  /// In en, this message translates to:
  /// **'All sessions, in playlist order'**
  String get youtubeCourseCaption;

  /// No description provided for @youtubeSingleCaption.
  ///
  /// In en, this message translates to:
  /// **'Just this video'**
  String get youtubeSingleCaption;

  /// No description provided for @youtubeOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Connect to play this video'**
  String get youtubeOffline;

  /// No description provided for @youtubePlaylistOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Connect to load this playlist'**
  String get youtubePlaylistOffline;

  /// No description provided for @youtubePlaylistUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This playlist isn\'t available right now'**
  String get youtubePlaylistUnavailable;

  /// No description provided for @youtubeAgeRestricted.
  ///
  /// In en, this message translates to:
  /// **'This video is age-restricted'**
  String get youtubeAgeRestricted;

  /// No description provided for @youtubePlaylistAgeRestricted.
  ///
  /// In en, this message translates to:
  /// **'This playlist contains age-restricted videos'**
  String get youtubePlaylistAgeRestricted;

  /// No description provided for @youtubePrivate.
  ///
  /// In en, this message translates to:
  /// **'This video is private'**
  String get youtubePrivate;

  /// No description provided for @youtubePlaylistPrivate.
  ///
  /// In en, this message translates to:
  /// **'This playlist is private'**
  String get youtubePlaylistPrivate;

  /// No description provided for @youtubeRateLimited.
  ///
  /// In en, this message translates to:
  /// **'YouTube is busy or asking for a bot check. Try again later'**
  String get youtubeRateLimited;

  /// No description provided for @youtubePlaylistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Sessions aren\'t stored on this device yet. We\'ll try again shortly'**
  String get youtubePlaylistEmpty;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @exploreSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your library and Dharma Seed'**
  String get exploreSearchHint;

  /// The shortcuts section's name in Customize, and its screen-reader heading on Home (not drawn)
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get homeShortcutsTitle;

  /// The pinned section's name in Customize, and its screen-reader heading on Home (not drawn)
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get homePinnedTitle;

  /// No description provided for @homeCustomize.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get homeCustomize;

  /// No description provided for @homeCustomizeHint.
  ///
  /// In en, this message translates to:
  /// **'Switch sections on or off, and drag to put them in your order.'**
  String get homeCustomizeHint;

  /// No description provided for @homeContinueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing in progress. Add something to your library, or open Explore.'**
  String get homeContinueEmpty;

  /// No description provided for @homeContinueResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get homeContinueResume;

  /// No description provided for @homeContinueStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get homeContinueStart;

  /// No description provided for @homeContinueSessionOf.
  ///
  /// In en, this message translates to:
  /// **'Session {number} of {total}'**
  String homeContinueSessionOf(int number, int total);

  /// No description provided for @homeContinueTimeLeft.
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String homeContinueTimeLeft(String time);

  /// No description provided for @homeShortcutAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get homeShortcutAdd;

  /// Screen-reader label of a Home tile that starts the timer with a saved background-sound preset.
  ///
  /// In en, this message translates to:
  /// **'Start the timer with {preset}'**
  String homeShortcutPresetTimer(String preset);

  /// No description provided for @pinCourse.
  ///
  /// In en, this message translates to:
  /// **'Pin to Home'**
  String get pinCourse;

  /// No description provided for @unpinCourse.
  ///
  /// In en, this message translates to:
  /// **'Unpin from Home'**
  String get unpinCourse;

  /// No description provided for @pinnedLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Home holds up to three pinned courses or playlists. Unpin one first.'**
  String get pinnedLimitReached;

  /// No description provided for @pinnedCourseAdded.
  ///
  /// In en, this message translates to:
  /// **'Pinned to Home'**
  String get pinnedCourseAdded;

  /// No description provided for @statsFeedbackNote.
  ///
  /// In en, this message translates to:
  /// **'These numbers are feedback, not a score.'**
  String get statsFeedbackNote;

  /// Sounds screen: soundsYourMix
  ///
  /// In en, this message translates to:
  /// **'Your mix'**
  String get soundsYourMix;

  /// Sounds screen: soundsEmptyMix
  ///
  /// In en, this message translates to:
  /// **'Tap a sound below to start a mix.'**
  String get soundsEmptyMix;

  /// Sounds screen: soundsLayerCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sound} other{{count} sounds}}'**
  String soundsLayerCount(int count);

  /// Sounds screen: soundsPlay
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get soundsPlay;

  /// Sounds screen: soundsPause
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get soundsPause;

  /// Sounds screen: soundsStop
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get soundsStop;

  /// Sounds screen: soundsRemove
  ///
  /// In en, this message translates to:
  /// **'Remove {sound}'**
  String soundsRemove(String sound);

  /// Sounds screen: soundsDrift
  ///
  /// In en, this message translates to:
  /// **'Drift'**
  String get soundsDrift;

  /// Sounds screen: soundsDriftHint
  ///
  /// In en, this message translates to:
  /// **'Let the level rise and fall slowly'**
  String get soundsDriftHint;

  /// Sounds screen: soundsPresets
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get soundsPresets;

  /// Sounds screen: soundsSavePreset
  ///
  /// In en, this message translates to:
  /// **'Save mix'**
  String get soundsSavePreset;

  /// Sounds screen: the overline on a preset that ships with the app
  ///
  /// In en, this message translates to:
  /// **'Meditejo'**
  String get soundsPresetOurs;

  /// Sounds screen: the overline on a preset the user saved
  ///
  /// In en, this message translates to:
  /// **'Yours'**
  String get soundsPresetYours;

  /// Sounds screen: soundsPresetName
  ///
  /// In en, this message translates to:
  /// **'Preset name'**
  String get soundsPresetName;

  /// Sounds screen: soundsPresetSaved
  ///
  /// In en, this message translates to:
  /// **'Saved “{name}”'**
  String soundsPresetSaved(String name);

  /// Sounds screen: soundsDeletePreset
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String soundsDeletePreset(String name);

  /// Sounds screen: soundsDelete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get soundsDelete;

  /// Sounds screen: soundsCancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get soundsCancel;

  /// Sounds screen: soundsSave
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get soundsSave;

  /// Sounds screen: soundsLayerLimit
  ///
  /// In en, this message translates to:
  /// **'A mix holds up to {count} sounds'**
  String soundsLayerLimit(int count);

  /// Sounds screen: soundsCouldNotPlay
  ///
  /// In en, this message translates to:
  /// **'This sound could not be played'**
  String get soundsCouldNotPlay;

  /// Sounds screen: soundsUnderSessions
  ///
  /// In en, this message translates to:
  /// **'Under sessions'**
  String get soundsUnderSessions;

  /// Sounds screen: soundsUnderPractice
  ///
  /// In en, this message translates to:
  /// **'Play under practice'**
  String get soundsUnderPractice;

  /// Sounds screen: soundsUnderTalks
  ///
  /// In en, this message translates to:
  /// **'Play under talks'**
  String get soundsUnderTalks;

  /// Sounds screen: soundsUnderSessionsHint
  ///
  /// In en, this message translates to:
  /// **'Your mix plays beneath the session, at its own volume'**
  String get soundsUnderSessionsHint;

  /// Sounds screen: soundsCredits
  ///
  /// In en, this message translates to:
  /// **'Sound credits'**
  String get soundsCredits;

  /// Sounds screen: soundsNotificationText
  ///
  /// In en, this message translates to:
  /// **'Playing your mix'**
  String get soundsNotificationText;

  /// Sounds screen: soundCategoryRain
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get soundCategoryRain;

  /// Sounds screen: soundCategoryWater
  ///
  /// In en, this message translates to:
  /// **'Water'**
  String get soundCategoryWater;

  /// Sounds screen: soundCategoryWind
  ///
  /// In en, this message translates to:
  /// **'Wind'**
  String get soundCategoryWind;

  /// Sounds screen: soundCategoryForest
  ///
  /// In en, this message translates to:
  /// **'Forest and birds'**
  String get soundCategoryForest;

  /// Sounds screen: soundCategoryFire
  ///
  /// In en, this message translates to:
  /// **'Fire'**
  String get soundCategoryFire;

  /// Sounds screen: soundCategoryRoom
  ///
  /// In en, this message translates to:
  /// **'Rooms and city'**
  String get soundCategoryRoom;

  /// Sounds screen: soundCategoryNight
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get soundCategoryNight;

  /// Sounds screen: soundPresetRainForest
  ///
  /// In en, this message translates to:
  /// **'Rain on the forest'**
  String get soundPresetRainForest;

  /// Sounds screen: soundPresetNight
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get soundPresetNight;

  /// Sounds screen: soundPresetHearth
  ///
  /// In en, this message translates to:
  /// **'Hearth'**
  String get soundPresetHearth;

  /// Sounds screen: soundPresetShore
  ///
  /// In en, this message translates to:
  /// **'Shore'**
  String get soundPresetShore;

  /// Sounds screen: soundCreditsIntro
  ///
  /// In en, this message translates to:
  /// **'These recordings are shared by their authors under their own licences, not the app’s AGPL. Each was cut to a loop, crossfaded, levelled and re-encoded for Meditejo.'**
  String get soundCreditsIntro;

  /// Sounds screen: soundCreditsBy
  ///
  /// In en, this message translates to:
  /// **'“{original}” by {author}'**
  String soundCreditsBy(String original, String author);

  /// Sounds screen: soundCreditsChanges
  ///
  /// In en, this message translates to:
  /// **'Changes: {changes}'**
  String soundCreditsChanges(String changes);

  /// Sounds screen: soundCreditsAttributionRequired
  ///
  /// In en, this message translates to:
  /// **'Attribution required'**
  String get soundCreditsAttributionRequired;

  /// Sounds screen, generated layers: soundCategoryGenerated
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get soundCategoryGenerated;

  /// Sounds screen, generated layers: synthNoise
  ///
  /// In en, this message translates to:
  /// **'Noise'**
  String get synthNoise;

  /// Sounds screen, generated layers: synthDrone
  ///
  /// In en, this message translates to:
  /// **'Drone'**
  String get synthDrone;

  /// Sounds screen, generated layers: synthBinaural
  ///
  /// In en, this message translates to:
  /// **'Binaural beats'**
  String get synthBinaural;

  /// Sounds screen, generated layers: synthAdjust
  ///
  /// In en, this message translates to:
  /// **'Adjust {sound}'**
  String synthAdjust(String sound);

  /// Sounds screen, generated layers: noiseColour
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get noiseColour;

  /// Sounds screen, generated layers: noiseWhite
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get noiseWhite;

  /// Sounds screen, generated layers: noisePink
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get noisePink;

  /// Sounds screen, generated layers: noiseBrown
  ///
  /// In en, this message translates to:
  /// **'Brown'**
  String get noiseBrown;

  /// Sounds screen, generated layers: noiseBands
  ///
  /// In en, this message translates to:
  /// **'Bands'**
  String get noiseBands;

  /// Sounds screen, generated layers: noiseReset
  ///
  /// In en, this message translates to:
  /// **'Reset bands'**
  String get noiseReset;

  /// Sounds screen, generated layers: droneRoot
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get droneRoot;

  /// Sounds screen, generated layers: droneTimbre
  ///
  /// In en, this message translates to:
  /// **'Timbre'**
  String get droneTimbre;

  /// Sounds screen, generated layers: dronePure
  ///
  /// In en, this message translates to:
  /// **'Pure'**
  String get dronePure;

  /// Sounds screen, generated layers: droneWarm
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get droneWarm;

  /// Sounds screen, generated layers: droneBright
  ///
  /// In en, this message translates to:
  /// **'Bright'**
  String get droneBright;

  /// Sounds screen, generated layers: droneMovement
  ///
  /// In en, this message translates to:
  /// **'Movement'**
  String get droneMovement;

  /// Sounds screen, generated layers: binauralCarrier
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get binauralCarrier;

  /// Sounds screen, generated layers: binauralBeat
  ///
  /// In en, this message translates to:
  /// **'Beat'**
  String get binauralBeat;

  /// Sounds screen, generated layers: binauralHeadphones
  ///
  /// In en, this message translates to:
  /// **'Binaural beats need headphones: each ear hears its own tone.'**
  String get binauralHeadphones;

  /// Sounds screen, generated layers: soundPresetStillness
  ///
  /// In en, this message translates to:
  /// **'Stillness'**
  String get soundPresetStillness;

  /// Action that makes a playlist
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get myCourseNew;

  /// Hint in the new playlist name field
  ///
  /// In en, this message translates to:
  /// **'Playlist name'**
  String get myCourseNameHint;

  /// Confirms making a new playlist
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get myCourseCreate;

  /// Title of a new playlist left unnamed
  ///
  /// In en, this message translates to:
  /// **'My playlist'**
  String get myCourseDefaultTitle;

  /// Menu entry that adds a session or playlist to a playlist
  ///
  /// In en, this message translates to:
  /// **'Add to playlist…'**
  String get myCourseAddTo;

  /// Title of the sheet listing playlists
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get myCourseAddToTitle;

  /// Snackbar after adding to a playlist
  ///
  /// In en, this message translates to:
  /// **'Added to {title}'**
  String myCourseAddedSnack(String title);

  /// Snackbar after adding a playlist's sessions
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session added to {title}} other{{count} sessions added to {title}}}'**
  String myCourseAddedCountSnack(int count, String title);

  /// Snackbar when the playlist already holds it
  ///
  /// In en, this message translates to:
  /// **'Already in {title}'**
  String myCourseAlreadyIn(String title);

  /// Snackbar when a playlist has nothing addable
  ///
  /// In en, this message translates to:
  /// **'There are no sessions to add.'**
  String get myCourseNothingToAdd;

  /// Snackbar when adding fails
  ///
  /// In en, this message translates to:
  /// **'Could not add it to the playlist.'**
  String get myCourseAddFailed;

  /// Shown in the add-to-playlist sheet with no playlists
  ///
  /// In en, this message translates to:
  /// **'You haven\'t made a playlist yet. Start one here.'**
  String get myCourseNoneYet;

  /// Copies any course, or another playlist, into a new playlist
  ///
  /// In en, this message translates to:
  /// **'Copy as playlist'**
  String get myCourseDuplicate;

  /// Title of a duplicated playlist
  ///
  /// In en, this message translates to:
  /// **'{title} (my copy)'**
  String myCourseCopyTitle(String title);

  /// Snackbar when duplicating fails
  ///
  /// In en, this message translates to:
  /// **'Could not make a playlist from this.'**
  String get myCourseDuplicateFailed;

  /// Snackbar when saving a playlist fails
  ///
  /// In en, this message translates to:
  /// **'Could not save the playlist.'**
  String get myCourseSaveFailed;

  /// Opens the playlist edit screen; also its title
  ///
  /// In en, this message translates to:
  /// **'Edit playlist'**
  String get myCourseEdit;

  /// Saves the playlist edit
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get myCourseSave;

  /// Course title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get myCourseTitleLabel;

  /// Course description field
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get myCourseDescriptionLabel;

  /// Practice or Talks selector label
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get myCourseKindLabel;

  /// Cover picker label
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get myCourseCoverLabel;

  /// Semantics label for the generated cover choice
  ///
  /// In en, this message translates to:
  /// **'Generated cover'**
  String get myCourseCoverGenerated;

  /// Semantics label for an artwork cover choice
  ///
  /// In en, this message translates to:
  /// **'Cover {index}'**
  String myCourseCoverChoice(int index);

  /// Header above the playlist rows on the edit screen
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get myCourseSessionsLabel;

  /// Adds a section heading such as Day 1
  ///
  /// In en, this message translates to:
  /// **'Add heading'**
  String get myCourseAddHeading;

  /// Hint in a section heading field
  ///
  /// In en, this message translates to:
  /// **'Heading, e.g. Day 1'**
  String get myCourseHeadingHint;

  /// Removes a row from the playlist
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get myCourseRemoveRow;

  /// Semantics label of a row's drag handle
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get myCourseDragHandle;

  /// Edit screen with no rows
  ///
  /// In en, this message translates to:
  /// **'No sessions yet. Use Add to playlist… in any session\'s menu.'**
  String get myCourseEditEmpty;

  /// Leaving the edit screen with unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Discard your changes?'**
  String get myCourseDiscardTitle;

  /// Discards unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get myCourseDiscard;

  /// Returns to the edit screen
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get myCourseKeepEditing;

  /// Deletes a playlist
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get myCourseDelete;

  /// Delete confirmation title
  ///
  /// In en, this message translates to:
  /// **'Delete this playlist?'**
  String get myCourseDeleteTitle;

  /// Delete confirmation body
  ///
  /// In en, this message translates to:
  /// **'Only the playlist goes. Its sessions stay in your library, with their downloads and progress.'**
  String get myCourseDeleteBody;

  /// Snackbar after deleting a playlist
  ///
  /// In en, this message translates to:
  /// **'Playlist deleted'**
  String get myCourseDeletedSnack;

  /// Empty playlist page title
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get myCourseEmptyTitle;

  /// Empty playlist page body
  ///
  /// In en, this message translates to:
  /// **'Add sessions from anywhere: a Dharma Seed talk, a YouTube video, an episode or a file. Open its menu and choose Add to playlist…'**
  String get myCourseEmptyBody;

  /// Label on a session its source no longer has
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get myCourseUnavailable;

  /// Tapping an unavailable session
  ///
  /// In en, this message translates to:
  /// **'This session is no longer available from its source.'**
  String get myCourseUnavailableSnack;

  /// Extra line when removing an import that playlists list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{It is also in one of your playlists, where it will show as unavailable.} other{It is also in {count} of your playlists, where it will show as unavailable.}}'**
  String myCourseRemoveWarning(int count);

  /// Tooltip of a row's overflow menu
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get myCourseMore;

  /// After taking a session out of a playlist
  ///
  /// In en, this message translates to:
  /// **'Removed from the playlist'**
  String get myCourseRemovedSnack;

  /// Button on a playlist page that opens its edit screen
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get myCourseEditAction;

  /// The tab bar's last tab: the user's own place (stats and settings)
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get navYou;

  /// The Sounds tab's mix panel when the mix has no layers
  ///
  /// In en, this message translates to:
  /// **'Nothing in your mix yet'**
  String get soundsMixEmptyTitle;

  /// Under the empty mix: how to start one
  ///
  /// In en, this message translates to:
  /// **'Tap a sound or a preset to start a mix.'**
  String get soundsMixEmptyHint;

  /// Button on a layer of the mix that silences it
  ///
  /// In en, this message translates to:
  /// **'Mute {sound}'**
  String soundsMute(String sound);

  /// Button on a muted layer of the mix that brings its sound back
  ///
  /// In en, this message translates to:
  /// **'Unmute {sound}'**
  String soundsUnmute(String sound);

  /// Opens the mix panel docked at the bottom of the Sounds tab
  ///
  /// In en, this message translates to:
  /// **'Show your mix'**
  String get soundsShowMix;

  /// Folds the mix panel back down to its bar
  ///
  /// In en, this message translates to:
  /// **'Hide your mix'**
  String get soundsHideMix;

  /// Screen-reader label of the slider for the whole mix's volume
  ///
  /// In en, this message translates to:
  /// **'Mix volume'**
  String get soundsMixVolume;

  /// Screen-reader label of a preset card, which starts the preset
  ///
  /// In en, this message translates to:
  /// **'Play {name}'**
  String soundsPlayPreset(String name);

  /// Badge on the preset card that is playing now
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get soundsPresetPlaying;

  /// Button on a generated layer (noise, drone, binaural beats) that opens its settings
  ///
  /// In en, this message translates to:
  /// **'Adjust'**
  String get soundsAdjust;

  /// In the player's Customize sheet, under Background sound: opens the Sounds screen
  ///
  /// In en, this message translates to:
  /// **'Edit your mix in Sounds'**
  String get soundsEditMix;

  /// Names what the user makes (a Playlist), shown beside a course on Library rows and as the kind on a playlist page. A course comes from a source.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get playlistKind;

  /// Settings group: defaults for sessions, day boundary, Health
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get settingsSectionPractice;

  /// Settings group: bells, cues and background sound defaults
  ///
  /// In en, this message translates to:
  /// **'Sounds & cues'**
  String get settingsSectionSounds;

  /// Settings group: imports, favorites, downloads, catalogue sync
  ///
  /// In en, this message translates to:
  /// **'Library & downloads'**
  String get settingsSectionLibrary;

  /// Settings group: theme, icon, home layout, widget
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// Settings group: the daily reminder
  ///
  /// In en, this message translates to:
  /// **'Notifications & reminders'**
  String get settingsSectionReminders;

  /// Settings group: version, updates, licences and credits
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// Settings row that opens the Customize sheet for guided Practice
  ///
  /// In en, this message translates to:
  /// **'Practice sounds & cues'**
  String get settingsPracticeCues;

  /// Caption of the Practice cues row
  ///
  /// In en, this message translates to:
  /// **'Bells, cues and background sound'**
  String get settingsPracticeCuesCaption;

  /// Settings row that opens the Customize sheet for Talks
  ///
  /// In en, this message translates to:
  /// **'Talks sounds & cues'**
  String get settingsTalksCues;

  /// Caption of the Talks cues row
  ///
  /// In en, this message translates to:
  /// **'Bells, cues and background sound'**
  String get settingsTalksCuesCaption;

  /// Settings row for the day boundary used by streaks and stats
  ///
  /// In en, this message translates to:
  /// **'When my day starts'**
  String get settingsDayStarts;

  /// Day boundary value: midnight
  ///
  /// In en, this message translates to:
  /// **'Midnight (default)'**
  String get settingsDayStartsMidnight;

  /// Day boundary value: an hour of the morning
  ///
  /// In en, this message translates to:
  /// **'{hour}:00 AM'**
  String settingsDayStartsAt(int hour);

  /// The AGPL notice in About
  ///
  /// In en, this message translates to:
  /// **'Meditejo is free software under the GNU Affero General Public License v3.0. You can read, change and share its source code.'**
  String get settingsAgplNotice;

  /// Settings row opening the credits of the background sounds
  ///
  /// In en, this message translates to:
  /// **'Sound credits'**
  String get settingsSoundCredits;

  /// Settings row opening the licences page
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicenses;

  /// Stats card: today, week, month and all-time totals
  ///
  /// In en, this message translates to:
  /// **'Time practised'**
  String get statsTimePractised;

  /// Stats label
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get statsToday;

  /// Stats label: Monday to today
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get statsThisWeek;

  /// Stats label
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get statsThisMonth;

  /// Stats label
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get statsAllTime;

  /// You tab summary label
  ///
  /// In en, this message translates to:
  /// **'Total time'**
  String get statsTotalTime;

  /// Note under the totals when older sessions have no recorded length
  ///
  /// In en, this message translates to:
  /// **'Sessions from before the app recorded their length ({count}) count as days practised, not as minutes.'**
  String statsUntimedNote(int count);

  /// Stats empty state
  ///
  /// In en, this message translates to:
  /// **'Your first recorded session will show up here.'**
  String get statsEmpty;

  /// Chart title
  ///
  /// In en, this message translates to:
  /// **'Minutes a day'**
  String get statsDailyMinutes;

  /// Chart range option
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get statsRange7;

  /// Chart range option
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get statsRange30;

  /// Chart readout and screen-reader summary
  ///
  /// In en, this message translates to:
  /// **'{total} in all, practised on {practised} of {days} days'**
  String statsChartTotal(String total, int practised, int days);

  /// Calendar card title
  ///
  /// In en, this message translates to:
  /// **'Days practised'**
  String get statsDaysPracticedTitle;

  /// Days practised in the month shown
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String statsDaysPractised(int count);

  /// Screen-reader status of a calendar day with a session of unknown length
  ///
  /// In en, this message translates to:
  /// **'Practised'**
  String get statsPractised;

  /// Heat-map legend
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get statsLess;

  /// Heat-map legend
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get statsMore;

  /// Breakdown card title
  ///
  /// In en, this message translates to:
  /// **'Where your time went'**
  String get statsBreakdown;

  /// Breakdown: guided practice
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get statsPractice;

  /// Breakdown: talks
  ///
  /// In en, this message translates to:
  /// **'Talks'**
  String get statsTalks;

  /// Breakdown sub-heading
  ///
  /// In en, this message translates to:
  /// **'By course or source'**
  String get statsByCourse;

  /// Breakdown empty state
  ///
  /// In en, this message translates to:
  /// **'Once a session is recorded with its length, the split shows here.'**
  String get statsBreakdownEmpty;

  /// Breakdown row for a course with no recorded title
  ///
  /// In en, this message translates to:
  /// **'A course'**
  String get statsSourceCourse;

  /// Breakdown row
  ///
  /// In en, this message translates to:
  /// **'Added by hand'**
  String get statsSourceByHand;

  /// Breakdown row
  ///
  /// In en, this message translates to:
  /// **'Dharma Seed talks'**
  String get statsSourceDharmaSeed;

  /// Breakdown row
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get statsSourceYoutube;

  /// Breakdown row
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get statsSourceImported;

  /// Breakdown row
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get statsSourceOther;

  /// Streak card title
  ///
  /// In en, this message translates to:
  /// **'Streak and consistency'**
  String get statsStreakTitle;

  /// Streak card feedback line
  ///
  /// In en, this message translates to:
  /// **'You practised on {count} of the last 30 days.'**
  String statsLast30Days(int count);

  /// Streak card label
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get statsConsistency;

  /// Settings row and sheet: the mark at the top of Home
  ///
  /// In en, this message translates to:
  /// **'Home mark'**
  String get homeMarkTitle;

  /// The Home mark when it changes daily
  ///
  /// In en, this message translates to:
  /// **'Today\'s mark'**
  String get homeMarkToday;

  /// The Home mark when the user pinned it
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get homeMarkPinned;

  /// Home mark sheet, daily
  ///
  /// In en, this message translates to:
  /// **'A new mark arrives each day. Pin this one to keep it on Home.'**
  String get homeMarkTodayBody;

  /// Home mark sheet, pinned
  ///
  /// In en, this message translates to:
  /// **'This mark stays on Home until you go back to the daily mark.'**
  String get homeMarkPinnedBody;

  /// Button: keep today's mark on Home
  ///
  /// In en, this message translates to:
  /// **'Pin this mark'**
  String get homeMarkPin;

  /// Button: unpin the Home mark
  ///
  /// In en, this message translates to:
  /// **'Back to the daily mark'**
  String get homeMarkUnpin;

  /// Screen reader hint for long-pressing Home's mark
  ///
  /// In en, this message translates to:
  /// **'pin or unpin'**
  String get homeMarkPinHint;

  /// Settings row and screen: the app's colour palette
  ///
  /// In en, this message translates to:
  /// **'Palette'**
  String get paletteTitle;

  /// Palette option: a different palette each day
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get paletteDaily;

  /// Settings subtitle when the palette is daily; name is today's palette
  ///
  /// In en, this message translates to:
  /// **'Daily · {name} today'**
  String paletteDailyToday(String name);

  /// Library heading over what the user has started and not finished
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get libraryInProgress;

  /// Library filter chip: everything
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryFilterAll;

  /// Library filter chip: courses from a source
  ///
  /// In en, this message translates to:
  /// **'Courses'**
  String get libraryFilterCourses;

  /// Library filter chip: what the user made
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get libraryFilterPlaylists;

  /// Library filter chip: single sessions
  ///
  /// In en, this message translates to:
  /// **'Singles'**
  String get libraryFilterSingles;

  /// Library filter chip: what is downloaded
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get libraryFilterDownloads;

  /// Screen-reader label of the Library's filter chips
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get libraryFilterLabel;

  /// Screen-reader label of the Library's Practice/Talks switch
  ///
  /// In en, this message translates to:
  /// **'Practice or talks'**
  String get libraryGroupLabel;

  /// Tooltip of the Library's sort menu
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get librarySort;

  /// Sort the Library by most recently played or added
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get librarySortRecent;

  /// Sort the Library by name
  ///
  /// In en, this message translates to:
  /// **'A–Z'**
  String get librarySortTitle;

  /// Sort the Library by how far along a course is
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get librarySortProgress;

  /// Tooltip: switch the Library to a grid of cards
  ///
  /// In en, this message translates to:
  /// **'Show as grid'**
  String get libraryShowGrid;

  /// Tooltip: switch the Library to a list
  ///
  /// In en, this message translates to:
  /// **'Show as list'**
  String get libraryShowList;

  /// Where a course came from, on its Library card: the user's own link or files
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get librarySourceImported;

  /// Library heading when a filter matches nothing
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get libraryFilterEmpty;

  /// Library text when a filter matches nothing
  ///
  /// In en, this message translates to:
  /// **'Find something in Explore, or add a link or a file.'**
  String get libraryFilterEmptyBody;

  /// Button in an empty Library that opens the Explore tab
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get libraryEmptyExplore;

  /// Screen-reader label of the pin mark on a Library card
  ///
  /// In en, this message translates to:
  /// **'Pinned to Home'**
  String get libraryPinned;

  /// Sound card: download a sound that is not on this phone yet
  ///
  /// In en, this message translates to:
  /// **'Download {title}, {size}'**
  String soundPackDownloadSound(String title, String size);

  /// Sound card: stop downloading a sound
  ///
  /// In en, this message translates to:
  /// **'Cancel the download of {title}'**
  String soundPackCancelDownload(String title);

  /// Sound card: retry a failed download
  ///
  /// In en, this message translates to:
  /// **'The download of {title} failed. Try again'**
  String soundPackRetryDownload(String title);

  /// Sound card: queued behind other downloads
  ///
  /// In en, this message translates to:
  /// **'Waiting to download'**
  String get soundPackQueued;

  /// Sounds screen: heading of the downloadable sounds banner
  ///
  /// In en, this message translates to:
  /// **'More sounds'**
  String get soundPackMoreTitle;

  /// Sounds screen: how much is left to download
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 more sound to download} other{{count} more sounds to download}} · {size}'**
  String soundPackMoreBody(int count, String size);

  /// Sounds screen: download every sound that is not on this phone
  ///
  /// In en, this message translates to:
  /// **'Download all'**
  String get soundPackDownloadAll;

  /// Sounds screen: progress of the downloads
  ///
  /// In en, this message translates to:
  /// **'Downloading {done} of {total}'**
  String soundPackDownloading(int done, int total);

  /// Sounds screen: stop the downloads
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get soundPackCancel;

  /// Sounds screen: downloads wait because the phone is on mobile data
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi'**
  String get soundPackWaitingForWifi;

  /// Sounds screen: why downloads wait
  ///
  /// In en, this message translates to:
  /// **'Downloads wait for Wi-Fi. You can change this in Settings.'**
  String get soundPackWifiOnlyHint;

  /// Sounds screen: download on mobile data this once
  ///
  /// In en, this message translates to:
  /// **'Download anyway'**
  String get soundPackDownloadAnyway;

  /// Sounds screen: some downloads did not finish
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 download failed} other{{count} downloads failed}}'**
  String soundPackFailedCount(int count);

  /// Sounds screen: try the failed downloads again
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get soundPackRetry;

  /// Sounds screen: why a download failed (no network)
  ///
  /// In en, this message translates to:
  /// **'Check your connection'**
  String get soundPackFailureNetwork;

  /// Sounds screen: why a download failed (the server)
  ///
  /// In en, this message translates to:
  /// **'The download is not available right now'**
  String get soundPackFailureServer;

  /// Sounds screen: why a download failed (the checksum)
  ///
  /// In en, this message translates to:
  /// **'The file did not match what Meditejo expects, so it was not kept'**
  String get soundPackFailureIntegrity;

  /// Sounds screen: why a download failed (storage)
  ///
  /// In en, this message translates to:
  /// **'Could not save it on this phone'**
  String get soundPackFailureStorage;

  /// Mix: a layer whose sound is not on this phone
  ///
  /// In en, this message translates to:
  /// **'Needs download · {size}'**
  String soundPackNeedsDownload(String size);

  /// Download a sound
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get soundPackDownload;

  /// Mix panel: sounds missing from the mix
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 sound in this mix needs downloading. The rest plays.} other{{count} sounds in this mix need downloading. The rest plays.}}'**
  String soundPackMixMissing(int count);

  /// Preset card: sounds missing from a preset
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 sound needs downloading} other{{count} sounds need downloading}}'**
  String soundPackPresetMissing(int count);

  /// Snackbar: a mix plays without some sounds
  ///
  /// In en, this message translates to:
  /// **'Playing without {names}. {count, plural, one{It is} other{They are}} not downloaded yet.'**
  String soundPackMissingPartial(String names, int count);

  /// Snackbar: a mix has no sound that is on this phone
  ///
  /// In en, this message translates to:
  /// **'Nothing to play yet: {names} {count, plural, one{needs} other{need}} downloading.'**
  String soundPackMissingAll(String names, int count);

  /// Settings, Library and downloads: the sound pack row
  ///
  /// In en, this message translates to:
  /// **'Downloaded sounds'**
  String get settingsSoundPackTitle;

  /// Settings: how many sounds are downloaded and what they take
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} on this phone · {size}'**
  String settingsSoundPackSummary(int count, int total, String size);

  /// Settings: no sound is downloaded
  ///
  /// In en, this message translates to:
  /// **'None downloaded · {size} available'**
  String settingsSoundPackNone(String size);

  /// Settings: remove the downloaded sounds
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get settingsSoundPackDelete;

  /// Settings: dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete downloaded sounds?'**
  String get settingsSoundPackDeleteTitle;

  /// Settings: dialog text
  ///
  /// In en, this message translates to:
  /// **'This frees {size}. The sounds stay in the library, and you can download them again any time.'**
  String settingsSoundPackDeleteBody(String size);

  /// Settings: sound downloads wait for Wi-Fi
  ///
  /// In en, this message translates to:
  /// **'Download sounds on Wi-Fi only'**
  String get settingsSoundPackWifiOnly;

  /// Settings: why Wi-Fi only
  ///
  /// In en, this message translates to:
  /// **'They are large. On mobile data a download only starts when you choose Download anyway.'**
  String get settingsSoundPackWifiOnlyHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
