import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const bundledLicensesDir = 'assets/licenses';
const bundledLicensesManifest =
    '$bundledLicensesDir/newpipe-runtime-dependencies.json';

/// Native code inside flutter_soloud (the Sounds mixer): SoLoud, miniaudio,
/// the Xiph codecs and the rest. Kept apart from the NewPipe manifest, whose
/// inventory CI checks against the extractor's POM closure.
const audioEngineLicensesManifest =
    '$bundledLicensesDir/soloud-native-components.json';

/// One third-party component whose licence notice ships with the app.
class BundledLicense {
  const BundledLicense({
    required this.id,
    required this.title,
    required this.coordinates,
    required this.copyright,
    required this.licenseName,
    required this.licenseUrl,
    required this.sourceUrl,
    required this.texts,
    this.note,
  });

  factory BundledLicense.fromJson(Map<String, dynamic> json) => BundledLicense(
    id: json['id'] as String,
    title: json['title'] as String,
    coordinates: List<String>.from(json['coordinates'] as List),
    copyright: json['copyright'] as String,
    licenseName: json['licenseName'] as String,
    licenseUrl: json['licenseUrl'] as String,
    sourceUrl: json['sourceUrl'] as String,
    texts: List<String>.from(json['texts'] as List),
    note: json['note'] as String?,
  );

  final String id;
  final String title;
  final List<String> coordinates;
  final String copyright;
  final String licenseName;
  final String licenseUrl;
  final String sourceUrl;
  final List<String> texts;
  final String? note;

  /// The package names shown on the licences page.
  List<String> get packages => [title];

  String header() {
    final buffer = StringBuffer()
      ..writeln('$title — $copyright')
      ..writeln('Licence: $licenseName ($licenseUrl)')
      ..writeln('Source: $sourceUrl')
      ..writeln('Used as: ${coordinates.join(', ')}');
    if (note != null) buffer.writeln(note);
    return buffer.toString();
  }
}

Future<List<BundledLicense>> loadBundledLicenses(
  Future<String> Function(String path) load, {
  String manifestPath = bundledLicensesManifest,
}) async {
  final manifest = jsonDecode(await load(manifestPath));
  return [
    for (final c in (manifest as Map<String, dynamic>)['components'] as List)
      BundledLicense.fromJson(c as Map<String, dynamic>),
  ];
}

/// Adds the licence of every bundled NewPipeExtractor runtime dependency to
/// the in-app licences page (Flutter's [LicenseRegistry]).
void registerBundledLicenses({
  Future<String> Function(String path)? load,
  String manifestPath = bundledLicensesManifest,
}) {
  final loader = load ?? rootBundle.loadString;
  LicenseRegistry.addLicense(() async* {
    for (final license in await loadBundledLicenses(
      loader,
      manifestPath: manifestPath,
    )) {
      final body = StringBuffer(license.header());
      for (final text in license.texts) {
        body
          ..writeln()
          ..write(await loader('$bundledLicensesDir/$text'))
          ..writeln();
      }
      yield LicenseEntryWithLineBreaks(license.packages, body.toString());
    }
  });
}
