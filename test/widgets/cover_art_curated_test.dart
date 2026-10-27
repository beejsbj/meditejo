import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/widgets/art/art_cover.dart';
import 'package:medito/widgets/art/art_subject.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

import '../helpers/art_finders.dart';

// Its own file: once the curated art is in, every ArtCover draws, and these
// tests should not depend on the painters of the other ids.

const _thumb = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
const _starter = 'yt-playlist-PLND1JCRq8VujAHvDA482SXF1cJTQrwlx3';

Map<String, Object?> _shipped() =>
    (jsonDecode(File('assets/art/curated_art.json').readAsStringSync()) as Map)
        .cast<String, Object?>();

void main() {
  setUpAll(holdCuratedArt);

  test('a shipped course resolves to its curated composition', () {
    CuratedArt.instance.useJson(
      File('assets/art/curated_art.json').readAsStringSync(),
    );
    final comp = CuratedArt.instance.resolve(courseArt(_starter));
    expect(comp, isNotNull);
    expect(comp!.seed, CuratedArt.instance.entry(_starter)!['seed']);
    // An id that doesn't ship is built from its id, not curated.
    expect(CuratedArt.instance.entry('lib-course-new'), isNull);
  });

  test('curated art for a shipped id wins over its thumbnail', () {
    CuratedArt.instance.useJson(
      File('assets/art/curated_art.json').readAsStringSync(),
    );
    expect(shownCoverUrl(courseArt(_starter), _thumb), isEmpty);
    expect(shownCoverUrl(singleArt('ds-talk-60864'), _thumb), isEmpty);
    // Anything else keeps its real cover.
    expect(shownCoverUrl(courseArt('yt-playlist-other'), _thumb), _thumb);
    // And a teacher is never curated away from their photo.
    expect(shownCoverUrl(teacherArt(_starter), _thumb), _thumb);
  });

  testWidgets('a starter course shows its curated card, not its thumbnail', (
    tester,
  ) async {
    // The shipped starter course, with a ground and no figure so this does
    // not depend on the painters still being ported.
    final file = _shipped();
    final items = (file['items'] as Map).cast<String, Object?>();
    final entry = (items[_starter] as Map).cast<String, Object?>();
    items[_starter] = {
      ...entry,
      'ground': (items['ds-retreat-1183'] as Map)['ground'],
      'figure': null,
      'accent': null,
    };
    CuratedArt.instance.useJson(jsonEncode(file));

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 160,
          height: 90,
          child: NetworkImageWidget(url: _thumb, art: courseArt(_starter)),
        ),
      ),
    );
    expect(findArt(courseArt(_starter)), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(ArtCover), findsOneWidget);
  });
}
