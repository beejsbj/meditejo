// Screenshots for the identity PR, written to docs/fork/design/identity/.
// Not part of the normal run (they render real fonts and write files):
//
//   MEDITEJO_SCREENSHOTS=1 flutter test test/screenshots/identity_screenshots_test.dart
//
// MEDITEJO_SHOT_DIR writes elsewhere and MEDITEJO_SHOT_PALETTES (ids,
// comma-separated) picks Home's palettes, for comparing variants.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/theme/app_theme.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/providers/home/continue_provider.dart';
import 'package:medito/providers/identity/identity_providers.dart';
import 'package:medito/providers/stats/practice_summary_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/services/home/continue_rules.dart';
import 'package:medito/services/identity/daily_mark.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/views/home/home_view.dart';
import 'package:medito/views/you/you_view.dart';
import 'package:medito/widgets/branding/meditejo_mark.dart';

import '../helpers/library_app.dart';
import '../helpers/stats_fixtures.dart';
import '../helpers/update_fakes.dart';

final _out =
    Platform.environment['MEDITEJO_SHOT_DIR'] ?? 'docs/fork/design/identity';
final _enabled = Platform.environment['MEDITEJO_SCREENSHOTS'] == '1';
final _today = DateTime(2026, 10, 26, 9);

Future<void> _loadFonts() async {
  final sans = FontLoader('Google Sans');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    sans.addFont(rootBundle.load('assets/fonts/google-sans/GoogleSans-$w.ttf'));
  }
  await sans.load();
  // The tester runs from bin/cache/artifacts/engine/<host>/ in the SDK.
  var root = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    root = root.parent;
  }
  await (FontLoader('MaterialIcons')..addFont(
        File(
          '${root.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      ))
      .load();
  // Home's tiles use Material Symbols.
  await (FontLoader(
        'packages/material_symbols_icons/MaterialSymbolsRounded',
      )..addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf',
        ),
      ))
      .load();
}

final _boundary = GlobalKey();

Future<void> _save(ui.Image image, String name) async {
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  File('$_out/$name.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

Future<void> _capture(WidgetTester tester, String name) => tester.runAsync(
  () async {
    final render =
        _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await _save(
      await render.toImage(pixelRatio: tester.view.devicePixelRatio),
      name,
    );
  },
);

/// Everything on screen, including routes above the page (a bottom sheet).
Future<void> _captureView(WidgetTester tester, String name) =>
    tester.runAsync(() async {
      var render = tester.element(find.byType(Navigator).first).renderObject!;
      while (!render.isRepaintBoundary) {
        render = render.parent!;
      }
      final layer = render.debugLayer! as OffsetLayer;
      await _save(await layer.toImage(render.paintBounds), name);
    });

/// [child] in [brightness] under [palette], still (reduced motion).
Widget _frame(Brightness brightness, IdentityPalette palette, Widget child) =>
    RepaintBoundary(
      key: _boundary,
      child: Theme(
        data: meditejoTheme(brightness, palette),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child,
          ),
        ),
      ),
    );

Future<void> _phone(WidgetTester tester) async {
  // An S23+-shaped screen: 1080 × 2340 at 2.625.
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = const Size(1080, 2340);
  await tester.pump();
}

final _items = [
  ContinueItem(
    trackId: 't1',
    path: '/tracks/t1',
    title: 'Developing Piti, Developing Focus',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 25),
    courseId: 'lib-course-a',
    courseTitle: 'Practising the Jhānas',
    resume: const ResumePoint(positionMs: 1800000, durationMs: 5340000),
    sessionNumber: 4,
    sessionTotal: 32,
  ),
  ContinueItem(
    trackId: 't2',
    path: '/tracks/t2',
    title: 'Metta for a difficult person',
    group: LibraryGroup.practice,
    lastPlayed: DateTime(2026, 10, 24),
    courseId: 'lib-course-b',
    courseTitle: 'The Loving Kindness Retreat',
    sessionNumber: 3,
    sessionTotal: 10,
  ),
];

class _Stats extends StatsNotifier {
  _Stats(this.stats);
  final LocalAllStats stats;
  @override
  Future<LocalAllStats> build() async => stats;
}

