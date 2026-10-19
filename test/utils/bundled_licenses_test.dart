import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/utils/bundled_licenses.dart';

// Runtime closure of com.github.TeamNewPipe:NewPipeExtractor:v0.26.5, from its
// published POM and Gradle metadata (none of the six has further runtime
// dependencies). Changing the pin means re-deriving this list; the
// "YouTube dependency" workflow checks it against the live POMs.
const _expectedCoordinates = {
  'com.github.TeamNewPipe:NewPipeExtractor:v0.26.5',
  'com.github.TeamNewPipe:nanojson:e9d656ddb49a412a5a0a5d5ef20ca7ef09549996',
  'org.jsoup:jsoup:1.22.2',
  'com.google.code.findbugs:jsr305:3.0.2',
  'com.google.protobuf:protobuf-javalite:4.35.1',
  'org.mozilla:rhino:1.8.1',
  'org.mozilla:rhino-engine:1.8.1',
};

Future<String> _readAsset(String path) => File(path).readAsString();

Future<Map<String, String>> _registeredLicenses() async {
  LicenseRegistry.reset();
  registerBundledLicenses(load: _readAsset);
  final byPackage = <String, String>{};
  await for (final entry in LicenseRegistry.licenses) {
    final text = entry.paragraphs.map((p) => p.text).join('\n');
    for (final package in entry.packages) {
      byPackage[package] = text;
    }
  }
  return byPackage;
}

