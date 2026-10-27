// The Dart art engine against the identity page: the same frozen
// composition must draw visibly the same card. References are PNGs (and
// the frozen composition each one drew) rendered by the page's own code:
//
//     python3 -I tools/meditejo/art/reference/render_reference.py \
//         SPECS.json test/widgets/art/reference
//
// They are compared with a tolerance for antialiasing, not pixel for pixel.
//
// A reference's name says how it was drawn:
// `NAME[.ground|.figure][%h<height/width>][@<seconds>]`; `.ground` is the
// ground alone, `.figure` the figures on flat paper, and without `@` the
// frame is still.
//
// While porting, point it at a wider set and filter by primitive:
//
//     MEDITEJO_ART_REF=/tmp/art-ref MEDITEJO_ART_ONLY=mist,waves \
//     MEDITEJO_ART_DIFF=/tmp/art-diff flutter test test/widgets/art/art_reference_test.dart
//
// MEDITEJO_ART_DIFF writes the Dart side and a difference image per case.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/identity/palettes.dart';
import 'package:medito/widgets/art/engine/art_core.dart';
import 'package:medito/widgets/art/engine/art_textures.dart';
import 'package:medito/widgets/art/engine/compose.dart';
import 'package:medito/widgets/art/engine/registry.dart';

final _dir =
    Platform.environment['MEDITEJO_ART_REF'] ?? 'test/widgets/art/reference';
final _only = Platform.environment['MEDITEJO_ART_ONLY']
    ?.split(',')
    .where((s) => s.isNotEmpty)
    .toSet();
final _diffDir = Platform.environment['MEDITEJO_ART_DIFF'];
const _px = 256;

typedef _Case = ({
  String name,
  ArtComposition comp,
  String? only,
  double h,
  double t,
  bool still,
});

_Case _parse(String name, Map<String, Object?> frozen) {
  final m = RegExp(
    r'^(.*?)(\.ground|\.figure)?(%h[0-9.]+)?(@[0-9.]+)?$',
  ).firstMatch(name)!;
  final t = m.group(4);
  return (
    name: name,
    comp: ArtComposition.thaw(frozen),
    only: m.group(2)?.substring(1),
    h: m.group(3) == null ? 1.0 : double.parse(m.group(3)!.substring(2)),
    t: t == null ? 60.0 : double.parse(t.substring(1)),
    still: t == null,
  );
}

/// The primitives a case draws.
Set<String> _uses(_Case c) => {
  if (c.only != 'figure') c.comp.ground.name,
  if (c.only == 'figure') 'paper',
  if (c.only != 'ground') ...[
    if (c.comp.figure != null) c.comp.figure!.name,
    if (c.comp.accent != null) c.comp.accent!.name,
  ],
};

Future<Uint8List> _rgba(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawStraightRgba,
))!.buffer.asUint8List();

Future<ui.Image> _decode(String path) async {
  final codec = await ui.instantiateImageCodec(File(path).readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<ui.Image> _render(_Case c) async {
  final roles = ArtRoles.of(IdentityPalettes.byId('tide'));
  final ph = (_px * c.h).round();
  final finish = await ArtTextures.instance.finishFor(roles, _px, c.h);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_px.toDouble());
  final ctx = Ctx(canvas);
  Compose.draw(ctx, c.comp, roles, c.t, still: c.still, H: c.h, only: c.only);
  if (finish != null) ctx.drawImage(finish, 0, 0, 1, c.h);
  return recorder.endRecording().toImageSync(_px, ph);
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

Future<void> _writeDiff(
  String name,
  Uint8List dart,
  Uint8List page,
  int w,
  int h,
) async {
  final dir = _diffDir;
  if (dir == null) return;
  Future<void> png(String file, Uint8List rgba) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: w,
      height: h,
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

List<_Case> _cases() {
  final dir = Directory(_dir);
  if (!dir.existsSync()) return const [];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      _parse(
        f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
        (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>(),
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cases = _cases();

  test('there are references to check', () {
    expect(cases, isNotEmpty, reason: 'no references in $_dir');
  });

  for (final c in cases) {
    final uses = _uses(c);
    final only = _only;
    if (only != null && !uses.any(only.contains)) continue;
    final missing = uses.where(
      (n) =>
          !ArtRegistry.grounds.containsKey(n) &&
          !ArtRegistry.figures.containsKey(n),
    );
    testWidgets(
      '${c.name} draws as on the identity page',
      skip: missing.isNotEmpty,
      (tester) async {
        await tester.runAsync(() async {
          await ArtTextures.instance.load();
          final image = await _render(c);
          final dart = await _rgba(image);
          final page = await _rgba(await _decode('$_dir/${c.name}.png'));
          expect(dart.length, page.length, reason: 'sizes differ');
          await _writeDiff(c.name, dart, page, image.width, image.height);
          final r = _compare(dart, page);
          // ignore: avoid_print
          print(
            '${c.name}: mean ${r.mean.toStringAsFixed(3)}, '
            '${(r.off * 100).toStringAsFixed(3)}% off',
          );
          expect(
            r.mean,
            lessThan(1.0),
            reason: '${c.name}: mean difference ${r.mean.toStringAsFixed(2)}',
          );
          expect(
            r.off,
            lessThan(0.005),
            reason:
                '${c.name}: ${(r.off * 100).toStringAsFixed(2)}% of pixels off',
          );
        });
      },
    );
  }
}
