import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:health/health.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:medito/utils/health_kit_manager.dart';
import 'package:medito/views/settings/health_sync_tile.dart';
import 'package:mocktail/mocktail.dart';

class MockHealth extends Mock implements Health {}

class MockBridge extends Mock implements MeditoHealthConnectManager {}

void main() {
  for (final granted in [true, false]) {
    testWidgets('Settings switch requests permission; granted=$granted', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final bridge = MockBridge();
      final manager = HealthKitManager.forTesting(
        health: MockHealth(),
        isAndroid: true,
        androidBridge: bridge,
      );
      when(
        () => bridge.getStatus(),
      ).thenAnswer((_) async => HealthConnectStatus.available);
      when(
        () => bridge.hasMindfulnessPermissions(),
      ).thenAnswer((_) async => false);
      when(
        () => bridge.requestMindfulnessPermissions(),
      ).thenAnswer((_) async => granted);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: HealthSyncTile(manager: manager)),
        ),
      );
      await tester.pumpAndSettle();
      verifyNever(() => bridge.requestMindfulnessPermissions());
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      verify(() => bridge.requestMindfulnessPermissions()).called(1);
      expect(await manager.isSyncEnabled(), granted);
      expect(tester.widget<Switch>(find.byType(Switch)).value, granted);
      if (!granted) {
        expect(
          find.text(
            'Health sync is off. You can allow access in Settings whenever you’re ready.',
          ),
          findsOneWidget,
        );
      } else {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        verifyNever(() => bridge.requestMindfulnessPermissions());
        expect(await manager.isSyncEnabled(), isFalse);
        expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      }
    });
  }
}
