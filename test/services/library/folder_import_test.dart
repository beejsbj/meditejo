import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/providers/library/import_providers.dart';
import 'package:medito/services/library/folder_import.dart';
import 'package:medito/services/library/import_models.dart';

/// The contract with `FolderImportBridge` (Kotlin): the calls Dart makes, in
/// order, and what it does with each answer.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ChannelFolderImporter.channelName);
  late ChannelFolderImporter importer;
  late List<String> calls;
  late FutureOr<Object?> Function(MethodCall call) native;

  /// What a happy `pick` / `scan` / `copy` say, replaceable per test.
  Object? happy(MethodCall call) => switch (call.method) {
    'pick' => {'treeUri': 'content://tree/Meditation', 'name': 'Meditation'},
    'scan' => {
      'audioCount': 3,
      'totalBytes': 3000,
      'entriesSeen': 4,
      'unreadableFolders': 0,
      'truncated': false,
    },
    'copy' => {
      'files': [
        for (var i = 1; i <= 3; i++)
          {
            'path': '/cache/folder_import/00$i-Session $i.mp3',
            'name': 'Session $i.mp3',
            'mimeType': 'audio/mpeg',
            'size': 1000,
          },
      ],
      'skipped': <String>[],
    },
    _ => null,
  };

  setUp(() {
    calls = [];
    native = happy;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return native(call);
        });
    importer = ChannelFolderImporter(channel: channel);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    channel.setMethodCallHandler(null);
  });

  Future<ImportFailureReason> failureOf() async {
    try {
      await importer.importFolder();
    } on ImportFailure catch (e) {
      return e.reason;
    }
    fail('expected an ImportFailure');
  }

  /// A progress call from the native side, as `FolderImportBridge` sends it.
  Future<void> nativeProgress(Map<String, Object?> payload) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('progress', payload),
          ),
          (_) {},
        );
  }

  test('a picked folder is scanned, copied and handed back as files', () async {
    final folder = (await importer.importFolder())!;

    expect(calls, ['pick', 'scan', 'copy']);
    expect(folder.path, isNull);
    expect(folder.name, 'Meditation');
    expect(folder.files.map((f) => f.name), [
      'Session 1.mp3',
      'Session 2.mp3',
      'Session 3.mp3',
    ]);
    expect(folder.files.first.path, '/cache/folder_import/001-Session 1.mp3');
    expect(folder.files.first.mimeType, 'audio/mpeg');
    expect(folder.unreadable, 0);
  });

  test('progress from the native copy reaches the caller', () async {
    final seen = <FolderProgress>[];
    native = (call) async {
      if (call.method == 'copy') {
        await nativeProgress({
          'filesDone': 1,
          'filesTotal': 3,
          'bytesDone': 1500,
          'bytesTotal': 3000,
          'name': 'Session 2.mp3',
        });
      }
      return happy(call);
    };

    await importer.importFolder(onProgress: seen.add);

    expect(seen.first.filesDone, 0, reason: 'starts at nothing copied');
    expect(seen.first.filesTotal, 3);
    final mid = seen.firstWhere((p) => p.name == 'Session 2.mp3');
    expect(mid.fraction, 0.5);
    expect(mid.filesDone, 1);
  });

  test('progress after the import ended is ignored', () async {
    var calls = 0;
    await importer.importFolder(onProgress: (_) => calls++);
    final during = calls;
    await nativeProgress({'filesDone': 3, 'filesTotal': 3});
    expect(calls, during, reason: 'nobody is listening any more');
  });

  test('backing out of the picker is a quiet null, nothing scanned', () async {
    native = (call) => call.method == 'pick' ? null : happy(call);

    expect(await importer.importFolder(), isNull);
    expect(calls, ['pick']);
  });

  test('cancelling the copy is a quiet null', () async {
    native = (call) => call.method == 'copy'
        ? throw PlatformException(code: 'cancelled')
        : happy(call);

    expect(await importer.importFolder(), isNull);
    expect(calls, ['pick', 'scan', 'copy']);
  });

  test('cancelling the scan is a quiet null too', () async {
    native = (call) => call.method == 'scan'
        ? throw PlatformException(code: 'cancelled')
        : happy(call);

    expect(await importer.importFolder(), isNull);
  });

  group('failures are reasons, never codes', () {
    Map<String, Object?> scan({
      int audio = 0,
      int seen = 0,
      int unreadable = 0,
      bool truncated = false,
    }) => {
      'audioCount': audio,
      'totalBytes': 0,
      'entriesSeen': seen,
      'unreadableFolders': unreadable,
      'truncated': truncated,
    };

    test('an empty folder is told apart from one without audio', () async {
      native = (call) => call.method == 'scan' ? scan() : happy(call);
      expect(await failureOf(), ImportFailureReason.folderEmpty);
      expect(calls, ['pick', 'scan'], reason: 'nothing is copied');

      calls.clear();
      native = (call) => call.method == 'scan' ? scan(seen: 6) : happy(call);
      expect(await failureOf(), ImportFailureReason.noAudioFiles);
      expect(calls, ['pick', 'scan']);
    });

    test('a folder the provider will not list is unreadable', () async {
      native = (call) =>
          call.method == 'scan' ? scan(unreadable: 1) : happy(call);
      expect(await failureOf(), ImportFailureReason.folderUnreadable);
    });

    test('more audio than a course should hold stops before copying', () async {
      native = (call) => call.method == 'scan'
          ? scan(audio: 1000, seen: 1001, truncated: true)
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderTooLarge);
      expect(calls, ['pick', 'scan']);
    });

    test('a full phone says so', () async {
      native = (call) => call.method == 'copy'
          ? throw PlatformException(code: 'no_space')
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderNoSpace);
    });

    test('a device with no folder picker says so', () async {
      native = (call) => call.method == 'pick'
          ? throw PlatformException(code: 'no_picker')
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderUnavailable);
    });

    test('a lost permission or failed copy is unreadable', () async {
      native = (call) => call.method == 'scan'
          ? throw PlatformException(code: 'unreadable')
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderUnreadable);

      native = (call) => call.method == 'copy'
          ? throw PlatformException(code: 'copy_failed')
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderUnreadable);
    });

    test('when no file could be read, that is the answer', () async {
      native = (call) => call.method == 'copy'
          ? {
              'files': <Object?>[],
              'skipped': ['a.mp3', 'b.mp3', 'c.mp3'],
            }
          : happy(call);
      expect(await failureOf(), ImportFailureReason.folderUnreadable);
    });
  });

  test('unreadable files and folders are counted for the preview', () async {
    native = (call) async {
      if (call.method == 'scan') {
        return {
          'audioCount': 3,
          'totalBytes': 3000,
          'entriesSeen': 5,
          'unreadableFolders': 1,
          'truncated': false,
        };
      }
      if (call.method == 'copy') {
        final answer = happy(call) as Map<String, Object?>;
        return {
          'files': (answer['files'] as List).take(1).toList(),
          'skipped': ['Session 2.mp3', 'Session 3.mp3'],
        };
      }
      return happy(call);
    };

    final folder = (await importer.importFolder())!;
    expect(folder.files, hasLength(1));
    expect(folder.unreadable, 3, reason: '2 files and 1 folder');
  });

  test('cancel and discard are plain calls, and never throw', () async {
    await importer.cancel();
    await importer.discard();
    expect(calls, ['cancel', 'discard']);

    native = (call) => throw PlatformException(code: 'busy');
    await importer.cancel();
    native = (call) => throw MissingPluginException();
    await importer.discard();
  });

  group('the pickers choose by platform', () {
    test('on Android the folder importer does the work', () async {
      final fake = _FakeImporter(
        const PickedFolder.copied(name: 'Retreat', files: []),
      );
      final pickers = SystemImportPickers(folders: fake, isAndroid: true);

      final folder = await pickers.pickFolder();
      expect(folder!.name, 'Retreat');
      await pickers.cancelFolderImport();
      await pickers.discardFolderImport();
      expect(fake.log, ['import', 'cancel', 'discard']);
    });

    test('elsewhere there is nothing to cancel or discard', () async {
      final fake = _FakeImporter(null);
      final pickers = SystemImportPickers(folders: fake, isAndroid: false);

      await pickers.cancelFolderImport();
      await pickers.discardFolderImport();
      expect(fake.log, isEmpty);
    });
  });
}

class _FakeImporter implements FolderImporter {
  _FakeImporter(this.answer);

  final PickedFolder? answer;
  final log = <String>[];

  @override
  Future<PickedFolder?> importFolder({
    void Function(FolderProgress)? onProgress,
  }) async {
    log.add('import');
    return answer;
  }

  @override
  Future<void> cancel() async => log.add('cancel');

  @override
  Future<void> discard() async => log.add('discard');
}
