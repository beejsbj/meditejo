import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/cues/cue_settings.dart';
import 'package:medito/providers/cues/cue_settings_provider.dart';
import 'package:medito/services/audio/native_cue_controller.dart';
import 'package:medito/services/bells/bell_recipe.dart';
import 'package:medito/services/bells/bell_synth.dart';
import 'package:medito/services/bells/custom_bell.dart';
import 'package:medito/services/bells/custom_bell_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

BellKnobs _knobs([double pitch = 300]) =>
    BellKnobs(pitch: pitch, bright: 0.3, ring: 1, strike: 0.4, shimmer: 1);

const _request = PlaybackRequest(
  trackId: 'timer',
  fileId: 'timer-file',
  title: 'Timer',
  description: '',
  coverUrl: '',
  remoteUrl: '',
  duration: 600000,
  hasBackgroundSound: false,
);

/// What [NativeCueController.configure] sends the native engine, with
/// [bellFile] standing in for the app's store.
Future<Map<Object?, Object?>> configureAndCapture(
  CueSettings settings,
  Future<String?> Function(String id) bellFile,
) async {
  Map<Object?, Object?>? sent;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(NativeCueController.channel, (call) async {
    sent = Map<Object?, Object?>.from(call.arguments as Map);
    return null;
  });
  final real = NativeCueController.bellFile;
  NativeCueController.bellFile = bellFile;
  try {
    await NativeCueController.configure(settings, _request);
  } finally {
    NativeCueController.bellFile = real;
    messenger.setMockMethodCallHandler(NativeCueController.channel, null);
  }
  return sent!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late SharedPreferences prefs;
  late int renders;
  late CustomBellStore store;
  var clock = 1000;

  CustomBellStore make() => CustomBellStore(
    prefs,
    directory: () async => dir,
    // The real synth, in this isolate: the bytes are what an app would save.
    render: (spec) async {
      renders++;
      return BellSynth.render(spec);
    },
    random: Random(7),
    now: () => DateTime.fromMillisecondsSinceEpoch(clock += 1000),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    dir = await Directory.systemTemp.createTemp('bells');
    renders = 0;
    store = make();
  });
  tearDown(() => dir.delete(recursive: true));

  test('saving makes a stable id, a WAV file and a list entry', () async {
    final bell = await store.save(
      name: '  Evening   bowl ',
      spec: BellSpec('bowl_medium', _knobs()),
    );
    expect(isCustomBellId(bell.id), isTrue);
    expect(bell.name, 'Evening bowl');
    final path = await store.fileFor(bell.id);
    expect(path, '${dir.path}/${bell.token}.wav');
    expect(File(path!).lengthSync(), greaterThan(44));
    expect(store.all().map((b) => b.id), [bell.id]);
    // A new store over the same preferences (an app restart) finds it.
    expect(make().find(bell.id)?.name, 'Evening bowl');
    expect(make().find(bell.id)?.knobs, bell.knobs);
  });

  test('the file is the render of the spec, byte for byte', () async {
    final spec = BellSpec('temple', _knobs(210));
    final bell = await store.save(name: 'Low', spec: spec);
    final bytes = File((await store.fileFor(bell.id))!).readAsBytesSync();
    expect(bytes, orderedEquals(BellSynth.render(spec)));
  });

  test('a sound the caller already made is kept without rendering', () async {
    final spec = BellSpec('chime', _knobs(900));
    final wav = BellSynth.render(spec);
    final bell = await store.save(name: 'Chime', spec: spec, wav: wav);
    expect(renders, 0);
    expect(File((await store.fileFor(bell.id))!).readAsBytesSync(), wav);
  });

  test('a file that went missing is rendered again, identical', () async {
    final bell = await store.save(
      name: 'Bowl',
      spec: BellSpec('bowl_deep', _knobs(150)),
    );
    final path = (await store.fileFor(bell.id))!;
    final before = File(path).readAsBytesSync();
    File(path).deleteSync();
    expect(await store.fileFor(bell.id), path);
    expect(File(path).readAsBytesSync(), orderedEquals(before));
    expect(renders, 2);
  });

  test('rename keeps the id and the file', () async {
    final bell = await store.save(
      name: 'One',
      spec: BellSpec('gong', _knobs(120)),
    );
    final path = await store.fileFor(bell.id);
    await store.rename(bell.id, ' Two ');
    expect(store.all().single.id, bell.id);
    expect(store.all().single.name, 'Two');
    expect(await store.fileFor(bell.id), path);
    expect(() => store.rename(bell.id, '   '), throwsArgumentError);
  });

  test('delete removes the entry and the file, and only that bell', () async {
    final a = await store.save(name: 'A', spec: BellSpec('gong', _knobs(120)));
    final b = await store.save(name: 'B', spec: BellSpec('gong', _knobs(130)));
    final pathA = (await store.fileFor(a.id))!;
    await store.delete(a.id);
    expect(File(pathA).existsSync(), isFalse);
    expect(await store.fileFor(a.id), isNull);
    expect(store.all().map((x) => x.id), [b.id]);
    expect(File((await store.fileFor(b.id))!).existsSync(), isTrue);
  });

  test('ids are unique, and names are suggested without repeating', () async {
    expect(store.suggestName(), 'My bell');
    final ids = <String>{};
    for (var i = 0; i < 5; i++) {
      final bell = await store.save(
        name: store.suggestName(),
        spec: BellSpec('bowl_small', _knobs(600.0 + i)),
      );
      ids.add(bell.id);
    }
    expect(ids, hasLength(5));
    expect(store.all().map((b) => b.name), [
      'My bell',
      'My bell 2',
      'My bell 3',
      'My bell 4',
      'My bell 5',
    ]);
  });

  test('an empty name or a full shelf is refused', () async {
    expect(
      () => store.save(name: '  ', spec: BellSpec.preset('gong')),
      throwsArgumentError,
    );
    for (var i = 0; i < CustomBellStore.maxBells; i++) {
      await store.save(
        name: 'b$i',
        spec: BellSpec.preset('wood_block'),
        wav: Uint8List(50),
      );
    }
    expect(
      () => store.save(name: 'one more', spec: BellSpec.preset('gong')),
      throwsStateError,
    );
  });

  test('damaged or newer entries are skipped, and kept', () async {
    final good = await store.save(
      name: 'Good',
      spec: BellSpec('chime', _knobs(900)),
      wav: Uint8List(50),
    );
    final raw = jsonDecode(prefs.getString(CustomBellStore.prefsKey)!) as List;
    final newer = {
      'id': 'custom-bell:abcdef123456',
      'name': 'From the future',
      'preset': 'a-bell-this-version-lacks',
      'knobs': _knobs().toJson(),
    };
    await prefs.setString(
      CustomBellStore.prefsKey,
      jsonEncode([
        ...raw,
        newer,
        'junk',
        7,
        {'id': 3},
      ]),
    );
    expect(store.all().map((b) => b.id), [good.id]);
    await store.rename(good.id, 'Still good');
    final kept = jsonDecode(prefs.getString(CustomBellStore.prefsKey)!) as List;
    expect(
      kept.whereType<Map>().any(
        (m) => m['id'] == newer['id'] && m['preset'] == newer['preset'],
      ),
      isTrue,
      reason: 'the entry from the future is still stored',
    );
    await prefs.setString(CustomBellStore.prefsKey, '{not json');
    expect(store.all(), isEmpty);
  });

  test('saves made together do not lose one', () async {
    final saved = await Future.wait([
      for (var i = 0; i < 4; i++)
        store.save(
          name: 'b$i',
          spec: BellSpec('wood_block', _knobs(900.0 + i)),
          wav: Uint8List(50),
        ),
    ]);
    expect(store.all(), hasLength(4));
    expect({for (final b in saved) b.id}, hasLength(4));
  });

  group('in the cue settings and the native configuration', () {
    test('a made bell is a valid cue sound and survives a round trip', () {
      final s = CueSettings.fromJson({
        'startSound': 'custom-bell:abcdef1234',
        'intervalSound': 'custom-bell:zzzzzz0000',
        'endSound': 'assets/audio/bell_temple.wav',
        'intervalMinutes': 5,
      });
      expect(s.startSound, 'custom-bell:abcdef1234');
      expect(s.intervalSound, 'custom-bell:zzzzzz0000');
      expect(s.endSound, 'assets/audio/bell_temple.wav');
      expect(s.hasIntervalBell, isTrue);
      final again = CueSettings.decode(
        jsonEncode(s.toJson()),
        CueKind.practice,
      );
      expect(again.startSound, s.startSound);
    });

    test('anything else is still the default bell', () {
      for (final bad in [
        'custom-bell:',
        'custom-bell:AB',
        'custom-bell:abc def',
        'custom-bell:../../etc/passwd',
        '/data/data/x/files/bell.wav',
        'custom-bell:${'a' * 33}',
      ]) {
        expect(
          CueSettings.fromJson({'startSound': bad}).startSound,
          cueDefaultBell,
          reason: bad,
        );
      }
      // The pulse takes no made bell.
      expect(
        CueSettings.fromJson({
          'pulseSound': 'custom-bell:abcdef1234',
        }).pulseSound,
        '',
      );
    });

    test('a saved bell resolves to its file for the native engine', () async {
      final bell = await store.save(
        name: 'Mine',
        spec: BellSpec('bowl_small', _knobs(640)),
      );
      final settings = CueSettings(
        startSound: bell.id,
        intervalSound: bell.id,
        intervalMinutes: 5,
        endSound: 'assets/audio/bell_temple.wav',
      );
      final sent = await configureAndCapture(settings, store.fileFor);
      final path = (await store.fileFor(bell.id))!;
      expect(sent['startSound'], path);
      expect(sent['intervalSound'], path);
      expect(sent['endSound'], 'assets/audio/bell_temple.wav');
      expect(File(sent['startSound'] as String).existsSync(), isTrue);
    });

    test('configurations reach the native side in the order asked', () async {
      final sent = <String?>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeCueController.channel, (
        call,
      ) async {
        sent.add((call.arguments as Map)['startSound'] as String?);
        return null;
      });
      final real = NativeCueController.bellFile;
      // The made bell's file takes a while; the bundled bell asked for after
      // it does not wait on anything.
      NativeCueController.bellFile = (id) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return '/files/slow.wav';
      };
      try {
        final first = NativeCueController.configure(
          const CueSettings(startSound: 'custom-bell:abcdef1234'),
          _request,
          update: true,
        );
        final second = NativeCueController.configure(
          const CueSettings(startSound: 'assets/audio/bell_temple.wav'),
          _request,
          update: true,
        );
        await Future.wait([first, second]);
      } finally {
        NativeCueController.bellFile = real;
        messenger.setMockMethodCallHandler(NativeCueController.channel, null);
      }
      expect(sent, ['/files/slow.wav', 'assets/audio/bell_temple.wav']);
    });

    test('a deleted bell rings as the default bell, not as nothing', () async {
      final bell = await store.save(
        name: 'Gone',
        spec: BellSpec('chime', _knobs(900)),
        wav: Uint8List(50),
      );
      await store.delete(bell.id);
      final sent = await configureAndCapture(
        CueSettings(startSound: bell.id, endSound: '', intervalSound: ''),
        store.fileFor,
      );
      expect(sent['startSound'], cueDefaultBell);
      expect(sent['endSound'], isNull);
      expect(sent['intervalSound'], isNull);
    });

    test('a bell that cannot be made falls back too', () async {
      final sent = await configureAndCapture(
        const CueSettings(startSound: 'custom-bell:abcdef1234'),
        (_) async => throw StateError('disk full'),
      );
      expect(sent['startSound'], cueDefaultBell);
    });

    test('deleting a bell moves every stored cue that rang it', () async {
      final bell = await store.save(
        name: 'Both',
        spec: BellSpec('chime', _knobs(900)),
        wav: Uint8List(50),
      );
      final cues = CueSettingsStore(prefs);
      await cues.save(
        const CueScope(CueKind.practice),
        CueSettings(startSound: bell.id, endSound: bell.id),
      );
      await cues.save(
        const CueScope(CueKind.talks, courseId: 'c1'),
        CueSettings(intervalSound: bell.id, intervalMinutes: 5),
      );
      await cues.save(
        const CueScope(CueKind.talks),
        const CueSettings(startSound: 'assets/audio/bell_gong.wav'),
      );
      await cues.replaceSound(bell.id, cueDefaultBell);
      final practice = cues.read(const CueScope(CueKind.practice));
      expect(practice.startSound, cueDefaultBell);
      expect(practice.endSound, cueDefaultBell);
      expect(
        cues.read(const CueScope(CueKind.talks, courseId: 'c1')).intervalSound,
        cueDefaultBell,
      );
      expect(
        cues.read(const CueScope(CueKind.talks)).startSound,
        'assets/audio/bell_gong.wav',
      );
    });
  });
}
