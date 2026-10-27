// The Dart composition builder against the identity page: built from the
// same class and seed, a composition must freeze to the same plain data as
// the page's. The references are the frozen JSON that
// tools/meditejo/art/reference/render_reference.py writes beside each PNG;
// only cards built from a class and seed (named `<class>-<n>`, seed
// `<class>#<n>`, as dev_specs.py writes them) are checked.
//
//     MEDITEJO_ART_REF=/tmp/art-ref MEDITEJO_ART_ONLY=mist,waves \
//     flutter test test/widgets/art/art_build_parity_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/art/engine/compose.dart';
import 'package:medito/widgets/art/engine/registry.dart';

final _dir = Platform.environment['MEDITEJO_ART_REF'];
final _only = Platform.environment['MEDITEJO_ART_ONLY']
    ?.split(',')
    .where((s) => s.isNotEmpty)
    .toSet();

/// Every leaf of [a] equals [b]'s, numbers to within rounding.
void _same(Object? a, Object? b, String path) {
  if (a is Map && b is Map) {
    expect(a.keys.toSet(), b.keys.toSet(), reason: '$path: keys');
    for (final k in a.keys) {
      _same(a[k], b[k], '$path.$k');
    }
  } else if (a is List && b is List) {
    expect(a.length, b.length, reason: '$path: length');
    for (var i = 0; i < a.length; i++) {
      _same(a[i], b[i], '$path[$i]');
    }
  } else if (a is num && b is num) {
    expect(
      (a - b).abs(),
      lessThanOrEqualTo(1.0001e-4),
      reason: '$path: $a vs $b',
    );
  } else {
    expect(a, b, reason: path);
  }
}

void main() {
  final path = _dir;
  final dir = path == null ? null : Directory(path);
  final files = dir == null || !dir.existsSync()
      ? <File>[]
      : (dir
            .listSync()
            .whereType<File>()
            .where((f) => RegExp(r'/[a-z]+-\d+\.json$').hasMatch(f.path))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)));

  test('there are references to check', () {
    expect(files, isNotEmpty, reason: 'set MEDITEJO_ART_REF');
  }, skip: _dir == null);

  for (final f in files) {
    final name = f.uri.pathSegments.last.replaceFirst('.json', '');
    final page = (jsonDecode(f.readAsStringSync()) as Map)
        .cast<String, Object?>();
    final uses = <String>{
      (page['ground']! as Map)['name']! as String,
      if (page['figure'] != null) (page['figure']! as Map)['name']! as String,
      if (page['accent'] != null) (page['accent']! as Map)['name']! as String,
    };
    final only = _only;
    if (only != null && !uses.any(only.contains)) continue;
    final ready = uses.every(
      (n) =>
          ArtRegistry.grounds.containsKey(n) ||
          ArtRegistry.figures.containsKey(n),
    );
    test('$name builds as on the identity page', () {
      final cut = name.lastIndexOf('-');
      final cls = name.substring(0, cut),
          seed = '$cls#${name.substring(cut + 1)}';
      final dart = Compose.build(cls, seed).freeze();
      _same(jsonDecode(jsonEncode(dart)), page, name);
    }, skip: !ready);
  }
}
