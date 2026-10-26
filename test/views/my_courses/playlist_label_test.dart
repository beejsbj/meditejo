import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/l10n/app_localizations_de.dart';
import 'package:medito/l10n/app_localizations_en.dart';
import 'package:medito/l10n/app_localizations_es.dart';
import 'package:medito/models/pack/pack_model.dart';
import 'package:medito/views/dharma_seed/widgets/course_rows_sliver.dart';
import 'package:medito/views/my_courses/playlist_label.dart';

import '../../helpers/library_app.dart';

const _playlist = 'my-course-0123456789abcdef';

void main() {
  group('playlistAwareDetail', () {
    final en = AppLocalizationsEn();

    test('a course keeps its own line, whatever it is', () {
      expect(
        playlistAwareDetail(en, 'ds-retreat-1', 'Tara Brach'),
        'Tara Brach',
      );
      expect(playlistAwareDetail(en, 'ds-retreat-1', null), isNull);
    });

    test('a playlist leads with what it is', () {
      expect(
        playlistAwareDetail(en, _playlist, '3 sessions'),
        'Playlist · 3 sessions',
      );
      expect(playlistAwareDetail(en, _playlist, ''), 'Playlist');
      expect(playlistAwareDetail(en, _playlist, null), 'Playlist');
    });

    test('the word follows the language', () {
      expect(
        playlistAwareDetail(AppLocalizationsDe(), _playlist, null),
        'Playlist',
      );
      expect(
        playlistAwareDetail(AppLocalizationsEs(), _playlist, null),
        'Lista',
      );
    });
  });

  testWidgets('search rows say which result is a playlist', (tester) async {
    final app = await LibraryTestApp.create(tester);
    await app.pump(
      tester,
      Scaffold(
        body: CustomScrollView(
          slivers: [
            CourseRowsSliver(
              courses: [
                PackItemsModel(
                  type: 'pack',
                  id: 'ds-retreat-1',
                  title: 'Jhāna Retreat',
                  subtitle: 'Rob Burbea',
                  path: '/packs/ds-retreat-1',
                ),
                PackItemsModel(
                  type: 'pack',
                  id: _playlist,
                  title: 'Morning sits',
                  subtitle: 'Short and quiet',
                  path: '/packs/$_playlist',
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('Rob Burbea'), findsOneWidget);
    expect(find.text('Playlist · Short and quiet'), findsOneWidget);
    expect(find.textContaining('Playlist'), findsOneWidget);
  });
}
