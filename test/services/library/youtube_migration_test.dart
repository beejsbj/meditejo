import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/library_database.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/dharma_seed_fake_api.dart';

void main() {
  test(
    'schema 1 library gains YouTube tables without losing saves or positions',
    () async {
      useSystemSqlite();
      final scratch = Directory.systemTemp.createTempSync('youtube_migration');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final file = File('${scratch.path}/library.sqlite');
      var db = LibraryDatabase(NativeDatabase(file));
      var store = LibraryStore(db);
      await store.add(
        const LibraryDraft(
          sourceId: 'ds-talk-1',
          kind: LibraryKind.single,
          title: 'My saved practice',
          group: LibraryGroup.practice,
        ),
      );
      await store.savePosition('ds-talk-1', 60000, 600000);
      store.dispose();
      await db.close();

      // Recreate the previous schema exactly: only the additive tables and
      // columns of schemas 2 to 4 differ. The old library's data is left in place.
      final old = sqlite3.open(file.path);
      old.execute('DROP TABLE youtube_videos');
      old.execute('DROP TABLE youtube_playlists');
      old.execute('DROP TABLE my_courses');
      old.execute('DROP TABLE my_course_items');
      old.execute('DROP TABLE session_contexts');
      old.execute('ALTER TABLE lib_tracks DROP COLUMN license_name');
      old.execute('ALTER TABLE lib_tracks DROP COLUMN license_url');
      old.execute('PRAGMA user_version = 1');
      old.dispose();

      db = LibraryDatabase(NativeDatabase(file));
      store = LibraryStore(db);
      addTearDown(() async {
        store.dispose();
        await db.close();
      });
      expect((await store.entries()).single.title, 'My saved practice');
      expect((await store.resumePoint('ds-talk-1'))!.positionMs, 60000);
      expect(await db.youtubeCourses(), isEmpty);
      expect(await db.youtubeSessions(), isEmpty);
    },
  );
}
