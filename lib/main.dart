// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/updates/update_providers.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/providers/notification/reminder_provider.dart';
import 'package:medito/providers/locale_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/providers/theme_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/utils/notification_permission_flow.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:medito/services/history/app_history_service.dart';
import 'package:medito/services/home_widget_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:audio_service/audio_service.dart';
import 'package:medito/providers/player/ios_audio_handler.dart';
import 'package:medito/utils/bundled_licenses.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/stats_updater.dart';
import 'package:medito/views/splash_view.dart';
import 'package:medito/services/deep_link_service.dart';
// ignore: depend_on_referenced_packages
import 'package:device_preview/device_preview.dart';
import 'package:medito/config/debug_options.dart';
import 'scaffold_messenger_key.dart';

// Completer used as both the guard and the barrier for duplicate main() calls.
// It is set synchronously before any await, so a second call always finds it non-null.
Completer<void>? _initCompleter;

void main() async {
  if (_initCompleter != null) {
    AppLogger.d('MAIN', 'App already initialized, skipping main()');
    await _initCompleter!.future;
    return;
  }
  _initCompleter = Completer<void>();

  AppLogger.d('MAIN', 'Starting app initialization');

  // device_preview 3.0 simulates device metrics by installing its own
  // WidgetsBinding, so it has to run before any other binding is created —
  // ensureInitialized() below is then a no-op that returns this binding.
  // No-op in release builds; the simulation is driven from the "device_preview"
  // tab in Flutter DevTools, not from in-app UI.
  DevicePreview.enable(enabled: DebugOptions.enableDevicePreview);

  WidgetsFlutterBinding.ensureInitialized();

  // Google Sans ships under the SIL Open Font License 1.1, which requires the
  // license notice to travel with the app. Register it so it's included in the
  // in-app licenses page (Advanced > Licenses / showLicensePage).
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/google-sans/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Google Sans'], ofl);
  });

  // NewPipeExtractor and each of its bundled runtime dependencies (nanojson,
  // jsoup, jsr305, protobuf-javalite, Rhino) carry their own notice and source
  // link; see assets/licenses/newpipe-runtime-dependencies.json.
  registerBundledLicenses();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      const ['Meditejo cue sounds'],
      await rootBundle.loadString('assets/audio/NOTICE'),
    );
  });

  var prefs = await initializeSharedPreferences();

  try {
    final packageInfo = await PackageInfo.fromPlatform();
    await AppHistoryService.recordCurrentVersion(
      prefs,
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  } catch (e) {
    AppLogger.w('MAIN', 'Failed to record version history: $e');
  }

  // One-time detection pass for users who had daily_reminder_enabled=true but
  // never actually granted POST_NOTIFICATIONS (the old flow requested
  // SCHEDULE_EXACT_ALARM instead, which isn't needed and blocked many users).
  // We flag them here; HomeView will prompt them immediately on first render.
  const notifPermissionMigrationKey = 'notif_permission_migration_v1';
  if (!(prefs.getBool(notifPermissionMigrationKey) ?? false)) {
    await prefs.setBool(notifPermissionMigrationKey, true);
    final remindersEnabled =
        prefs.getBool(SharedPreferenceConstants.dailyReminderEnabled) ?? false;
    if (remindersEnabled) {
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await prefs.setBool(
          SharedPreferenceConstants.notifPermissionFixNeeded,
          true,
        );
      }
    }
  }

  // Users who declined the reminder permission before the fix still read as
  // "reminders on"; see repairReminderFlagOnce.
  await repairReminderFlagOnce(
    prefs,
    isGranted: () async => (await Permission.notification.status).isGranted,
  );

  await initializeAudioService();

  usePathUrlStrategy();

  _initCompleter?.complete();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ParentWidget(),
    ),
  );
}

void setupAudioCallback() {
  MeditoAudioServiceCallbackApi.setUp(AudioStateProvider(audioStateNotifier));
}

Future<void> initializeAudioService() async {
  if (Platform.isAndroid) {
    setupAudioCallback();
  } else if (Platform.isIOS) {
    iosAudioHandler = await AudioService.init(
      builder: () => IosAudioHandler(),
      config: const AudioServiceConfig(
        fastForwardInterval: Duration(seconds: 15),
        rewindInterval: Duration(seconds: 15),
      ),
    );
  }
}

class ParentWidget extends ConsumerStatefulWidget {
  static const String _title = 'Meditejo';

  const ParentWidget({super.key});

  @override
  ConsumerState<ParentWidget> createState() => _ParentWidgetState();
}

class _ParentWidgetState extends ConsumerState<ParentWidget>
    with WidgetsBindingObserver {
  DeepLinkService? _deepLinkService;

  @override
  void initState() {
    super.initState();
    _setUpSystemUi();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_recoverPreviousSession());
    unawaited(prepareDharmaSeed(ref));
    unawaited(startFeedRefresh(ref));
    unawaited(startUpdateCheck(ref));
  }

  Future<void> _recoverPreviousSession() async {
    if (Platform.isIOS) await processPendingCompletedTracks();
  }

  void _setUpSystemUi() {
    // Set default system UI style - will be updated in build method when theme is available
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _updateSystemUiForTheme(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final brightness = MediaQuery.of(context).platformBrightness;
    final isDark =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && brightness == Brightness.dark);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  void dispose() {
    _deepLinkService?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_deepLinkService == null) {
      _deepLinkService = DeepLinkService(ref: ref, context: context);
      _deepLinkService!.initialize();
    }

    final locale = ref.watch(localeProvider);
    // Keep the widgets' "day"/"days" unit in the app's language. No-op
    // unless the locale changed.
    HomeWidgetService.setLocale(locale);
    final themeMode = ref.watch(themeProvider);

    // Update system UI to match current theme
    _updateSystemUiForTheme(context);

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 0.8,
      maxScaleFactor: 1.5,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        scaffoldMessengerKey: scaffoldMessengerKey,
        navigatorKey: navigatorKey,
        theme: appTheme(context, ThemeMode.light),
        darkTheme: appTheme(context, ThemeMode.dark),
        themeMode: themeMode,
        title: ParentWidget._title,
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        initialRoute: '/',
        routes: {'/': (context) => const SplashView()},
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _onAppForegrounded();
    }
  }

  void _onAppForegrounded() async {
    ref.read(reminderProvider).clearBadge();
    ref.read(statsProvider.notifier).refresh();
    if (Platform.isIOS) {
      // Process any pending track completions when app comes back to foreground
      processPendingCompletedTracks().then((processedCount) {
        if (processedCount > 0) {
          AppLogger.d(
            'STATS',
            'Processed $processedCount pending tracks on foreground',
          );
        }
      });
    }
  }
}
