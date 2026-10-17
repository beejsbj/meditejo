import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/services/dharma_seed/dharma_seed_database.dart';
import 'package:medito/services/dharma_seed/dharma_seed_source.dart';
import 'package:medito/services/dharma_seed/dharma_seed_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dharma_seed_catalogue.dart';
import 'dharma_seed_fake_api.dart';

class _Stats extends StatsNotifier {
  _Stats(this.checked);

  final List<String> checked;

  @override
  Future<LocalAllStats> build() async =>
      LocalAllStats.empty().copyWith(tracksChecked: [...checked]);
}

/// The real Dharma Seed source over an in-memory database, inside the app's
/// theme, localisations and navigator, so screens can be driven end to end:
/// a tap on a row really opens the next page.
class DharmaSeedTestApp {
  DharmaSeedTestApp._(this.db, this.source, this.prefs);

  final DharmaSeedDatabase db;
  final DharmaSeedSource source;
  final SharedPreferences prefs;

  /// Creates the database (seeded with the shared catalogue unless
  /// [seed] is false) and registers its disposal.
  static Future<DharmaSeedTestApp> create(
    WidgetTester tester, {
    bool seed = true,
    Map<String, Object> prefs = const {},
  }) async {
    // Teacher photos go through the image cache, which asks path_provider
    // for a folder; answer with a scratch one (the fetch itself then fails
    // under the test binding, which is the artwork fallback path).
    final scratch = Directory.systemTemp.createTempSync('ds_widget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => scratch.path,
        );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      scratch.deleteSync(recursive: true);
    });
    late DharmaSeedDatabase db;
    late SharedPreferences preferences;
    await tester.runAsync(() async {
      db = memoryDharmaSeedDb();
      if (seed) await seedDharmaSeedCatalogue(db);
      SharedPreferences.setMockInitialValues(prefs);
      preferences = await SharedPreferences.getInstance();
    });
    addTearDown(() => tester.runAsync(db.close));
    return DharmaSeedTestApp._(
      db,
      DharmaSeedSource(db: db, browseLimit: 10),
      preferences,
    );
  }

  /// Pumps [page] in the app shell.
  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    List<String> played = const [],
    Set<String> downloaded = const {},

    /// Use the app's real stats store (over the mock preferences) instead of
    /// a fixed list of played talks.
    bool realStats = false,

    /// A stand-in for the app's source (e.g. a slow one); defaults to [source].
    DharmaSeedSource? withSource,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          dharmaSeedSourceProvider.overrideWithValue(withSource ?? source),
          // Never contacted: only here so nothing builds a real client.
          dharmaSeedSyncProvider.overrideWithValue(
            DharmaSeedSync(
              db: db,
              client: FakeDharmaSeedApi().client(),
              sleep: (_) async {},
            ),
          ),
          if (!realStats) statsProvider.overrideWith(() => _Stats(played)),
          downloadedTrackIdsProvider.overrideWithValue(downloaded),
          ...overrides,
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            navigatorKey: navigatorKey,
            theme: appTheme(context, ThemeMode.light),
            darkTheme: appTheme(context, ThemeMode.dark),
            themeMode: ThemeMode.dark,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: page,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Lets database reads and page transitions finish. Memory-database reads
  /// complete on real time, so interleave real and fake time.
  static Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The image cache schedules a ten second clean-up the first time a photo
    // loads; let it fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 15));
  }
}
