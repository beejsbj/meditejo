import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/utils/bundled_licenses.dart';

Future<String> _readAsset(String path) => File(path).readAsString();

void main() {
  tearDownAll(LicenseRegistry.reset);

  test(
    'every native component of the mixer carries its licence text',
    () async {
      final licenses = await loadBundledLicenses(
        _readAsset,
        manifestPath: audioEngineLicensesManifest,
      );
      expect(
        licenses.map((l) => l.id),
        containsAll(<String>[
          'soloud',
          'miniaudio',
          'libogg',
          'libvorbis',
          'libopus',
          'libflac',
        ]),
      );
      for (final license in licenses) {
        expect(license.texts, isNotEmpty, reason: license.id);
        for (final text in license.texts) {
          final body = File('$bundledLicensesDir/$text').readAsStringSync();
          expect(body.trim(), isNotEmpty, reason: text);
        }
      }
    },
  );

  test('they reach the in-app licences page', () async {
    LicenseRegistry.reset();
    registerBundledLicenses(
      load: _readAsset,
      manifestPath: audioEngineLicensesManifest,
    );
    final packages = <String>{};
    await for (final entry in LicenseRegistry.licenses) {
      packages.addAll(entry.packages);
    }
    expect(packages, containsAll(<String>['SoLoud', 'miniaudio', 'libopus']));
  });
}