/// The You tab (with Settings) under [palette], as main.dart themes it.
Future<void> _pumpYou(
  WidgetTester tester,
  Brightness brightness,
  IdentityPalette palette,
) async {
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissions, (call) async => 0);
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null),
  );
  final h = await UpdateHarness.create(prefs: {'identity_palette': palette.id});
  final container = ProviderContainer(
    overrides: [
      ...h.overrides,
      statsProvider.overrideWith(() => _Stats(richStats(fixtureNow))),
      practiceClockProvider.overrideWithValue(() => fixtureNow),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          final p = ref.watch(activePaletteProvider);
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: meditejoTheme(brightness, p),
            home: _frame(brightness, p, const YouView()),
          );
        },
      ),
    ),
  );
  await _phone(tester);
  // Let the app icon's image decode before anything is captured.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });
  setUp(() {
    identityClock = () => _today;
  });
  tearDown(() {
    identityClock = DateTime.now;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  for (final brightness in Brightness.values) {
    for (final id
        in (Platform.environment['MEDITEJO_SHOT_PALETTES'] ??
                'tide,dusk,forest')
            .split(',')) {
      final palette = IdentityPalettes.byId(id);
      testWidgets('Home, ${palette.name}, ${brightness.name}', (tester) async {
        final app = await LibraryTestApp.create(tester);
        await app.pump(
          tester,
          _frame(brightness, palette, const HomeView()),
          overrides: [
            continueItemsProvider.overrideWith((ref) async => _items),
          ],
        );
        await _phone(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await _capture(tester, 'home-$id-${brightness.name}');
      }, skip: !_enabled);
    }

    testWidgets('Settings › Appearance, ${brightness.name}', (tester) async {
      await _pumpYou(tester, brightness, IdentityPalettes.fallback);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings_appearance')),
      );
      await tester.pump(const Duration(seconds: 1));
      await _capture(tester, 'settings-appearance-${brightness.name}');

      await tester.tap(find.byKey(const ValueKey('settings_palette')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _captureView(tester, 'palette-picker-${brightness.name}');
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byKey(const ValueKey('settings_home_mark')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await _captureView(tester, 'home-mark-sheet-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('a week of daily marks, ${brightness.name}', (tester) async {
      final theme = meditejoTheme(brightness);
      final scheme = theme.colorScheme;
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(7 * 136 * 2, 176 * 2);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Theme(
              data: theme,
              child: ColoredBox(
                color: scheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Column(
                            children: [
                              MeditejoMark(
                                mark: MarkGenerator.build(
                                  DailyMark.forDay(
                                    _today.add(Duration(days: i)),
                                  ).seed,
                                ),
                                size: 120,
                                still: true,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DailyMark.dayKey(_today.add(Duration(days: i))),
                                style: theme.textTheme.labelSmall!.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontFamily: 'Google Sans',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await _capture(tester, 'daily-week-${brightness.name}');
    }, skip: !_enabled);

    testWidgets('the launcher icon on a home screen, ${brightness.name}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = const Size(1080, 1500);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _boundary,
          child: _LauncherMock(dark: brightness == Brightness.dark),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await _capture(tester, 'launcher-${brightness.name}');
    }, skip: !_enabled);
  }
}

/// A launcher home screen: a row of plain icons, then the same row with
/// Android 13's themed icons, the house mark among them each time. The
/// house mark is drawn from the generated adaptive layers (the 108 dp SVG,
/// masked to the central 72 dp circle) and its monochrome layer.
class _LauncherMock extends StatelessWidget {
  const _LauncherMock({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final icon = File('assets/branding/house_mark.svg').readAsStringSync();
    final glyph = File(
      'assets/branding/house_mark_glyph.svg',
    ).readAsStringSync();
    final label = TextStyle(
      fontFamily: 'Google Sans',
      fontSize: 12,
      color: dark ? Colors.white : const Color(0xFF1B1B1F),
    );
    const others = [
      (Icons.phone_rounded, Color(0xFF2E7D32)),
      (Icons.mail_rounded, Color(0xFFC62828)),
      (Icons.photo_camera_rounded, Color(0xFF455A64)),
      (Icons.map_rounded, Color(0xFF1565C0)),
    ];
    final themedBg = dark ? const Color(0xFF2B3A3F) : const Color(0xFFCFE6EC);
    final themedFg = dark ? const Color(0xFFB4D0D8) : const Color(0xFF1D3A42);

    Widget adaptive(Widget layer, Color? bg) => ClipOval(
      child: SizedBox.square(
        dimension: 56,
        child: OverflowBox(
          maxWidth: 56 * 108 / 72,
          maxHeight: 56 * 108 / 72,
          child: Container(color: bg, child: layer),
        ),
      ),
    );

    Widget slot(Widget icon, String name) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 6),
        Text(name, style: label),
      ],
    );

    Widget row({required bool themed}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (i, (data, color)) in others.indexed) ...[
          if (i == 2)
            slot(
              themed
                  ? adaptive(
                      SvgPicture.string(
                        glyph,
                        colorFilter: ColorFilter.mode(
                          themedFg,
                          BlendMode.srcIn,
                        ),
                      ),
                      themedBg,
                    )
                  : adaptive(SvgPicture.string(icon), null),
              'Meditejo',
            ),
          slot(
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: themed ? themedBg : color,
              ),
              child: Icon(
                data,
                color: themed ? themedFg : Colors.white,
                size: 28,
              ),
            ),
            ['Phone', 'Mail', 'Camera', 'Maps'][i],
          ),
        ],
      ],
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [Color(0xFF0E151C), Color(0xFF283A44)]
                : const [Color(0xFFDCE7EA), Color(0xFFF4E3D7)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              row(themed: false),
              row(themed: true),
              // Actual size: 48 dp, the launcher's smallest common icon.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.scale(
                    scale: 48 / 56,
                    child: adaptive(SvgPicture.string(icon), null),
                  ),
                  const SizedBox(width: 24),
                  Transform.scale(
                    scale: 48 / 56,
                    child: adaptive(
                      SvgPicture.string(
                        glyph,
                        colorFilter: ColorFilter.mode(
                          themedFg,
                          BlendMode.srcIn,
                        ),
                      ),
                      themedBg,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
