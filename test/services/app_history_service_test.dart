import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/history/app_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppHistoryService.recordCurrentVersion', () {
    test('appends first version with timestamp', () async {
      final prefs = await SharedPreferences.getInstance();

      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '100',
      );

      final history = AppHistoryService.getVersionHistory(prefs);
      expect(history, hasLength(1));
      expect(history.first['version'], '3.6.17');
      expect(history.first['buildNumber'], '100');
      expect(history.first['firstSeenAt'], isA<String>());
      expect(
        DateTime.parse(history.first['firstSeenAt'] as String),
        isA<DateTime>(),
      );
    });

    test('does not duplicate same version+build', () async {
      final prefs = await SharedPreferences.getInstance();

      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '100',
      );
      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '100',
      );

      expect(AppHistoryService.getVersionHistory(prefs), hasLength(1));
    });

    test('appends when buildNumber differs', () async {
      final prefs = await SharedPreferences.getInstance();

      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '100',
      );
      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '101',
      );
      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.18',
        buildNumber: '102',
      );

      final history = AppHistoryService.getVersionHistory(prefs);
      expect(history, hasLength(3));
      expect(
        history.map((e) => '${e['version']}+${e['buildNumber']}').toList(),
        ['3.6.17+100', '3.6.17+101', '3.6.18+102'],
      );
    });
  });

  group('AppHistoryService base64 helpers', () {
    test('empty history returns empty string (not base64 of [])', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(AppHistoryService.getVersionHistoryBase64(prefs), '');
    });

    test('base64 decodes to the same JSON list', () async {
      final prefs = await SharedPreferences.getInstance();
      await AppHistoryService.recordCurrentVersion(
        prefs,
        version: '3.6.17',
        buildNumber: '100',
      );
      final versionB64 = AppHistoryService.getVersionHistoryBase64(prefs);

      final decodedVersions =
          jsonDecode(utf8.decode(base64Decode(versionB64))) as List;
      expect(decodedVersions, hasLength(1));
      expect((decodedVersions.first as Map)['version'], '3.6.17');
    });
  });
}
