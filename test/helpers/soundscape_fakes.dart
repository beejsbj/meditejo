import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:medito/models/soundscape/sound_library.dart';
import 'package:medito/providers/soundscape/sound_pack_provider.dart';
import 'package:medito/providers/soundscape/soundscape_provider.dart';
import 'package:medito/services/soundscape/sound_pack_service.dart';
import 'package:medito/services/soundscape/soundscape_engine.dart';
import 'package:medito/services/soundscape/soundscape_keep_alive.dart';

/// A silent [SoundscapeEngine] that records what it was asked to play.
class FakeSoundscapeEngine implements SoundscapeEngine {
  final playing = <String, double>{};
  double master = 1;
  bool paused = false;

  @override
  Future<bool> start(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    playing[key] = gain;
    return true;
  }

  final retuned = <String, LayerSource>{};

  @override
  Future<bool> retune(
    String key,
    LayerSource source, {
    required double gain,
    LayerMotion? motion,
  }) async {
    retuned[key] = source;
    playing[key] = gain;
    return true;
  }

  @override
  void setGain(String key, double gain, {LayerMotion? motion}) =>
      playing[key] = gain;

  @override
  Future<void> stop(String key, {Duration fade = Duration.zero}) async =>
      playing.remove(key);

  @override
  void setMaster(double gain, {Duration fade = Duration.zero}) => master = gain;

  @override
  void setPaused(bool paused) => this.paused = paused;

  @override
  Future<void> stopAll({Duration fade = Duration.zero}) async =>
      playing.clear();

  int shutdowns = 0;

  @override
  Future<void> shutdown() async => shutdowns++;
}

/// The bundled library, read straight from disk: `rootBundle` hands an
/// asset this size to an isolate, which a widget test's fake clock never
/// lets finish.
final bundledSoundLibrary = SoundLibrary.fromJson(
  jsonDecode(File(kSoundLibraryAsset).readAsStringSync())
      as Map<String, Object?>,
);

/// The sound pack with a fixed set of sounds on the phone and no disk, no
/// network: [downloaded] ids, or every pack sound when null. For tests that
/// play with the whole library, and for widget tests (whose fake clock never
/// lets real file I/O finish). It records what was asked of it.
class FakeSoundPack extends SoundPackController {
  FakeSoundPack([this.downloaded, this.instant = true]);

  final Set<String>? downloaded;

  /// Whether a download lands at once. When false it stays in flight, at 40%,
  /// until a test changes it.
  final bool instant;

  /// Ids asked for, in order, and the other calls received.
  final asked = <String>[];
  final cancelled = <String>[];
  final retried = <String>[];
  final askedAnyNetwork = <String>[];
  int cancelAlls = 0;
  int deletes = 0;

  @override
  SoundPackState build() => SoundPackState(
    scanned: true,
    downloaded:
        downloaded ?? {for (final s in bundledSoundLibrary.packSounds) s.id},
    usedBytes: 1234567,
  );

  @override
  Future<void> get ready async {}

  @override
  File? fileOf(SoundEntry sound) => state.downloaded.contains(sound.id)
      ? File('/sound-pack/${sound.file}')
      : null;

  @override
  Future<void> download(Iterable<String> ids, {bool anyNetwork = false}) async {
    final wanted = ids.toList();
    asked.addAll(wanted);
    if (anyNetwork) askedAnyNetwork.addAll(wanted);
    if (instant) {
      state = state.copyWith(downloaded: {...state.downloaded, ...wanted});
      return;
    }
    state = state.copyWith(
      downloads: {
        ...state.downloads,
        for (final id in wanted)
          id: SoundDownload(
            SoundDownloadPhase.downloading,
            received: 40,
            total: 100,
          ),
      },
      batchTotal: wanted.length,
    );
  }

  @override
  Future<void> downloadAll({bool anyNetwork = false}) => download([
    for (final s in bundledSoundLibrary.packSounds)
      if (!state.downloaded.contains(s.id)) s.id,
  ], anyNetwork: anyNetwork);

  @override
  Future<void> retry({Iterable<String>? ids, bool anyNetwork = false}) {
    final again = ids ?? state.downloads.keys;
    retried.addAll(again);
    return download(again.toList(), anyNetwork: anyNetwork);
  }

  @override
  void cancel(String id) {
    cancelled.add(id);
    state = state.copyWith(downloads: {...state.downloads}..remove(id));
  }

  @override
  void cancelAll() {
    cancelAlls++;
    state = state.copyWith(downloads: const {}, waitingForWifi: false);
  }