void main() {
  late List<BundledLicense> licenses;

  setUpAll(() async {
    licenses = await loadBundledLicenses(_readAsset);
  });

  tearDownAll(LicenseRegistry.reset);

  group('dependency inventory', () {
    test('covers exactly the NewPipeExtractor runtime closure', () {
      final listed = [for (final l in licenses) ...l.coordinates];
      expect(listed.toSet(), _expectedCoordinates);
      expect(listed.length, listed.toSet().length, reason: 'no duplicates');
    });

    test('the pinned extractor version matches the Gradle dependency', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      final pin = RegExp(
        r'"(com\.github\.TeamNewPipe:NewPipeExtractor:v[\d.]+)"',
      ).firstMatch(gradle)!.group(1);
      final manifest =
          jsonDecode(File(bundledLicensesManifest).readAsStringSync())
              as Map<String, dynamic>;
      expect(pin, manifest['extractor']);
      expect(_expectedCoordinates, contains(pin));
    });

    test('every component names its copyright, licence and source', () {
      for (final l in licenses) {
        expect(l.copyright, isNotEmpty, reason: l.id);
        expect(l.licenseName, isNotEmpty, reason: l.id);
        expect(Uri.parse(l.licenseUrl).scheme, 'https', reason: l.id);
        expect(Uri.parse(l.sourceUrl).scheme, 'https', reason: l.id);
        expect(l.texts, isNotEmpty, reason: l.id);
      }
    });
  });

  group('licence assets', () {
    test('every referenced text exists and is a complete, non-empty file', () {
      for (final l in licenses) {
        for (final name in l.texts) {
          final file = File('$bundledLicensesDir/$name');
          expect(file.existsSync(), isTrue, reason: '$name for ${l.id}');
          expect(file.readAsStringSync().trim().length, greaterThan(500));
        }
      }
    });

    test('the whole directory is bundled by pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('    - $bundledLicensesDir/\n'));
    });

    test('texts are the upstream licences', () {
      String text(String name) =>
          File('$bundledLicensesDir/$name').readAsStringSync();
      expect(text('Apache-2.0.txt'), contains('Apache License'));
      expect(text('Apache-2.0.txt'), contains('END OF TERMS AND CONDITIONS'));
      expect(
        text('Apache-2.0-nanojson-notice.txt'),
        contains('Copyright 2011 The nanojson Authors'),
      );
      expect(text('MIT-jsoup.txt'), contains('Jonathan Hedley'));
      expect(text('MIT-jsoup.txt'), contains('Permission is hereby granted'));
      expect(text('BSD-3-Clause-jsr305.txt'), contains('JSR305 expert group'));
      expect(text('BSD-3-Clause-protobuf.txt'), contains('Google Inc.'));
      for (final bsd in ['jsr305', 'protobuf']) {
        expect(
          text('BSD-3-Clause-$bsd.txt'),
          contains('Redistributions in binary form'),
        );
      }
      expect(text('MPL-2.0-Rhino.txt'), contains('Mozilla Public License'));
      expect(text('MPL-2.0-Rhino.txt'), contains('Version 2.0'));
      expect(text('Rhino-NOTICE.txt'), contains('V8 project authors'));
      expect(text('Rhino-NOTICE.txt'), contains('Raffaello Giulietti'));
      expect(
        text('NewPipeExtractor-GPL-3.0.txt'),
        contains('GNU GENERAL PUBLIC LICENSE'),
      );
    });

    test(
      'Rhino points at source for the exact version, MPL-2.0 section 3.2',
      () {
        final rhino = licenses.firstWhere((l) => l.id == 'rhino');
        expect(rhino.sourceUrl, endsWith('/tree/Rhino1_8_1_Release'));
        expect(rhino.note, contains('rhino-1.8.1-sources.jar'));
        expect(rhino.note, contains('rhino-engine-1.8.1-sources.jar'));
        expect(rhino.note, contains('unmodified'));
      },
    );
  });

  group('LicenseRegistry', () {
    test(
      'exposes every component with its notice, source and full text',
      () async {
        final registered = await _registeredLicenses();
        expect(registered.keys.toSet(), {for (final l in licenses) l.title});
        for (final l in licenses) {
          final body = registered[l.title]!;
          expect(body, contains(l.copyright), reason: l.id);
          expect(body, contains(l.sourceUrl), reason: l.id);
          expect(body, contains(l.licenseName), reason: l.id);
          for (final coordinate in l.coordinates) {
            expect(body, contains(coordinate), reason: l.id);
          }
          for (final name in l.texts) {
            final first = File(
              '$bundledLicensesDir/$name',
            ).readAsStringSync().trim().split('\n').first.trim();
            expect(body, contains(first), reason: '$name in ${l.id}');
          }
        }
      },
    );
  });

  group('Gradle packaging and JitPack scoping', () {
    final appGradle = File('android/app/build.gradle').readAsStringSync();
    final rootGradle = File('android/build.gradle').readAsStringSync();
    final settingsGradle = File('android/settings.gradle').readAsStringSync();

    test('every JitPack repository is limited to com.github.TeamNewPipe', () {
      for (final (name, source) in [
        ('build.gradle', rootGradle),
        ('settings.gradle', settingsGradle),
        ('app/build.gradle', appGradle),
      ]) {
        final blocks = RegExp(
          r"maven\s*\{[^{}]*jitpack\.io[^{}]*(?:\{[^{}]*\}[^{}]*)*\}",
        ).allMatches(source).toList();
        final mentions = 'jitpack.io'.allMatches(source).length;
        // The guard in build.gradle names jitpack.io once more.
        final guards = name == 'build.gradle' ? 1 : 0;
        expect(blocks.length, mentions - guards, reason: name);
        for (final block in blocks) {
          expect(
            block.group(0),
            contains("includeGroup 'com.github.TeamNewPipe'"),
            reason: name,
          );
        }
      }
    });

    test('plugin resolution never consults JitPack', () {
      final pluginManagement = settingsGradle.substring(
        0,
        settingsGradle.indexOf('plugins {'),
      );
      expect(pluginManagement, isNot(contains('jitpack')));
    });

    test('unscoped JitPack repositories added by plugins are removed', () {
      expect(rootGradle, contains('gradle.projectsEvaluated'));
      expect(rootGradle, contains("it.name != 'JitPackTeamNewPipe'"));
    });

    test('licence and notice paths are merged, not excluded or picked', () {
      const legal = [
        'META-INF/LICENSE',
        'META-INF/LICENSE.txt',
        'META-INF/license.txt',
        'META-INF/NOTICE',
        'META-INF/NOTICE.txt',
        'META-INF/notice.txt',
        'META-INF/ASL2.0',
        'META-INF/DEPENDENCIES',
        'META-INF/COPYRIGHT',
        'LICENSE',
        'LICENSE.txt',
        'NOTICE',
        'NOTICE.txt',
      ];
      final merges = RegExp(
        r'merges \+= \[(.*?)\]',
        dotAll: true,
      ).firstMatch(appGradle)!.group(1)!;
      final restoredDefaults = RegExp(
        r'excludes -= \[(.*?)\]',
        dotAll: true,
      ).firstMatch(appGradle)!.group(1)!;
      for (final path in [
        'META-INF/LICENSE',
        'META-INF/LICENSE.txt',
        'META-INF/NOTICE',
        'META-INF/NOTICE.txt',
        'LICENSE',
        'LICENSE.txt',
        'NOTICE',
        'NOTICE.txt',
      ]) {
        expect(
          restoredDefaults,
          contains("'/$path'"),
          reason: 'AGP default $path',
        );
      }
      for (final path in legal) {
        expect(merges, contains("'$path'"), reason: path);
        expect(appGradle, isNot(contains("exclude '$path'")), reason: path);
        expect(appGradle, isNot(contains("pickFirst '$path'")), reason: path);
      }
    });
  });
}
