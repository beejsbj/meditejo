import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:medito/src/audio_pigeon.g.dart';
import 'package:medito/utils/health_kit_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockHealth extends Mock implements Health {}

class MockBridge extends Mock implements MeditoHealthConnectManager {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockBridge bridge;
  late HealthKitManager manager;
  final start = DateTime(2026, 10, 16);
  final end = start.add(const Duration(minutes: 10));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bridge = MockBridge();
    manager = HealthKitManager.forTesting(
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
    ).thenAnswer((_) async => true);
    when(
      () => bridge.writeMindfulnessSession(any(), any()),
    ).thenAnswer((_) async => true);
  });

  test(
    'new install stays off and completion never requests permission',
    () async {
      expect(await manager.isSyncEnabled(), isFalse);
      expect(await manager.writeMindfulnessData(start, end), isFalse);
      verifyNever(() => bridge.requestMindfulnessPermissions());
      verifyNever(() => bridge.writeMindfulnessSession(any(), any()));
    },
  );

  test('migration preserves a current grant, not a previous prompt', () async {
    SharedPreferences.setMockInitialValues({'healthAuthRequested': true});
    expect(await manager.isSyncEnabled(), isFalse);
    SharedPreferences.setMockInitialValues({});
    when(
      () => bridge.hasMindfulnessPermissions(),
    ).thenAnswer((_) async => true);
    expect(await manager.isSyncEnabled(), isTrue);
    expect(await manager.writeMindfulnessData(start, end), isTrue);
    verifyNever(() => bridge.requestMindfulnessPermissions());
  });

  test('failed migration check stays pending and recovers', () async {
    when(
      () => bridge.hasMindfulnessPermissions(),
    ).thenThrow(Exception('channel down'));
    expect(await manager.isSyncEnabled(), isFalse);
    expect(await manager.writeMindfulnessData(start, end), isFalse);
    when(
      () => bridge.hasMindfulnessPermissions(),
    ).thenAnswer((_) async => true);
    expect(await manager.isSyncEnabled(), isTrue);
    verifyNever(() => bridge.requestMindfulnessPermissions());
  });

  test('failed availability probe keeps migration pending', () async {
    when(() => bridge.getStatus()).thenThrow(Exception('status failed'));
    expect(await manager.isSyncEnabled(), isFalse);
    expect(await manager.writeMindfulnessData(start, end), isFalse);
    when(
      () => bridge.getStatus(),
    ).thenAnswer((_) async => HealthConnectStatus.available);
    when(
      () => bridge.hasMindfulnessPermissions(),
    ).thenAnswer((_) async => true);
    expect(await manager.isSyncEnabled(), isTrue);
    verifyNever(() => bridge.requestMindfulnessPermissions());
  });

  test('explicit off persists even with an OS grant', () async {
    when(
      () => bridge.hasMindfulnessPermissions(),
    ).thenAnswer((_) async => true);
    await manager.setSyncEnabled(false);
    expect(await manager.isSyncEnabled(), isFalse);
    expect(await manager.writeMindfulnessData(start, end), isFalse);
    verifyNever(() => bridge.requestMindfulnessPermissions());
  });

  test('settings enable requests once and denial persists off', () async {
    when(
      () => bridge.requestMindfulnessPermissions(),
    ).thenAnswer((_) async => false);
    expect(await manager.setSyncEnabled(true), isFalse);
    expect(await manager.isSyncEnabled(), isFalse);
    verify(() => bridge.requestMindfulnessPermissions()).called(1);
  });

  test(
    'revoked permission skips completion without requesting again',
    () async {
      expect(await manager.setSyncEnabled(true), isTrue);
      expect(await manager.writeMindfulnessData(start, end), isFalse);
      verify(() => bridge.requestMindfulnessPermissions()).called(1);
      verifyNever(() => bridge.writeMindfulnessSession(any(), any()));
    },
  );

  test(
    'write exceptions are contained without requesting permission',
    () async {
      SharedPreferences.setMockInitialValues({'healthSyncEnabled': true});
      when(
        () => bridge.hasMindfulnessPermissions(),
      ).thenAnswer((_) async => true);
      when(
        () => bridge.writeMindfulnessSession(any(), any()),
      ).thenThrow(Exception('revoked'));
      expect(await manager.writeMindfulnessData(start, end), isFalse);
      verifyNever(() => bridge.requestMindfulnessPermissions());
    },
  );

  test(
    'unavailable Health Connect leaves sync off without a request',
    () async {
      when(
        () => bridge.getStatus(),
      ).thenAnswer((_) async => HealthConnectStatus.notInstalled);
      expect(await manager.setSyncEnabled(true), isFalse);
      expect(await manager.isSyncEnabled(), isFalse);
      verifyNever(() => bridge.requestMindfulnessPermissions());
    },
  );

  test('permission request failure leaves sync off', () async {
    when(
      () => bridge.requestMindfulnessPermissions(),
    ).thenThrow(Exception('unavailable'));
    expect(await manager.setSyncEnabled(true), isFalse);
    expect(await manager.isSyncEnabled(), isFalse);
  });

  test(
    'iOS Settings enable requests permission and persists the result',
    () async {
      final health = MockHealth();
      manager = HealthKitManager.forTesting(health: health, isAndroid: false);
      when(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => health.hasPermissions(
          [HealthDataType.MINDFULNESS],
          permissions: [HealthDataAccess.WRITE],
        ),
      ).thenAnswer((_) async => true);
      expect(await manager.setSyncEnabled(true), isTrue);
      expect(await manager.isSyncEnabled(), isTrue);
      verify(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).called(1);
    },
  );

  test(
    'iOS completion also never requests permission after revocation',
    () async {
      final health = MockHealth();
      manager = HealthKitManager.forTesting(health: health, isAndroid: false);
      SharedPreferences.setMockInitialValues({'healthSyncEnabled': true});
      when(
        () => health.hasPermissions(
          any(),
          permissions: any(named: 'permissions'),
        ),
      ).thenAnswer((_) async => false);
      expect(await manager.writeMindfulnessData(start, end), isFalse);
      verifyNever(
        () => health.requestAuthorization(
          any(),
          permissions: any(named: 'permissions'),
        ),
      );
    },
  );
  test('iOS completed sheet without a write grant leaves sync off', () async {
    final health = MockHealth();
    manager = HealthKitManager.forTesting(health: health, isAndroid: false);
    when(
      () => health.requestAuthorization(
        any(),
        permissions: any(named: 'permissions'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () =>
          health.hasPermissions(any(), permissions: any(named: 'permissions')),
    ).thenAnswer((_) async => false);
    expect(await manager.setSyncEnabled(true), isFalse);
    expect(await manager.isSyncEnabled(), isFalse);
  });
}
