import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/feed_parser.dart';
import 'package:medito/services/library/lib_source.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/dharma_seed_fake_api.dart';

/// `lib_tracks` as schema 3 wrote it: no licence columns.
const _schema3LibTracks = '''
CREATE TABLE lib_tracks (
  id TEXT NOT NULL PRIMARY KEY,
  course_id TEXT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT '',
  artwork_url TEXT NOT NULL DEFAULT '',
  audio_url TEXT NOT NULL,
  is_local_file INTEGER NOT NULL DEFAULT 0 CHECK (is_local_file IN (0, 1)),
  mime_type TEXT NOT NULL DEFAULT '',
  duration_ms INTEGER NOT NULL DEFAULT 0,
  guid TEXT NOT NULL DEFAULT '',
  published_at TEXT NOT NULL DEFAULT '',
  ordinal INTEGER NOT NULL DEFAULT 0,
  page_url TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
)''';

void main() {
  test(
    'schema 3 library gains the licence columns and keeps its episodes',
    () async {
      useSystemSqlite();
      final scratch = Directory.systemTemp.createTempSync('licence_migration');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final file = File('${scratch.path}/library.sqlite');

      final old = sqlite3.open(file.path);
      old.execute(_schema3LibTracks);
      old.execute(
        "INSERT INTO lib_tracks (id, title, author, audio_url, page_url, created_at) "
        "VALUES ('lib-track-old', 'Before the change', 'Example Sangha', "
        "'https://example.org/old.mp3', 'https://example.org/old', 1760000000)",
      );
      old.execute('PRAGMA user_version = 3');
      old.dispose();

      final db = LibraryDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final lib = LibSource(db: db, library: LibraryStore(db));

      final before = (await db.trackById('lib-track-old'))!;
      expect(before.title, 'Before the change');
      expect(before.author, 'Example Sangha');
      expect(before.licenseName, '', reason: 'no licence was ever recorded');
      expect(before.licenseUrl, '');
      expect(LibSource.trackAttribution(before, null).licenseName, '');

      // A lone episode added after the upgrade keeps the feed's licence.
      final id = await lib.storeEpisode(
        const ParsedEpisode(
          guid: 'ep-9',
          title: 'After the change',
          audioUrl: 'https://example.org/new.mp3',
          ordinal: 0,
        ),
        feedUrl: 'https://example.org/evening.rss',
        licenseName: 'CC BY-NC 4.0',
        licenseUrl: 'https://creativecommons.org/licenses/by-nc/4.0/',
      );
      final attribution = LibSource.trackAttribution(
        (await db.trackById(id))!,
        null,
      );
      expect(attribution.licenseName, 'CC BY-NC 4.0');
      expect(
        attribution.licenseUrl,
        'https://creativecommons.org/licenses/by-nc/4.0/',
      );
      expect(
        (await db.trackById('lib-track-old'))!.title,
        'Before the change',
        reason: 'the upgrade left the old row alone',
      );
    },
  );

  test(
    'storing an episode again without a licence keeps the one it has',
    () async {
      final db = LibraryDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final lib = LibSource(db: db, library: LibraryStore(db));
      final id = await lib.storeEpisode(
        const ParsedEpisode(
          guid: 'ep-1',
          title: 'One',
          audioUrl: 'https://example.org/1.mp3',
          ordinal: 0,
        ),
        feedUrl: 'https://example.org/evening.rss',
        licenseName: 'CC BY 4.0',
      );
      // The same episode again as part of a course, which names none for the
      // row (the course carries it): what the row holds stays.
      await lib.storeEpisode(
        const ParsedEpisode(
          guid: 'ep-1',
          title: 'One',
          audioUrl: 'https://example.org/1.mp3',
          ordinal: 0,
        ),
        feedUrl: 'https://example.org/evening.rss',
      );
      expect((await db.trackById(id))!.licenseName, 'CC BY 4.0');
    },
  );
}
