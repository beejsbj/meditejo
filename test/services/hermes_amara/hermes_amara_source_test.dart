import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/catalogue/catalogue_models.dart';
import 'package:medito/models/explore/session_length.dart';
import 'package:medito/services/hermes_amara/hermes_amara_flag.dart';
import 'package:medito/services/hermes_amara/hermes_amara_source.dart';
import 'package:medito/services/library/library_models.dart';
import 'package:medito/services/library/library_store.dart';
import 'package:medito/services/local_catalogue.dart';

import '../../helpers/library_fixtures.dart';

String fixture() => File(
  'test/fixtures/hermes_amara/resources_audio_sample.html',
).readAsStringSync();

void main() {
  late DateTime now;
  late int fetches;
  late Object? failure;
  late String body;
  late MemoryHaListingCache cache;

  HermesAmaraSource source({bool enabled = true, HaListingCache? withCache}) =>
      HermesAmaraSource(
        fetchListing: () async {
          fetches++;
          if (failure != null) throw failure!;
          return body;
        },
        cache: withCache ?? cache,
        clock: () => now,
        enabled: enabled,
      );

  setUp(() {
    now = DateTime.utc(2026, 10, 27, 9);
    fetches = 0;
    failure = null;
    body = fixture();
    cache = MemoryHaListingCache();
  });

  group('dormant by default', () {
    test('the compile-time flag is off', () {
      expect(hermesAmaraEnabled, isFalse);
    }, skip: hermesAmaraEnabled);

    test('a disabled source fetches nothing and answers empty', () async {
      final s = source(enabled: false);
      await s.catchUp(force: true);
      expect(fetches, 0);
      expect(await s.browsePacks(), isEmpty);
      expect((await s.explore()).hasCatalogue, isFalse);
      expect(s.canSave('ha-talk-x'), isFalse);
    });

    test('without the flag, a source built plainly is disabled', () async {
      final s = HermesAmaraSource(fetchListing: () async => body);
      await s.catchUp();
      expect(await s.browsePacks(), isEmpty);
    }, skip: hermesAmaraEnabled);
  });

  group('before the first catchUp', () {
    test('nothing is fetched and every read is empty', () async {
      final s = source();
      expect(await s.browsePacks(), isEmpty);
      expect(await s.searchPacks('mindfulness'), isEmpty);
      expect(await s.searchTracks('mindfulness'), isEmpty);
      expect(await s.packTrackIds(), isEmpty);
      expect((await s.explore()).isEmpty, isTrue);
      expect((await s.explore()).hasCatalogue, isFalse);
      expect((await s.search('mindfulness')).isEmpty, isTrue);
      expect(await s.libraryDraft('ha-talk-x'), isNull);
      await expectLater(
        s.track('ha-talk-x'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        s.pack('ha-retreat-x'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect(fetches, 0);
    });

    test('identity', () {
      final s = source();
      expect(s.name, 'Hermes Amāra');
      expect(s.prefix, 'ha-');
      expect(s.ownsTeacher('ds-teacher-210'), isFalse);
    });
  });

  group('catchUp', () {
    test('fetches once, then respects the 12 hour rule', () async {
      final s = source();
      await s.catchUp();
      expect(fetches, 1);
      expect(s.revision.value, 1);

      now = now.add(const Duration(hours: 11, minutes: 59));
      await s.catchUp();
      expect(fetches, 1);

      now = now.add(const Duration(minutes: 2));
      await s.catchUp();
      expect(fetches, 2);
      // Same listing: nothing for a screen to re-read.
      expect(s.revision.value, 1);
    });

    test('force ignores the rule', () async {
      final s = source();
      await s.catchUp();
      await s.catchUp(force: true);
      expect(fetches, 2);
    });

    test('calls made together share one fetch', () async {
      final s = source();
      await Future.wait([s.catchUp(), s.catchUp(), s.catchUp()]);
      expect(fetches, 1);
    });

    test('revision bumps when the listing changes', () async {
      final s = source();
      await s.catchUp();
      body = body.replaceFirst('Heart Work', 'Heart Work Revised');
      await s.catchUp(force: true);
      expect(s.revision.value, 2);
      expect((await s.searchTracks('revised')), hasLength(1));
    });

    test('a failure keeps the cached listing and retries next time', () async {
      final s = source();
      await s.catchUp();
      failure = Exception('offline');
      now = now.add(const Duration(hours: 13));
      await s.catchUp();
      expect(fetches, 2);
      expect(await s.browsePacks(), hasLength(6));
      expect(s.revision.value, 1);

      // Not remembered as a success: the next open tries again.
      await s.catchUp();
      expect(fetches, 3);
    });

    test('a page with no talks does not replace the listing', () async {
      final s = source();
      await s.catchUp();
      body = '<html>maintenance</html>';
      await s.catchUp(force: true);
      expect(await s.browsePacks(), hasLength(6));
      expect(cache.state!.raw, contains('Heart Work'));
    });

    test('a first launch that fails answers empty', () async {
      failure = Exception('offline');
      final s = source();
      await s.catchUp();
      expect(fetches, 1);
      expect(await s.browsePacks(), isEmpty);
      expect((await s.explore()).hasCatalogue, isFalse);
    });

    test('a later launch reads from the cache without fetching', () async {
      await source().catchUp();
      final later = source();
      expect(await later.browsePacks(), hasLength(6));
      expect(fetches, 1);

      // Within 12 hours of the cached fetch, catchUp stays quiet too.
      await later.catchUp();
      expect(fetches, 1);
    });
  });

  group('reads', () {
    late HermesAmaraSource s;
    setUp(() async {
      s = source();
      await s.catchUp();
    });

    test('a retreat is a course with its talks in order', () async {
      final pack = await s.pack('ha-retreat-november-solitary-2005');
      expect(pack.title, 'November Solitary 2005');
      expect(
        [for (final i in pack.items) i.title],
        [
          'Mindfulness of Mind States',
          'Contemplating the Three Characteristics (Part 1) - Impermanence And Dukkha',
          'Contemplating the Three Characteristics (Part 2) - Anattā (Not Self)',
          'Compassion and Emptiness',
        ],
      );
      expect(
        pack.items.first.id,
        'ha-talk-2005-11-05-mindfulness-of-mind-states',
      );
      expect(
        pack.items.first.path,
        '/tracks/ha-talk-2005-11-05-mindfulness-of-mind-states',
      );
      expect(pack.subtitle, 'Rob Burbea · 4 talks');
      expect(pack.attribution!.licenseUrl, isEmpty);
      expect(pack.teacher, isNull);
    });

    test('browse lists the retreats, newest first', () async {
      final packs = await s.browsePacks();
      expect(packs.first.id, 'ha-retreat-the-lovingkindness-metta-retreat');
      expect(
        packs.map((p) => p.id),
        contains('ha-retreat-november-solitary-2005'),
      );
    });

    test('track is one voice with one file at the audio URL', () async {
      final track = await s.track(
        'ha-talk-2005-11-22-compassion-and-emptiness',
      );
      expect(track.voices, hasLength(1));
      final file = track.voices.single.audioFiles.single;
      expect(
        file.path,
        'https://storage.googleapis.com/hermes-amara/stems/'
        '2005-11-22-compassion-and-emptiness.mp3',
      );
      expect(file.duration, (55 * 60 + 26) * 1000);
      expect(track.hasBackgroundSound, isFalse);
      expect(track.artist!.name, 'Rob Burbea');
      expect(
        track.artist!.path,
        'https://hermesamara.org/resources/talk/2005-11-22-compassion-and-emptiness',
      );
    });

    test('attribution credits the site and states no licence URL', () async {
      final track = await s.track(
        'ha-talk-2005-11-22-compassion-and-emptiness',
      );
      final a = track.attribution!;
      expect(a.source, 'Hermes Amāra Foundation');
      expect(a.creator, 'Rob Burbea');
      expect(a.licenseName, 'Copyright Hermes Amāra Foundation');
      expect(a.licenseUrl, '');
      expect(
        a.url,
        'https://hermesamara.org/resources/talk/2005-11-22-compassion-and-emptiness',
      );
    });

    test('a practice talk gets background sound', () async {
      final track = await s.track('ha-talk-2005-12-17-the-art-of-letting-go');
      expect(track.hasBackgroundSound, isTrue);
    });

    test('unknown ids are unavailable', () async {
      await expectLater(
        s.track('ha-talk-nope'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        s.pack('ha-retreat-nope'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      await expectLater(
        s.pack('ha-talk-2005-11-22-compassion-and-emptiness'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
    });

    test('there is no teacher entity', () async {
      await expectLater(
        s.teacherPage('ds-teacher-210'),
        throwsA(isA<CatalogueEntryUnavailable>()),
      );
      expect(await s.teacherTalks('ds-teacher-210', offset: 0), isEmpty);
      expect((await s.explore()).teachers, isEmpty);
    });

    test('explore splits by group', () async {
      final practice = await s.explore(group: ContentGroup.practice);
      final talks = await s.explore(group: ContentGroup.talks);
      final both = await s.explore();
      expect(practice.hasCatalogue, isTrue);
      expect(both.talks, hasLength(9));
      expect(practice.talks.map((t) => t.kind).toSet(), {'Practice'});
      expect(talks.talks.map((t) => t.kind).toSet(), {'Talk'});
      expect(practice.talks.length + talks.talks.length, 9);
      expect(
        practice.courses.map((c) => c.id),
        contains('ha-retreat-the-art-of-letting-go-insight-meditation'),
      );
      expect(
        talks.courses.map((c) => c.id),
        contains('ha-retreat-november-solitary-2005'),
      );
    });

    test('search folds diacritics and matches word prefixes', () async {
      final byAscii = await s.searchTracks('samadhi');
      expect(
        [for (final t in byAscii) t.id],
        ['ha-talk-2008-01-29-the-place-of-samadhi-in-metta-practice'],
      );
      expect(await s.searchTracks('Mettā'), hasLength(3));
      expect(await s.searchTracks('metta pla'), hasLength(1));
      expect(await s.searchTracks('anatta'), hasLength(1));
      // By event and by tag.
      expect(await s.searchTracks('finland'), hasLength(1));
      expect(await s.searchTracks('citta'), hasLength(1));
      expect(await s.searchTracks('zzz'), isEmpty);
      expect(await s.searchTracks('  '), isEmpty);
      // A prefix must start a word.
      expect(await s.searchTracks('indfulness'), isEmpty);
    });

    test(
      'grouped search returns courses and talks, and filters by length',
      () async {
        final results = await s.search('lovingkindness');
        expect(results.teachers, isEmpty);
        expect(
          results.courses.map((c) => c.id),
          contains('ha-retreat-the-lovingkindness-metta-retreat'),
        );
        expect(results.talks, hasLength(3));

        final long = await s.search(
          'lovingkindness',
          length: SessionLength.over45,
        );
        expect(long.talks, hasLength(3));
        final short = await s.search(
          'lovingkindness',
          length: SessionLength.under10,
        );
        expect(short.talks, isEmpty);
        expect(await s.searchPacks('solitary'), hasLength(1));

        // A talk with no length is dropped by a length filter.
        final noLength = await s.search(
          'finland',
          length: SessionLength.over45,
        );
        expect(noLength.talks, isEmpty);
        expect((await s.search('finland')).talks, hasLength(1));
      },
    );

    test('pack track ids list saved and started retreats only', () async {
      final started = await s.packTrackIds(
        startedTrackIds: {'ha-talk-2005-11-22-compassion-and-emptiness'},
      );
      expect(started.keys, ['ha-retreat-november-solitary-2005']);
      expect(started.values.single, hasLength(4));
      expect(await s.packTrackIds(), isEmpty);
    });
  });

  group('saving', () {
    test('drafts describe a retreat and a talk', () async {
      final s = source();
      await s.catchUp();
      expect(s.canSave('ha-talk-x'), isTrue);
      expect(s.canSave('ha-retreat-x'), isTrue);
      expect(s.canSave('ds-retreat-1'), isFalse);

      final course = (await s.libraryDraft(
        'ha-retreat-november-solitary-2005',
      ))!;
      expect(course.kind, LibraryKind.course);
      expect(course.group, LibraryGroup.talks);
      expect(course.itemCount, 4);
      expect(
        course.durationMs,
        ((47 * 60 + 39) + (53 * 60 + 39) + (56 * 60 + 21) + (55 * 60 + 26)) *
            1000,
      );

      final single = (await s.libraryDraft(
        'ha-talk-2005-12-17-the-art-of-letting-go',
      ))!;
      expect(single.kind, LibraryKind.single);
      expect(single.group, LibraryGroup.practice);
      expect(await s.libraryDraft('ha-talk-nope'), isNull);
    });

    test('save and unsave go through the library', () async {
      final db = memoryLibraryDb();
      addTearDown(db.close);
      final store = LibraryStore(db, clock: () => now);
      final s = HermesAmaraSource(
        fetchListing: () async => body,
        library: store,
        cache: cache,
        clock: () => now,
        enabled: true,
      );
      await s.catchUp();
      const id = 'ha-retreat-november-solitary-2005';
      expect(await s.isSaved(id), isFalse);
      await s.setSaved(id, saved: true);
      expect(await s.isSaved(id), isTrue);
      // A saved course leaves Explore and heads packTrackIds.
      expect((await s.explore()).courses.map((c) => c.id), isNot(contains(id)));
      expect((await s.packTrackIds()).keys, [id]);
      await s.setSaved(id, saved: false);
      expect(await s.isSaved(id), isFalse);
    });
  });
}
