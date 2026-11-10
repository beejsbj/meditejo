import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/local_all_stats.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/notification/reminder_provider.dart';
import 'package:medito/providers/stats_provider.dart';
import 'package:medito/utils/stats_manager.dart';
import 'package:medito/views/end_screen/end_screen_view.dart';
import 'package:medito/views/previews/preview_support.dart';
import 'package:medito/views/settings/battery_optimization_screen.dart';
import 'package:medito/views/settings/widgets/reminder_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Scheduling stands in: the notifications plugin has no platform here.
class _QuietReminders implements ReminderProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _EmptyStats extends StatsNotifier {
  @override
  Future<LocalAllStats> build() async => LocalAllStats.empty();
}

const _permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
const _battery = MethodChannel('in.jvapps.disable_battery_optimization');

/// Notifications are already allowed, so turning a reminder on asks nothing.
void _grantNotifications() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_permissions, (call) async {
    return switch (call.method) {
      'checkPermissionStatus' => 1,
      'requestPermissions' => {17: 1},
      _ => null,
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(_permissions, null));
}

/// StatsManager is a singleton holding futures from the test that used it
/// last; start it afresh inside this test's zone.
void _freshStats() => StatsManager().resetForTesting();

/// Leave the app for the phone's settings (or the plugin's dialog) and come
/// back.
Future<void> _leaveAndReturn(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    // Reminders are scheduled in the phone's zone.
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  setUp(() {
    // The reminder text reads the streak through StatsManager's own prefs.
    SharedPreferences.setMockInitialValues({});
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('whether the row is needed is read again on every return', (
    tester,
  ) async {
    var held = true;
    var checks = 0;
    final container = ProviderContainer(
      overrides: [
        batteryGuidanceCheckProvider.overrideWithValue(() async {
          checks++;
          return held;
        }),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(batteryGuidanceNeededProvider, (_, _) {});
    addTearDown(sub.close);
    expect(await container.read(batteryGuidanceNeededProvider.future), isTrue);
    expect(checks, 1);

    // The user lets Meditejo run in the phone's settings, then comes back.
    held = false;
    await _leaveAndReturn(tester);
    expect(checks, greaterThan(1));
    expect(await container.read(batteryGuidanceNeededProvider.future), isFalse);
  });

  group('the battery page', () {
    late List<MethodCall> pluginCalls;
    late bool held;

    Future<void> pumpPage(WidgetTester tester) async {
      pluginCalls = [];
      held = true;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_battery, (call) async {
        pluginCalls.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_battery, null));
      await tester.pumpWidget(
        PreviewShell(
          prefs: const {},
          locale: const Locale('es'),
          overrides: [
            batteryGuidanceCheckProvider.overrideWithValue(() async => held),
          ],
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const BatteryOptimizationScreen(),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('gives the phone its dialogs in the app\'s language', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('battery_open')));
      await tester.pumpAndSettle();
      expect(pluginCalls.single.method, 'disableAllOptimizations');
      expect(pluginCalls.single.arguments, [
        'Deja que Meditejo se inicie solo',
        startsWith('Tu teléfono impide'),
        'Un ajuste de batería más',
        startsWith('Tu teléfono también'),
      ]);
    });

    testWidgets('stays open over the plugin\'s own dialog, and closes once '
        'Meditejo may run', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('battery_open')));
      await tester.pumpAndSettle();

      // The plugin's dialog pauses and resumes the app; nothing has changed.
      await _leaveAndReturn(tester);
      expect(find.byType(BatteryOptimizationScreen), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);

      // Back from the phone's settings, now unrestricted.
      held = false;
      await _leaveAndReturn(tester);
      expect(find.byType(BatteryOptimizationScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('turning on the first daily reminder never opens the battery page', () {
    List<Override> overrides(bool held) => [
      reminderProvider.overrideWithValue(_QuietReminders()),
      statsProvider.overrideWith(_EmptyStats.new),
      batteryGuidanceCheckProvider.overrideWithValue(() async => held),
    ];

    for (final held in [true, false]) {
      testWidgets('from Settings, on a phone that '
          '${held ? 'holds' : 'does not hold'} the app back', (tester) async {
        _grantNotifications();
        _freshStats();
        await tester.pumpWidget(
          PreviewShell(
            prefs: const {},
            locale: const Locale('en'),
            overrides: overrides(held),
            child: const Scaffold(body: ReminderTile()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ReminderTile));
        await tester.pumpAndSettle();
        await tester.tap(
          find.textContaining('Morning', findRichText: true).last,
        );
        await tester.pumpAndSettle();

        // The reminder is on, and the page stays in Settings for whoever
        // wants it.
        expect(find.byType(BatteryOptimizationScreen), findsNothing);
        expect(find.text('Keep Meditejo running'), findsNothing);
      });
    }

    testWidgets('from the end-of-session card', (tester) async {
      _grantNotifications();
      _freshStats();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        PreviewShell(
          prefs: const {},
          locale: const Locale('en'),
          overrides: overrides(true),
          child: const EndScreenView(
            request: PlaybackRequest(
              trackId: 'preview',
              fileId: 'preview-file',
              title: 'Noting Thoughts',
              description: '',
              coverUrl: '',
              remoteUrl: 'https://example.test/audio.mp3',
              duration: 600000,
              hasBackgroundSound: false,
              guideName: 'Will',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      final turnOn = find.text('Turn on reminders');
      await tester.ensureVisible(turnOn);
      await tester.tap(turnOn);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Morning', findRichText: true).last);
      await tester.pumpAndSettle();

      // Even on a phone that holds the app back.
      expect(find.byType(BatteryOptimizationScreen), findsNothing);
      expect(find.text('Keep Meditejo running'), findsNothing);
      expect(find.text('Turn on reminders'), findsNothing);
    });
  });
}
