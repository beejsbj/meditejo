import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/utils/logger.dart';
import 'package:medito/utils/signed_url_redaction.dart';

const _signed =
    'https://rr1---sn-abc.googlevideo.com/videoplayback?expire=1&sig=SECRET&ip=1.2.3.4';

void main() {
  group('redactSignedUrls', () {
    test('a stream address keeps only its host', () {
      expect(
        redactSignedUrls('Will use path: $_signed'),
        'Will use path: https://rr1---sn-abc.googlevideo.com/<redacted>',
      );
    });

    test('every address in a long message goes, wherever it sits', () {
      final out = redactSignedUrls(
        'HttpException: Connection closed, uri = $_signed\n'
        '(retry: "$_signed")',
      );
      expect(out, isNot(contains('SECRET')));
      expect(out, isNot(contains('sig=')));
      expect('<redacted>'.allMatches(out), hasLength(2));
    });

    test('a videoplayback path is signed on any host', () {
      expect(
        redactSignedUrls('https://www.youtube.com/videoplayback?sig=SECRET'),
        'https://www.youtube.com/<redacted>',
      );
    });

    test('ordinary addresses and plain text are untouched', () {
      const text =
          'Opened https://www.youtube.com/watch?v=aaaaaaaaaaa, '
          'https://example.org/a.mp3?token=1 and no network';
      expect(redactSignedUrls(text), text);
    });
  });

  group('logging', () {
    late DebugPrintCallback original;
    late List<String> lines;

    setUp(() {
      original = debugPrint;
      lines = [];
      debugPrint = (String? message, {int? wrapWidth}) =>
          lines.add(message ?? '');
    });
    tearDown(() => debugPrint = original);

    test('AppLogger redacts messages and error details', () {
      AppLogger.d('PLAYER', 'Will use path: $_signed');
      AppLogger.i('PLAYER', 'i $_signed');
      AppLogger.w('PLAYER', 'w $_signed');
      AppLogger.e('PLAYER', 'e $_signed', Exception('failed: $_signed'));

      expect(lines, isNotEmpty);
      for (final line in lines) {
        expect(line, isNot(contains('SECRET')));
        expect(line, isNot(contains('sig=')));
      }
      expect(lines.join('\n'), contains('googlevideo.com/<redacted>'));
    });

    test('redactDebugPrint also covers the framework\'s own output', () {
      redactDebugPrint();
      debugPrint('FlutterError: uri = $_signed');
      expect(lines.single, isNot(contains('SECRET')));
      expect(lines.single, contains('<redacted>'));
    });
  });
}
