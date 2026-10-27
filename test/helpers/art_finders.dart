import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';

/// An [ArtCover] drawing exactly [subject].
Finder findArt(ArtSubject subject) => find.byWidgetPredicate(
  (w) => w is ArtCover && w.subject == subject,
  description: 'ArtCover(${subject.key})',
);

/// The subjects of every [ArtCover] in the tree, as their keys.
Set<String> artKeys(WidgetTester tester) => {
  for (final w in tester.widgetList<ArtCover>(find.byType(ArtCover)))
    w.subject.key,
};

/// Keeps the curated art file from loading in the background during a test:
/// until it's in, [ArtCover] draws a flat tone, so a test about wiring doesn't
/// depend on the painters. Call from `setUpAll`.
void holdCuratedArt() {
  CuratedArt.instance.load(_NeverBundle());
}

class _NeverBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Completer<ByteData>().future;
}