  @override
  Future<void> deleteAll() async {
    deletes++;
    state = state.copyWith(downloaded: const {}, usedBytes: 0);
  }

  @override
  Future<void> setWifiOnly(bool wifiOnly) async =>
      state = state.copyWith(wifiOnly: wifiOnly);

  /// Test controls: put a sound in a state, or make the queue wait for Wi-Fi.
  void setDownload(String id, SoundDownload download) =>
      state = state.copyWith(downloads: {...state.downloads, id: download});

  void setWaitingForWifi(bool waiting) =>
      state = state.copyWith(waitingForWifi: waiting);
}

/// A downloader that writes a file of the right size, or fails, or waits.
class FakeSoundPackDownloader extends SoundPackDownloader {
  FakeSoundPackDownloader() : super(client: _NoClient());

  final calls = <String>[];

  /// Ids that fail, with how.
  final failures = <String, SoundDownloadFailure>{};

  /// While set, downloads of these ids wait for [release] (progress is
  /// reported at half first).
  final held = <String>{};
  final _gate = <String, Completer<void>>{};

  void release(String id) => _gate.remove(id)?.complete();

  @override
  Future<void> download(
    SoundEntry sound,
    Uri url,
    SoundPackFiles files, {
    void Function(int received, int total)? onProgress,
    SoundDownloadCancel? cancel,
  }) async {
    calls.add(sound.id);
    onProgress?.call(sound.bytes ~/ 2, sound.bytes);
    if (held.contains(sound.id)) {
      final gate = _gate[sound.id] = Completer<void>();
      await Future.any([gate.future, ?cancel?.whenCancelled]);
      if (cancel?.isCancelled ?? false) return;
    }
    final failure = failures[sound.id];
    if (failure != null) throw SoundDownloadException(failure, 'test');
    await files.directory.create(recursive: true);
    await files.fileFor(sound).writeAsBytes(List.filled(sound.bytes, 0));
    onProgress?.call(sound.bytes, sound.bytes);
  }
}

class _NoClient implements http.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('a fake downloader never touches the network');
}

class FakeNetworkWatcher implements NetworkWatcher {
  FakeNetworkWatcher({this.unmetered = true});

  bool unmetered;
  final _changes = StreamController<bool>.broadcast();

  void setUnmetered(bool value) {
    unmetered = value;
    _changes.add(value);
  }

  @override
  Future<bool> onUnmetered() async => unmetered;

  @override
  Stream<bool> get unmeteredChanges => _changes.stream;
}

/// The real [SoundPackController] over a temporary directory, with a fake
/// downloader and network, for tests of what downloading does.
class SoundPackFixture {
  SoundPackFixture({bool unmetered = true})
    : network = FakeNetworkWatcher(unmetered: unmetered);

  final directory = Directory.systemTemp.createTempSync('sound_pack_fixture');
  final downloader = FakeSoundPackDownloader();
  final FakeNetworkWatcher network;

  /// Puts [ids] on the "phone": files of the pinned size, where the
  /// controller looks.
  void stage(SoundLibrary library, Iterable<String> ids) {
    final files = SoundPackFiles(Directory('${directory.path}/pack'))
      ..directory.createSync(recursive: true);
    for (final id in ids) {
      final sound = library[id]!;
      files.fileFor(sound).writeAsBytesSync(List.filled(sound.bytes, 0));
    }
  }

  List<Override> get overrides => [
    soundPackDirectoryProvider.overrideWithValue(
      Future.value(Directory('${directory.path}/pack')),
    ),
    soundPackDownloaderProvider.overrideWithValue(downloader),
    networkWatcherProvider.overrideWithValue(network),
  ];

  void dispose() => directory.deleteSync(recursive: true);
}

/// Overrides that keep widget tests away from the audio device and the
/// Android keep-alive channel. The library is the bundled one, and every
/// sound of the pack counts as downloaded unless [soundPack] says otherwise.
List<Override> soundscapeTestOverrides(
  FakeSoundscapeEngine engine, {
  List<Override>? soundPack,
}) => [
  soundLibraryProvider.overrideWith((ref) async => bundledSoundLibrary),
  soundscapeEngineProvider.overrideWithValue(engine),
  soundscapeKeepAliveProvider.overrideWithValue(
    const NoopSoundscapeKeepAlive(),
  ),
  ...?soundPack ?? [soundPackProvider.overrideWith(FakeSoundPack.new)],
];
