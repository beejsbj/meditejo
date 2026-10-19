import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/feed_parser.dart';

String fixture(String name) =>
    File('test/fixtures/library/$name').readAsStringSync();

void main() {
  group('RSS 2.0 with iTunes tags', () {
    final feed = parseFeed(
      fixture('rss_podcast.xml'),
      base: Uri.parse('https://example.org/evening.rss'),
    );

    test('reads the show', () {
      expect(feed.title, 'Evening Sits');
      expect(feed.author, 'Example Sangha');
      expect(feed.siteUrl, 'https://example.org/evening');
      expect(feed.copyright, '© 2025 Example Sangha');
      expect(
        feed.description,
        'Guided sits for the end of the day.\n\nGentle & unhurried.',
      );
      // A relative itunes:image resolves against the feed address.
      expect(feed.imageUrl, 'https://example.org/art/evening.jpg');
      expect(feed.isSerial, isFalse);
    });

    test('reads a Creative Commons licence', () {
      expect(
        feed.licenseUrl,
        'https://creativecommons.org/licenses/by-nc/4.0/',
      );
      expect(feed.licenseName, 'CC BY-NC 4.0');
    });

    test('keeps only audio episodes, oldest first', () {
      expect(feed.episodes.map((e) => e.guid), ['ep-1', 'ep-2', 'ep-3']);
      expect(feed.episodes.map((e) => e.ordinal), [0, 1, 2]);
      // The text post and the video were left out and counted.
      expect(feed.skippedItems, 2);
    });

    test('parses durations in every form, and leaves missing ones null', () {
      final byTitle = {for (final e in feed.episodes) e.title: e};
      expect(
        byTitle['Third sit: open awareness']!.durationMs,
        (3600 + 120 + 3) * 1000,
      );
      expect(byTitle['Second sit: the breath']!.durationMs, 1830 * 1000);
      expect(byTitle['First sit: arriving']!.durationMs, isNull);
      expect(feed.durationComplete, isFalse);
      expect(feed.totalDurationMs, (3723 + 1830) * 1000);
    });

    test('reads enclosures, dates, descriptions and artwork', () {
      final third = feed.episodes.last;
      expect(third.audioUrl, 'https://cdn.example.org/ep3.mp3');
      expect(third.mimeType, 'audio/mpeg');
      expect(third.lengthBytes, 9000000);
      expect(third.publishedAt, DateTime.utc(2025, 6, 10, 4));
      // content:encoded wins, stripped of markup.
      expect(third.description, 'Rest in open awareness.');
      expect(third.imageUrl, 'https://example.org/art/ep3.jpg');
      expect(third.pageUrl, 'https://example.org/evening/3');
      expect(third.author, 'Example Sangha');
    });

    test('resolves relative enclosures and zone offsets', () {
      final first = feed.episodes.first;
      expect(first.audioUrl, 'https://example.org/audio/ep1.mp3');
      // 04:00 at -0500 is 09:00 UTC.
      expect(first.publishedAt, DateTime.utc(2025, 5, 27, 9));
      // GMT zone name.
      expect(feed.episodes[1].publishedAt, DateTime.utc(2025, 6, 3, 4));
    });
  });

  group('ordering', () {
    test('a serial feed follows its episode numbers, not its dates', () {
      final feed = parseFeed(fixture('rss_serial.xml'));
      expect(feed.isSerial, isTrue);
      expect(feed.episodes.map((e) => e.title), [
        'Session 1',
        'Session 2',
        'Session 3',
      ]);
      expect(feed.imageUrl, 'https://example.org/foundations.png');
    });

    test(
      'with no dates, the feed is read backwards (feeds list newest first)',
      () {
        final feed = parseFeed(fixture('rss_undated.xml'));
        expect(feed.episodes.map((e) => e.title), [
          'Oldest',
          'Middle',
          'Newest',
        ]);
        expect(feed.episodes.every((e) => e.publishedAt == null), isTrue);
        expect(feed.episodes.every((e) => e.durationMs == null), isTrue);
      },
    );
  });

  group('Atom', () {
    final feed = parseFeed(
      fixture('atom_feed.xml'),
      base: Uri.parse('https://example.net/feed.atom'),
    );

    test('reads the feed', () {
      expect(feed.title, 'Dhamma Notes');
      expect(feed.description, 'Short talks & readings');
      expect(feed.author, 'Ayya Example');
      expect(feed.siteUrl, 'https://example.net/');
      expect(feed.imageUrl, 'https://example.net/logo.png');
      expect(feed.copyright, 'Free to share');
      expect(feed.licenseName, 'CC BY-NC-ND 3.0');
    });

    test('reads entries with enclosure links, oldest first', () {
      expect(feed.episodes.map((e) => e.title), ['Note one', 'Note two']);
      expect(feed.skippedItems, 1);
      final one = feed.episodes.first;
      expect(one.audioUrl, 'https://example.net/audio/1.ogg');
      expect(one.mimeType, 'audio/ogg');
      expect(one.description, 'The first note.');
      expect(one.author, 'Guest Voice');
      // +01:00 is read as an instant.
      expect(one.publishedAt, DateTime.utc(2025, 3, 1, 7));
      final two = feed.episodes.last;
      expect(two.lengthBytes, 1234);
      expect(two.pageUrl, 'https://example.net/2');
      expect(two.guid, 'tag:example.net,2025:2');
    });
  });

  group('failures', () {
    test('HTML is not a feed', () {
      expect(
        () => parseFeed(fixture('page_plain.html')),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('broken XML is not a feed', () {
      expect(
        () => parseFeed('<rss><channel>'),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('an RSS file with no channel is rejected', () {
      expect(
        () => parseFeed('<rss version="2.0"></rss>'),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('media:content with medium="audio" counts without a type', () {
      final feed = parseFeed(
        '<rss xmlns:media="http://search.yahoo.com/mrss/"><channel><title>T</title>'
        '<item><title>x</title><media:content url="https://cdn.example.org/a1" medium="audio"/></item>'
        '<item><title>y</title><media:content url="https://cdn.example.org/v1" medium="video"/></item>'
        '</channel></rss>',
      );
      expect(feed.episodes.map((e) => e.audioUrl), ['https://cdn.example.org/a1']);
      expect(feed.skippedItems, 1);
    });

    test('a feed with no audio parses to no episodes', () {
      final feed = parseFeed(
        '<rss><channel><title>T</title><item><title>x</title></item></channel></rss>',
      );
      expect(feed.episodes, isEmpty);
      expect(feed.skippedItems, 1);
      expect(feed.durationComplete, isFalse);
    });
  });

  group('helpers', () {
    test('looksLikeFeed sniffs the start of a body', () {
      expect(looksLikeFeed(fixture('rss_podcast.xml')), isTrue);
      expect(looksLikeFeed(fixture('atom_feed.xml')), isTrue);
      expect(looksLikeFeed(fixture('page_with_feed.html')), isFalse);
    });

    test('parseDurationMs', () {
      expect(parseDurationMs('90'), 90000);
      expect(parseDurationMs('05:30'), 330000);
      expect(parseDurationMs('1:00:00'), 3600000);
      expect(parseDurationMs('12.5'), 12500);
      expect(parseDurationMs(''), isNull);
      expect(parseDurationMs('soon'), isNull);
      expect(parseDurationMs('0'), isNull);
      expect(parseDurationMs('1:2:3:4'), isNull);
    });

    test('parseFeedDate takes RFC 822 and ISO 8601', () {
      expect(
        parseFeedDate('Wed, 02 Oct 2002 13:00:00 GMT'),
        DateTime.utc(2002, 10, 2, 13),
      );
      expect(
        parseFeedDate('02 Oct 02 13:00 EST'),
        DateTime.utc(2002, 10, 2, 18),
      );
      expect(
        parseFeedDate('2025-03-02T08:00:00Z'),
        DateTime.utc(2025, 3, 2, 8),
      );
      expect(parseFeedDate('not a date'), isNull);
      expect(parseFeedDate(null), isNull);
    });

    test('licenseNameFromUrl', () {
      expect(
        licenseNameFromUrl('https://creativecommons.org/licenses/by/4.0/'),
        'CC BY 4.0',
      );
      expect(
        licenseNameFromUrl(
          'https://creativecommons.org/publicdomain/zero/1.0/',
        ),
        'CC0',
      );
      expect(licenseNameFromUrl('https://example.org/terms'), '');
    });

    test('plainText strips markup and entities', () {
      expect(
        plainText('<p>One &amp; two</p><p>Three<br/>four</p>'),
        'One & two\n\nThree\nfour',
      );
      expect(plainText('already plain'), 'already plain');
    });
  });
}
