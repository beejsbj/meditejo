import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/library/share_intake.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPayload', () {
    test('a shared link', () {
      final payload = SharedPayload.fromMap({'text': '  Listen https://example.org/feed.xml \n'});
      expect(payload.text, 'Listen https://example.org/feed.xml');
      expect(payload.files, isEmpty);
      expect(payload.isEmpty, isFalse);
    });

    test('shared audio files, with what the share knew about them', () {
      final payload = SharedPayload.fromMap({
        'files': [
          {'path': '/cache/shared_audio/1-a.mp3', 'name': 'a.mp3', 'mimeType': 'audio/mpeg', 'size': 1234},
          {'path': '/cache/shared_audio/2-b', 'name': 'b', 'mimeType': 'audio/ogg'},
          {'name': 'no path is skipped'},
        ],
      });
      expect(payload.files.map((f) => f.path), ['/cache/shared_audio/1-a.mp3', '/cache/shared_audio/2-b']);
      expect(payload.files.first.name, 'a.mp3');
      expect(payload.files.first.mimeType, 'audio/mpeg');
      expect(payload.files.first.sizeBytes, 1234);
      expect(payload.files.last.sizeBytes, isNull);
    });

    test('nothing, blank text and junk are empty', () {
      expect(SharedPayload.fromMap(null).isEmpty, isTrue);
      expect(SharedPayload.fromMap({'text': '   '}).isEmpty, isTrue);
      expect(SharedPayload.fromMap({'files': 'nope'}).isEmpty, isTrue);
    });
  });

  group('PlatformShareIntake', () {
    const channel = MethodChannel('meditejo/share');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('the share that started the app is read once from the platform', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getInitial');
        return {'text': 'https://dharmaseed.org/talks/1/'};
      });
      final intake = PlatformShareIntake();
      expect((await intake.initial())!.text, 'https://dharmaseed.org/talks/1/');
    });

    test('a normal start has no share; a missing platform side is not an error', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      expect(await PlatformShareIntake().initial(), isNull);
      messenger.setMockMethodCallHandler(channel, null);
      expect(await PlatformShareIntake().initial(), isNull);
    });

    test('shares that arrive while the app is open are streamed', () async {
      final intake = PlatformShareIntake();
      final next = intake.shares.first;
      await messenger.handlePlatformMessage(
        'meditejo/share',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onShare', {'text': 'https://example.org/a.mp3'}),
        ),
        (_) {},
      );
      expect((await next).text, 'https://example.org/a.mp3');
    });
  });
}
