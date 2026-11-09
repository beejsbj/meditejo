// Layout shots for real time in the stats: the You page's stats card and the
// top of the stats page, on eleven weeks of practice in which every talk was
// heard at 1.5× (so its real time is two thirds of its recording). At the
// S23+'s 411 dp light and dark, and a 360 dp phone in German with 1.3× text.
// Not part of the normal run:
//
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> flutter test \
//     test/screenshots/stats_real_time_screenshots_test.dart
//
// The history is built through JSON, so the same file also runs on a branch
// from before real time was recorded (it ignores `realMs`): the before shots.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/local_audio_completed.dart';
import 'package:medito/providers/shared_preference/shared_preference_provider.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/views/stats/stats_screen.dart';
import 'package:medito/views/you/you_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/stats_fixtures.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  await icons.load();
  final symbols =
      FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      );
  await symbols.load();
}

/// [richStats], with every talk heard at 1.5×.
LocalAllStats _spedUpTalks() {
  final stats = richStats(fixtureNow);
  return stats.copyWith(
    audioCompleted: [
      for (final e in stats.audioCompleted!)
        LocalAudioCompleted.fromJson({
          ...e.toJson(),
          if (e.kind == LocalAudioCompleted.kindTalks)
            'realMs': (e.durationMs! / 1.5).round(),
        }),
    ],
  );
}

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

typedef _Variant = (String name, double dp, Brightness, double scale, Locale);

const _variants = <_Variant>[
  ('411-light', 411, Brightness.light, 1, Locale('en')),
  ('411-dark', 411, Brightness.dark, 1, Locale('en')),
  ('360-de', 360, Brightness.light, 1.3, Locale('de')),
];

Future<void> _pump(WidgetTester tester, _Variant v, Widget home) async {
  final (_, dp, brightness, scale, locale) = v;
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = Size(dp * 2.625, 640 * 2.625);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        statsProvider.overrideWith(() => _Stats(_spedUpTalks())),
        practiceClockProvider.overrideWithValue(() => fixtureNow),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: meditejoTheme(brightness, IdentityPalettes.byId(null)),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    var render = tester.element(find.byType(Navigator).first).renderObject!;
    while (!render.isRepaintBoundary) {
      render = render.parent!;
    }
    final layer = render.debugLayer! as OffsetLayer;
    final image = await layer.toImage(render.paintBounds);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final v in _variants) {
    final name = v.$1;

    testWidgets('real time on the You page, $name', (tester) async {
      await _pump(tester, v, const YouView());
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'you-$name');
    }, skip: !_enabled);

    testWidgets('real time on the stats page, $name', (tester) async {
      await _pump(tester, v, const StatsScreen());
      expect(tester.takeException(), isNull);
      await _shoot(tester, 'stats-$name');
    }, skip: !_enabled);
  }
}
