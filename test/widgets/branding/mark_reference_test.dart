// The Dart port against the exploration page: the same seed must draw
// visibly the same mark. The references are PNGs rendered from the page's
// own generator (tools/meditejo/branding/reference/render_reference.py), so
// they are compared with a tolerance for antialiasing, not pixel for pixel.
//
// To look at the Dart side and the difference, run with
// MEDITEJO_MARK_DIFF=/some/dir.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/identity/mark_generator.dart';
import 'package:medito/services/identity/mark_spec.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/branding/mark_painter.dart';
import 'package:medito/widgets/branding/mark_textures.dart';

const _dir = 'test/widgets/branding/reference';
const _px = 256;

Future<Uint8List> _rgba(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawStraightRgba,
))!.buffer.asUint8List();

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

/// The house mark as frozen in assets/branding/house_mark.json (Clear V:
/// the minimal shelter with its M-notch), as an app pin would carry it.
MarkSpec _houseMark() =>
    MarkSpec.decode(File('assets/branding/house_mark.json').readAsStringSync());

ui.Image _render(
  String seed, {
  double t = 60,
  bool still = true,
  MarkSpec? mark,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_px.toDouble());
  MarkRenderer(
    canvas,
    MarkColors.of(IdentityPalettes.byId('tide')),
    textures: MarkTextures.instance,
    texel: 1 / _px,
  ).draw(mark ?? MarkGenerator.build(seed), t, still: still, finish: false);
  return recorder.endRecording().toImageSync(_px, _px);
}

/// Mean absolute difference per channel (0–255), and the share of pixels
/// that differ by more than 64 in any channel.
({double mean, double off}) _compare(Uint8List a, Uint8List b) {
  var sum = 0, off = 0;
  for (var i = 0; i < a.length; i += 4) {
    var worst = 0;
    for (var k = 0; k < 3; k++) {
      final d = (a[i + k] - b[i + k]).abs();
      sum += d;
      if (d > worst) worst = d;
    }
    if (worst > 64) off++;
  }
  final pixels = a.length ~/ 4;
  return (mean: sum / (pixels * 3), off: off / pixels);
}

