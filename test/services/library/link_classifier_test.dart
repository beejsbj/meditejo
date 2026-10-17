import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/link_classifier.dart';

void main() {
  ImportLinkKind kind(String s) => classifyLink(s).kind;

  group('Dharma Seed links', () {
    test('retreat, teacher and talk pages', () {
      final retreat = classifyLink('https://dharmaseed.org/retreats/6689/');
      expect(retreat.kind, ImportLinkKind.dharmaSeedRetreat);
      expect(dharmaSeedIdFor(retreat), 'ds-retreat-6689');

      final teacher = classifyLink('https://www.dharmaseed.org/teacher/210/');
      expect(teacher.kind, ImportLinkKind.dharmaSeedTeacher);
      expect(dharmaSeedIdFor(teacher), 'ds-teacher-210');

      final talk = classifyLink('http://dharmaseed.org/talks/99944/?foo=bar');
      expect(talk.kind, ImportLinkKind.dharmaSeedTalk);
      expect(dharmaSeedIdFor(talk), 'ds-talk-99944');
    });

    test('works without a scheme or trailing slash, and on mobile hosts', () {
      expect(kind('dharmaseed.org/talks/12'), ImportLinkKind.dharmaSeedTalk);
      expect(kind('https://m.dharmaseed.org/retreats/9'), ImportLinkKind.dharmaSeedRetreat);
    });

    test('a teacher page with extra path or a non-numeric ID is just a web address', () {
      expect(kind('https://dharmaseed.org/teacher/abc/'), ImportLinkKind.webAddress);
      expect(kind('https://dharmaseed.org/'), ImportLinkKind.webAddress);
    });

    test('a Dharma Seed audio file is an audio file', () {
      expect(kind('https://dharmaseed.org/talks/99944/audio.mp3'), ImportLinkKind.dharmaSeedTalk);
      expect(kind('https://dharmaseed.org/media/x/y.mp3'), ImportLinkKind.audioFile);
    });
  });

  group('other links', () {
    test('audio by extension, ignoring query and case', () {
      expect(kind('https://example.org/a/sit.MP3?dl=1'), ImportLinkKind.audioFile);
      expect(kind('https://example.org/a/sit.m4a'), ImportLinkKind.audioFile);
      expect(kind('https://example.org/a/sit.opus'), ImportLinkKind.audioFile);
    });

    test('anything else on the web needs one request to tell', () {
      expect(kind('https://example.org/feed.xml'), ImportLinkKind.webAddress);
      expect(kind('https://example.org/podcast'), ImportLinkKind.webAddress);
      expect(kind('https://example.org/dir.mp3/'), ImportLinkKind.webAddress);
    });

    test('YouTube in all its forms', () {
      expect(kind('https://www.youtube.com/watch?v=abc'), ImportLinkKind.youtube);
      expect(kind('https://youtu.be/abc'), ImportLinkKind.youtube);
      expect(kind('https://m.youtube.com/playlist?list=PL1'), ImportLinkKind.youtube);
      expect(kind('https://music.youtube.com/watch?v=abc'), ImportLinkKind.youtube);
    });

    test('Apple Podcasts carries the show ID; other directories cannot be read', () {
      final apple = classifyLink('https://podcasts.apple.com/us/podcast/evening-sits/id1234567?i=1000');
      expect(apple.kind, ImportLinkKind.applePodcast);
      expect(apple.id, 1234567);
      expect(kind('https://podcasts.apple.com/us/browse'), ImportLinkKind.unsupportedHost);
      expect(kind('https://open.spotify.com/show/abc'), ImportLinkKind.unsupportedHost);
    });

    test('local paths and file URIs', () {
      expect(kind('/storage/emulated/0/Download/sit.mp3'), ImportLinkKind.localFile);
      expect(kind('file:///storage/emulated/0/sit.mp3'), ImportLinkKind.localFile);
      expect(kind('content://media/external/audio/1'), ImportLinkKind.localFile);
    });

    test('rubbish is unrecognised', () {
      expect(kind(''), ImportLinkKind.unrecognised);
      expect(kind('hello there'), ImportLinkKind.unrecognised);
      expect(kind('ftp://example.org/a.mp3'), ImportLinkKind.unrecognised);
      expect(kind('mailto:me@example.org'), ImportLinkKind.unrecognised);
    });
  });

  group('shared text', () {
    test('firstLinkIn finds a link in a sentence and trims punctuation', () {
      expect(
        firstLinkIn('Check this out: https://example.org/feed.xml, it is great.'),
        'https://example.org/feed.xml',
      );
      expect(firstLinkIn('(see https://example.org/a)'), 'https://example.org/a');
      expect(
        firstLinkIn('https://en.wikipedia.org/wiki/Zen_(disambiguation)'),
        'https://en.wikipedia.org/wiki/Zen_(disambiguation)',
      );
      expect(firstLinkIn('no link at all'), isNull);
    });

    test('looksImportable', () {
      expect(looksImportable('  https://example.org/feed.xml \n'), isTrue);
      expect(looksImportable('Listen: https://dharmaseed.org/talks/1/'), isTrue);
      expect(looksImportable('just words'), isFalse);
      expect(looksImportable('ftp://example.org/a.mp3'), isFalse);
    });
  });

  group('titles and hosts', () {
    test('titleFromFileName tidies a file name or URL', () {
      expect(titleFromFileName('https://example.org/files/2024-05_body-scan_20min.mp3'), '2024 05 body scan 20min');
      expect(titleFromFileName('/storage/emulated/0/Download/Metta%20Practice.m4a'), 'Metta Practice');
      expect(titleFromFileName('Loving kindness.MP3'), 'Loving kindness');
      expect(titleFromFileName('https://example.org/'), 'example.org');
      expect(titleFromFileName(''), 'Untitled');
    });

    test('known talk hosts', () {
      expect(isKnownTalkHost('www.dhammatalks.org'), isTrue);
      expect(isKnownTalkHost('dharmaseed.org'), isTrue);
      expect(isKnownTalkHost('example.org'), isFalse);
      expect(isKnownTalkHost('notdhammatalks.org'), isFalse);
    });
  });
}
