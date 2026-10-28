import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/hermes_amara/hermes_amara_ids.dart';
import 'package:medito/services/hermes_amara/hermes_amara_listing.dart';

String fixture() => File(
  'test/fixtures/hermes_amara/resources_audio_sample.html',
).readAsStringSync();

String page(String dataJson) =>
    '<html><script id="__NEXT_DATA__" type="application/json">'
    '{"props":{"pageProps":{"data":$dataJson}}}</script></html>';

void main() {
  group('parseHermesListing', () {
    late HaListing listing;
    setUp(() => listing = parseHermesListing(fixture()));

    test('reads every talk and groups them into events', () {
      expect(listing.talks, hasLength(9));
      expect(listing.events, hasLength(6));
      // Newest first.
      expect(listing.talks.first.slug, '2010-08-08-heart-work');
      expect(listing.talks.last.slug, '2005-11-05-mindfulness-of-mind-states');
    });

    test('puts an event\'s talks in ordinal order', () {
      final solitary = listing.event('november-solitary-2005')!;
      expect(solitary.name, 'November Solitary 2005');
      expect([for (final t in solitary.talks) t.ordinal], [1, 2, 3, 4]);
      expect(solitary.talks.first.title, 'Mindfulness of Mind States');
    });

    test('a record with no duration has none', () {
      final drive = listing.talk('2006-10-01-mindfulness')!;
      expect(drive.durationMs, 0);
      // A Google Drive source link does not matter: the audio is the stem.
      expect(drive.audioUrl, haAudioUrl('2006-10-01-mindfulness'));
      expect(drive.event, 'Silent Autumn Retreat, Finland 2006');
    });

    test('converts mm:ss and h:mm:ss to milliseconds', () {
      expect(
        listing.talk('2005-11-05-mindfulness-of-mind-states')!.durationMs,
        (47 * 60 + 39) * 1000,
      );
      expect(
        listing
            .talk('2008-01-29-the-place-of-samadhi-in-metta-practice')!
            .durationMs,
        (3600 + 26 * 60 + 4) * 1000,
      );
      expect(parseHaDuration('66:46'), (66 * 60 + 46) * 1000);
      expect(parseHaDuration('1:15:48'), (3600 + 15 * 60 + 48) * 1000);
      expect(parseHaDuration(''), 0);
      expect(parseHaDuration('soon'), 0);
      expect(parseHaDuration('1:xx'), 0);
    });

    test('splits tags, keeping quoted commas together', () {
      final talk = listing.talk('2005-11-05-mindfulness-of-mind-states')!;
      expect(talk.tags, contains('emptiness/insight'));
      expect(
        talk.tags,
        contains('mindfulness, foundations of: third foundation (citta)'),
      );
      expect(talk.tags, contains('impermanence (anicca)'));
    });
  });

  group('parseHermesListing, defensively', () {
    test('skips records without a slug or a title, and repeats', () {
      final listing = parseHermesListing(
        page(
          '[{"title":"A","slug":"a","date":"2020-01-02"},'
          '{"title":"No slug"},{"slug":"no-title"},{"title":"A again","slug":"a"},'
          '"junk",null,{"title":"B","slug":"b"}]',
        ),
      );
      expect([for (final t in listing.talks) t.slug], ['a', 'b']);
      // A talk with no event is a single, in no event.
      expect(listing.events, isEmpty);
      expect(listing.talk('b')!.date, '');
      expect(listing.talk('b')!.ordinal, isNull);
    });

    test('anything that is not the page gives an empty listing', () {
      expect(parseHermesListing('').isEmpty, isTrue);
      expect(parseHermesListing('<html>nothing</html>').isEmpty, isTrue);
      expect(
        parseHermesListing(
          '<script id="__NEXT_DATA__">{not json</script>',
        ).isEmpty,
        isTrue,
      );
      expect(parseHermesListing(page('{"x":1}')).isEmpty, isTrue);
    });

    test('the record\'s own author is kept', () {
      final listing = parseHermesListing(
        page('[{"title":"A","slug":"a","author":"Someone Else"}]'),
      );
      expect(listing.talk('a')!.author, 'Someone Else');
    });
  });

  group('isHaPractice', () {
    test('matches whole words in title, event or tags', () {
      expect(isHaPractice(title: 'A Guided Metta'), isTrue);
      expect(isHaPractice(title: 'x', event: 'Insight Meditation'), isTrue);
      expect(isHaPractice(title: 'x', tags: ['Practice']), isTrue);
      expect(isHaPractice(title: 'Compassion and Emptiness'), isFalse);
      expect(isHaPractice(title: 'Meditations on Practicality'), isFalse);
    });

    test('classifies the fixture', () {
      final listing = parseHermesListing(fixture());
      expect(
        listing.talk('2005-12-17-the-art-of-letting-go')!.practice,
        isTrue,
      );
      expect(
        listing
            .talk('2008-01-29-the-place-of-samadhi-in-metta-practice')!
            .practice,
        isTrue,
      );
      expect(
        listing.talk('2005-11-22-compassion-and-emptiness')!.practice,
        isFalse,
      );
    });
  });

  group('ids', () {
    test('round-trip', () {
      expect(haTalkId('2005-11-05-x'), 'ha-talk-2005-11-05-x');
      expect(parseHaTalkId('ha-talk-2005-11-05-x'), '2005-11-05-x');
      expect(parseHaTalkId('ha-talk-'), isNull);
      expect(parseHaTalkId('ha-retreat-x'), isNull);
      expect(isHaTalkId('ha-talk-a'), isTrue);

      final slug = haEventSlug('Silent Autumn Retreat, Finland 2006');
      expect(slug, 'silent-autumn-retreat-finland-2006');
      expect(
        haRetreatId(slug),
        'ha-retreat-silent-autumn-retreat-finland-2006',
      );
      expect(parseHaRetreatId(haRetreatId(slug)), slug);
      expect(parseHaRetreatId('ha-retreat-'), isNull);
      expect(isHaRetreatId('ha-talk-a'), isFalse);
    });

    test('event slugs fold diacritics and punctuation', () {
      expect(
        haEventSlug('The Lovingkindness (Mettā) Retreat'),
        'the-lovingkindness-metta-retreat',
      );
    });

    test('audio and page addresses are the site\'s own', () {
      expect(
        haAudioUrl('2005-11-05-x'),
        'https://storage.googleapis.com/hermes-amara/stems/2005-11-05-x.mp3',
      );
      expect(
        haTalkPageUrl('2005-11-05-x'),
        'https://hermesamara.org/resources/talk/2005-11-05-x',
      );
    });

    test('the attribution states no licence and invents none', () {
      final a = haAttribution(url: haTalkPageUrl('x'));
      expect(a.source, 'Hermes Amāra Foundation');
      expect(a.creator, 'Rob Burbea');
      expect(a.licenseName, 'Copyright Hermes Amāra Foundation');
      expect(a.licenseUrl, isEmpty);
      expect(haAttribution(url: 'u', creator: 'Ann').creator, 'Ann');
    });
  });
}
