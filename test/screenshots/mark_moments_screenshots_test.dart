// Screenshots of Home's mark in its two moments (#63): the turn from
// yesterday's mark to today's, with today's name, and a deep breath. Run:
//   MEDITEJO_SCREENSHOTS=1 MEDITEJO_SHOT_DIR=<dir> \
//     flutter test test/screenshots/mark_moments_screenshots_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/constants/theme/palette_theme.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_moments.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/bottom_navigation/widgets/medito_nav_bar.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import '../helpers/library_app.dart';

final _out = Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'build/shots';
final _palette = IdentityPalettes.byId(
  Platform.environment['MEDITEJO_SHOT_PALETTE'],
);
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';
final _boundary = GlobalKey();

final _day1 = DateTime(2026, 10, 25, 9);
final _day2 = DateTime(2026, 10, 26, 0, 0, 30);

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

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(
      pixelRatio: tester.view.devicePixelRatio,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

final _items = [
  ContinueItem(
    trackId: 't1',
    path: '/tracks/t1',
    title: 'Developing Piti, Developing Focus',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 24),
    courseId: 'c1',
    courseTitle: 'Practising the Jhānas',
    completedSessions: 11,
    sessionTotal: 32,
  ),
];

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });
  tearDown(() => identityClock = DateTime.now);

  const nav = [
    MeditoNavItem(icon: Symbols.home_rounded, label: 'Home'),
    MeditoNavItem(icon: Symbols.search_rounded, label: 'Explore'),
    MeditoNavItem(icon: Symbols.graphic_eq_rounded, label: 'Sounds'),
    MeditoNavItem(icon: Symbols.library_books_rounded, label: 'Library'),
    MeditoNavItem(icon: Symbols.settings_rounded, label: 'Settings'),
  ];

  for (final brightness in Brightness.values) {
    // Home open over midnight: on the next tick the mark turns. Captured at
    // moments of the turn (seconds since it began).
    testWidgets('Home on a new day, ${brightness.name}', (tester) async {
      var now = _day1;
      identityClock = () => now;
      final app = await LibraryTestApp.create(tester);
      await app.prefs.setString(
        SharedPreferenceConstants.homeMarkSeenDay,
        DailyMark.dayKey(_day1),
      );
      await app.pump(
        tester,
        RepaintBoundary(
          key: _boundary,
          child: Theme(
            data: meditejoTheme(brightness, _palette),
            child: Scaffold(
              body: const HomeView(),
              bottomNavigationBar: MeditoNavBar(
                items: nav,
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
        overrides: [continueItemsProvider.overrideWith((ref) async => _items)],
      );
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump(const Duration(seconds: 1));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeView)),
      );
      now = _day2;
      container.read(identityDayProvider.notifier).refresh();
      await tester.pump();
      var at = 0.0;
      for (final s in [0.0, 0.8, 1.5, 2.6, 4.0, 5.4, 7.0]) {
        await tester.pump(Duration(milliseconds: ((s - at) * 1000).round()));
        at = s;
        expect(tester.takeException(), isNull);
        await _capture(
          tester,
          'home-turn-${brightness.name}-${(s * 10).round().toString().padLeft(2, '0')}',
        );
      }
    }, skip: !_enabled);
  }

  testWidgets('the mark turns and breathes, frame by frame', (tester) async {
    final from = MarkGenerator.build(DailyMark.forDay(_day1).seed);
    final to = MarkGenerator.build(DailyMark.forDay(_day2).seed);
    for (final brightness in Brightness.values) {
      final theme = meditejoTheme(brightness, _palette);
      final scheme = theme.colorScheme;
      final colors = theme.extension<MeditejoPalette>()!.markColors(scheme);
      Future<void> frame(String name, MarkPainter painter) async {
        await tester.pumpWidget(
          RepaintBoundary(
            key: _boundary,
            child: ColoredBox(
              color: scheme.surface,
              child: Center(
                child: CustomPaint(
                  size: const Size.square(240),
                  painter: painter,
                ),
              ),
            ),
          ),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(280, 280);
        await _capture(tester, name);
      }

      // The turn, every quarter second for five seconds: these two days,
      // and a scene turning into the same mark (families differ most days).
      for (final (dir, old) in [
        ('turn-frames', from),
        ('turn-frames-scene', MarkGenerator.build('a-1q')),
      ]) {
        for (var i = 0; i <= 20; i++) {
          final s = i * 0.25;
          await frame(
            '$dir/${brightness.name}-${i.toString().padLeft(2, '0')}',
            MarkPainter(
              mark: to,
              colors: colors,
              from: old,
              time: ValueNotifier(s - MarkMoments.morphLead),
            ),
          );
        }
      }
      // A deep breath, long after drawing in: every half second. Today's
      // mark, and a scene (its circle and print finish swell together).
      const rest = 20.0;
      for (final (dir, mark) in [
        ('breath-frames', to),
        ('breath-frames-scene', MarkGenerator.build('a-1q')),
      ]) {
        for (var i = 0; i <= 11; i++) {
          await frame(
            '$dir/${brightness.name}-${i.toString().padLeft(2, '0')}',
            MarkPainter(
              mark: mark,
              colors: colors,
              breathStart: rest,
              time: ValueNotifier(rest + i * 0.5),
            ),
          );
        }
      }
    }
  }, skip: !_enabled);
}
