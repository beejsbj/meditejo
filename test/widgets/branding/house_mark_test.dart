import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/identity/mark_spec.dart';

/// The launcher icon comes from the frozen house mark (decision 21: the
/// shelter). Regenerate with `uv run tools/meditejo/branding/make_icons.py`.
void main() {
  final paths = RegExp(r' d="([^"]+)"')
      .allMatches(File('assets/branding/house_mark.svg').readAsStringSync())
      .map((m) => m.group(1)!)
      .toList();
  const res = 'android/app/src/main/res';

  test('the house mark is the frozen shelter', () {
    final mark = MarkSpec.decode(
      File('assets/branding/house_mark.json').readAsStringSync(),
    );
    expect(mark.seed, 'm-2026-10-26');
    expect(mark.type, 'shelter');
    expect(paths, hasLength(2)); // roof and pebble
  });

  test('the adaptive icon has its background, foreground and monochrome '
      'layers, drawn from the house mark', () {
    final adaptive = File(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(adaptive, contains('@drawable/ic_launcher_background'));
    expect(adaptive, contains('@drawable/ic_launcher_foreground'));
    expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
    for (final layer in ['foreground', 'monochrome']) {
      final xml = File(
        '$res/drawable/ic_launcher_$layer.xml',
      ).readAsStringSync();
      for (final d in paths) {
        expect(xml, contains('android:pathData="$d"'), reason: layer);
      }
    }
    expect(
      File('$res/drawable/ic_launcher_monochrome.xml').readAsStringSync(),
      isNot(contains('#1E2C3A')),
    );
    expect(
      File('$res/drawable/ic_launcher_background.xml').readAsStringSync(),
      contains('#E5EAEC'), // Tidewater's tile
    );
  });

  test('no build flavour overrides the launcher icon', () {
    for (final flavour in Directory('android/app/src').listSync()) {
      if (flavour is! Directory || flavour.path.endsWith('/main')) continue;
      final res = Directory('${flavour.path}/res');
      if (!res.existsSync()) continue;
      final overrides = res
          .listSync(recursive: true)
          .where(
            (f) => f.path.contains('/mipmap') && f.path.contains('ic_launcher'),
          );
      expect(overrides, isEmpty, reason: flavour.path);
    }
  });
}
