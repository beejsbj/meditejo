import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/dharma_seed/dharma_seed_providers.dart';
import 'package:medito/providers/library/import_providers.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/providers/meditation/downloaded_track_ids_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/routes/routes.dart';
import 'package:medito/scaffold_messenger_key.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/services/library/import_service.dart';
import 'package:medito/services/library/share_intake.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dharma_seed_app.dart';
import 'library_fixtures.dart';

class _Stats extends StatsNotifier {
  _Stats(this.checked);

  final List<String> checked;

  @override
  Future<LocalAllStats> build() async =>
      LocalAllStats.empty().copyWith(tracksChecked: [...checked]);
}

class FakePickers implements ImportPickers {
  FakePickers({this.files, this.folder});

  List<PickedFile>? files;
  String? folder;

  @override
  Future<List<PickedFile>?> pickAudioFiles() async => files;

  @override
  Future<String?> pickFolder() async => folder;
}

class FakeShareIntake implements ShareIntake {
  FakeShareIntake({this.first});

  SharedPayload? first;
  final controller = StreamController<SharedPayload>.broadcast();

  @override
  Future<SharedPayload?> initial() async => first;

  @override
  Stream<SharedPayload> get shares => controller.stream;
}

/// The library screens over in-memory databases, a scripted web, and fake
/// pickers, clipboard and share intake, inside the app's theme and
/// localisations.
class LibraryTestApp {
  LibraryTestApp._(this.harness, this.prefs, this.pickers, this.share);

  final LibraryHarness harness;
  final SharedPreferences prefs;
  final FakePickers pickers;
  final FakeShareIntake share;

  static Future<LibraryTestApp> create(
    WidgetTester tester, {
    Map<String, http.Response> routes = const {},
    Future<int?> Function(String)? probe,
    FakePickers? pickers,
    SharedPayload? shared,
  }) async {
    // Artwork goes through the image cache, which asks path_provider for a
    // folder; answer with a scratch one (the fetch then fails under the test
    // binding, which is the generated-artwork fallback).
    final scratch = Directory.systemTemp.createTempSync('library_widget_test');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => scratch.path);
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      scratch.deleteSync(recursive: true);
    });
    late LibraryHarness harness;
    late SharedPreferences prefs;
    await tester.runAsync(() async {
      harness = LibraryHarness.create(routes: routes, probe: probe);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });
    addTearDown(() => tester.runAsync(harness.dispose));
    return LibraryTestApp._(
      harness,
      prefs,
      pickers ?? FakePickers(),
      FakeShareIntake(first: shared),
    );
  }

  Future<void> pump(
    WidgetTester tester,
    Widget page, {
    String? clipboard,

    /// Open [page] on top of an empty root, so it can close itself.
    bool asRoute = false,
    List<String> played = const [],
    List<Override> overrides = const [],
    ImportService? importService,
  }) async {
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          libraryDatabaseProvider.overrideWithValue(harness.db),
          libraryStoreProvider.overrideWithValue(harness.store),
          importServiceProvider.overrideWithValue(
            importService ?? harness.service,
          ),
          importPickersProvider.overrideWithValue(pickers),
          shareIntakeProvider.overrideWithValue(share),
          clipboardLinkReaderProvider.overrideWithValue(() async => clipboard),
          statsProvider.overrideWith(() => _Stats(played)),
          downloadedTrackIdsProvider.overrideWithValue(const {}),
          // An empty catalogue stands in for Dharma Seed.
          dharmaSeedSourceProvider.overrideWithValue(harness.dharmaSeed),
          ...overrides,
        ],
        child: Builder(
          builder: (context) => MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
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
            home: asRoute ? const Scaffold(body: Text('root')) : page,
          ),
        ),
      ),
    );
    if (asRoute) {
      unawaited(
        navigatorKey.currentState!.push<Object?>(
          MaterialPageRoute(builder: (_) => page),
        ),
      );
    }
    await DharmaSeedTestApp.settle(tester);
  }
}