Future<void> _writeDiff(String name, Uint8List dart, Uint8List page) async {
  final dir = Platform.environment['MEDITEJO_MARK_DIFF'];
  if (dir == null) return;
  Future<void> png(String file, Uint8List rgba) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _px,
      height: _px,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final image =
        (await (await descriptor.instantiateCodec()).getNextFrame()).image;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$file').writeAsBytesSync(bytes!.buffer.asUint8List());
  }

  Directory(dir).createSync(recursive: true);
  final diff = Uint8List(dart.length);
  for (var i = 0; i < dart.length; i += 4) {
    for (var k = 0; k < 3; k++) {
      diff[i + k] = 255 - ((dart[i + k] - page[i + k]).abs() * 4).clamp(0, 255);
    }
    diff[i + 3] = 255;
  }
  await png('$name.dart.png', dart);
  await png('$name.diff.png', diff);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // Six or more seeds across the three families, settled, plus frames
  // caught mid-drawing and mid-breath.
  const cases = <(String, double, bool)>[
    ('g-1kq', 60, true), // gesture shelter
    ('g-1cq', 60, true), // doorway
    ('g-28q', 60, true), // ensō (brush taper)
    ('m-2026-10-26', 60, true), // minimal shelter, the launcher icon
    ('m-1nq', 60, true), // split sun (clips)
    ('m-1zq', 60, true), // vesica (clip, three inks)
    ('a-1q', 60, true), // lit doorway
    ('a-3q', 60, true), // ridges in mist
    ('a-dq', 60, true), // halo (a stroke in an atmospheric scene)
    ('g-1kq', 1.6, false),
    ('m-2026-10-26', 1.6, false),
    ('a-dq', 1.6, false),
    // Mid-breath: every round shape between circle and pebble, ridges
    // drifting, rings opening.
    ('g-1kq', 7.3, false),
    ('m-2026-10-26', 7.3, false),
    ('m-1zq', 7.3, false),
    ('a-3q', 7.3, false),
    ('a-dq', 7.3, false),
  ];

  // The house mark, drawn from its frozen JSON, against the page drawing the
  // same shelter with round 6's notch (render_reference.py --values
  // notch=0.045,nw=0.065): settled, mid-draw and mid-breath.
  const houseCases = <(String, double, bool)>[
    ('m-2026-10-26-clearv', 60, true),
    ('m-2026-10-26-clearv@1.6s', 1.6, false),
    ('m-2026-10-26-clearv@7.3s', 7.3, false),
  ];

  testWidgets('the frozen house mark carries the notch', (tester) async {
    final house = _houseMark() as MinimalMark;
    expect(house.values['notch'], 0.045);
    expect(house.values['nw'], 0.065);
    // The seed alone still draws the shelter as first shipped.
    expect(
      (MarkGenerator.build(house.seed) as MinimalMark).values['notch'],
      isNull,
    );
  });

  // The plain shelter misses the Clear V reference by 2.2/255 and 1.1% of
  // pixels, twice what the cases below allow, so they cannot pass without
  // the notch.
  testWidgets('the notch is a mark of its own, not the plain shelter', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await MarkTextures.instance.load();
      final page = await _rgba(await _decode('$_dir/m-2026-10-26-clearv.png'));
      final plain = _compare(await _rgba(_render('m-2026-10-26')), page);
      expect(
        plain.mean >= 1.0 || plain.off >= 0.005,
        isTrue,
        reason:
            'the plain shelter passed as Clear V: ${plain.mean}, ${plain.off}',
      );
    });
  });

  for (final (name, t, still) in houseCases) {
    testWidgets('$name (the house mark) draws as on the exploration page', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await MarkTextures.instance.load();
        final dart = await _rgba(
          _render('', t: t, still: still, mark: _houseMark()),
        );
        final page = await _rgba(await _decode('$_dir/$name.png'));
        await _writeDiff(name, dart, page);
        final r = _compare(dart, page);
        // ignore: avoid_print
        print(
          '$name: mean ${r.mean.toStringAsFixed(3)}, '
          '${(r.off * 100).toStringAsFixed(3)}% off',
        );
        expect(r.mean, lessThan(1.0), reason: '$name: ${r.mean}');
        expect(r.off, lessThan(0.005), reason: '$name: ${r.off}');
      });
    });
  }

  testWidgets('the comparison tells two marks apart', (tester) async {
    await tester.runAsync(() async {
      await MarkTextures.instance.load();
      final page = await _rgba(await _decode('$_dir/g-1kq.png'));
      for (final other in ['g-1cq', 'g-1kq-x', 'm-1lq']) {
        final r = _compare(await _rgba(_render(other)), page);
        expect(
          r.mean >= 2.5 || r.off >= 0.01,
          isTrue,
          reason: '$other passed as g-1kq: ${r.mean}, ${r.off}',
        );
      }
    });
  });

  for (final (seed, t, still) in cases) {
    final name = still ? seed : '$seed@${t}s';
    testWidgets('$name draws as on the exploration page', (tester) async {
      await tester.runAsync(() async {
        await MarkTextures.instance.load();
        final dart = await _rgba(_render(seed, t: t, still: still));
        final page = await _rgba(await _decode('$_dir/$name.png'));
        await _writeDiff(name, dart, page);
        final r = _compare(dart, page);
        // ignore: avoid_print
        print(
          '$name: mean ${r.mean.toStringAsFixed(3)}, '
          '${(r.off * 100).toStringAsFixed(3)}% off',
        );
        expect(
          r.mean,
          lessThan(1.0),
          reason: '$name: mean difference ${r.mean.toStringAsFixed(2)}',
        );
        expect(
          r.off,
          lessThan(0.005),
          reason: '$name: ${(r.off * 100).toStringAsFixed(2)}% of pixels off',
        );
      });
    });
  }
}
