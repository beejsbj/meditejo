import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/soundscape/sound_library.dart';
import '../../services/soundscape/sound_pack_service.dart';
import '../../utils/logger.dart';
import '../shared_preference/shared_preference_provider.dart';
import 'sound_library_provider.dart';

/// Shared preferences key: download the sound pack on Wi-Fi only (default on).
const kSoundPackWifiOnlyKey = 'sound_pack_wifi_only';

/// Where downloaded sounds live: the app's own storage, which Android
/// removes with the app. A test overrides it.
final soundPackDirectoryProvider = Provider<Future<Directory>>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}${Platform.pathSeparator}sound_pack');
});

final soundPackDownloaderProvider = Provider<SoundPackDownloader>((ref) {
  final downloader = SoundPackDownloader();
  ref.onDispose(downloader.close);
  return downloader;
});

/// Whether the phone is on a network that is not a mobile connection (Wi-Fi
/// or Ethernet), and when that changes. A test overrides it.
abstract class NetworkWatcher {
  Future<bool> onUnmetered();
  Stream<bool> get unmeteredChanges;
}

class ConnectivityNetworkWatcher implements NetworkWatcher {
  static bool _unmetered(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);

  @override
  Future<bool> onUnmetered() async =>
      _unmetered(await Connectivity().checkConnectivity());

  @override
  Stream<bool> get unmeteredChanges =>
      Connectivity().onConnectivityChanged.map(_unmetered).distinct();
}

final networkWatcherProvider = Provider<NetworkWatcher>(
  (ref) => ConnectivityNetworkWatcher(),
);

enum SoundDownloadPhase { queued, downloading, failed }

/// One sound that is being fetched, waiting, or did not arrive.
@immutable
class SoundDownload {
  const SoundDownload(
    this.phase, {
    this.received = 0,
    this.total = 0,
    this.failure,
  });

  final SoundDownloadPhase phase;
  final int received;
  final int total;
  final SoundDownloadFailure? failure;

  bool get inFlight => phase != SoundDownloadPhase.failed;

  /// 0–1, or null before the first byte.
  double? get progress => total > 0 && received > 0 ? received / total : null;
}

@immutable
class SoundPackState {
  const SoundPackState({
    this.scanned = false,
    this.downloaded = const {},
    this.downloads = const {},
    this.wifiOnly = true,
    this.waitingForWifi = false,
    this.usedBytes = 0,
    this.batchTotal = 0,
    this.batchDone = 0,
  });

  /// False until the disk was read once; until then nothing counts as
  /// downloaded.
  final bool scanned;

  /// Ids of the pack sounds whose file is on this phone, whole.
  final Set<String> downloaded;

  /// Sounds being fetched, queued, or whose last try failed, by id.
  final Map<String, SoundDownload> downloads;
  final bool wifiOnly;

  /// Something is queued but waits for Wi-Fi (the setting is on and the
  /// phone is on a mobile connection).
  final bool waitingForWifi;

  /// Bytes the downloaded sounds take on disk.
  final int usedBytes;

  /// The current run of downloads: how many were asked for, and how many
  /// have arrived. Starts again when a download is asked for while idle.
  final int batchTotal;
  final int batchDone;

  bool get busy => downloads.values.any((d) => d.inFlight);

  bool get hasFailures =>
      downloads.values.any((d) => d.phase == SoundDownloadPhase.failed);

  /// Whether [sound] can be played now: shipped in the APK, or downloaded.
  bool isAvailable(SoundEntry sound) =>
      sound.bundled || downloaded.contains(sound.id);

  SoundDownload? downloadOf(String id) => downloads[id];

  SoundPackState copyWith({
    bool? scanned,
    Set<String>? downloaded,
    Map<String, SoundDownload>? downloads,
    bool? wifiOnly,
    bool? waitingForWifi,
    int? usedBytes,
    int? batchTotal,
    int? batchDone,
  }) => SoundPackState(
    scanned: scanned ?? this.scanned,
    downloaded: downloaded ?? this.downloaded,
    downloads: downloads ?? this.downloads,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    waitingForWifi: waitingForWifi ?? this.waitingForWifi,
    usedBytes: usedBytes ?? this.usedBytes,
    batchTotal: batchTotal ?? this.batchTotal,
    batchDone: batchDone ?? this.batchDone,
  );
}

final soundPackProvider = NotifierProvider<SoundPackController, SoundPackState>(
  SoundPackController.new,
);

class _Job {
  _Job(this.sound, this.allowMobile);

  final SoundEntry sound;

  /// This job was asked for despite the Wi-Fi-only setting ("Download
  /// anyway").
  bool allowMobile;
  SoundDownloadCancel? cancel;
}

/// Downloads the sound pack's files one at a time, on request, and keeps
/// track of what is on the phone. Never downloads by itself.
class SoundPackController extends Notifier<SoundPackState> {
  late SharedPreferences _prefs;
  late SoundPackDownloader _downloader;
  late NetworkWatcher _network;
  SoundLibrary _library = SoundLibrary.empty;
  SoundPackFiles? _files;
  final _queue = <_Job>[];
  bool _pumping = false;
  StreamSubscription<bool>? _networkSub;
  late Future<void> _ready;

  /// Completes once the disk was read.
  Future<void> get ready => _ready;

  /// How often a download's progress reaches the screen.
  @visibleForTesting
  static Duration progressInterval = const Duration(milliseconds: 150);

  @override
  SoundPackState build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    _downloader = ref.watch(soundPackDownloaderProvider);
    _network = ref.watch(networkWatcherProvider);
    ref.onDispose(() {
      _networkSub?.cancel();
      for (final job in _queue) {
        job.cancel?.cancel();
      }
    });
    _ready = _scan();
    return SoundPackState(
      wifiOnly: _prefs.getBool(kSoundPackWifiOnlyKey) ?? true,
    );
  }

  Future<SoundPackFiles> _filesOnDisk() async =>
      _files ??= SoundPackFiles(await ref.read(soundPackDirectoryProvider));

  Future<void> _scan() async {
    try {
      _library = await ref.read(soundLibraryProvider.future);
      final files = await _filesOnDisk();
      final present = await files.scan(
        _library.packSounds,
        tidy: _queue.isEmpty,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        scanned: true,
        downloaded: present,
        usedBytes: await files.usedBytes(),
      );
    } catch (error, stack) {
      // Without a readable disk nothing counts as downloaded: the sounds
      // are offered again rather than failing in the mixer.
      AppLogger.e('SOUNDSCAPE', 'Could not read the sound pack', error, stack);
      if (ref.mounted) state = state.copyWith(scanned: true);
    }
  }

  /// The file of a downloaded pack sound, or null.
  File? fileOf(SoundEntry sound) {
    final files = _files;
    if (files == null || !state.downloaded.contains(sound.id)) return null;
    return files.fileFor(sound);
  }

  Future<void> setWifiOnly(bool wifiOnly) async {
    await _prefs.setBool(kSoundPackWifiOnlyKey, wifiOnly);
    state = state.copyWith(wifiOnly: wifiOnly);
    // Turning it off releases what waited for Wi-Fi.
    if (!wifiOnly) unawaited(_pump());
  }

  /// Queues [ids] (pack sounds not on the phone). With [anyNetwork], these
  /// go ahead on a mobile connection despite the Wi-Fi-only setting.
  Future<void> download(Iterable<String> ids, {bool anyNetwork = false}) async {
    await _ready;
    if (!ref.mounted) return;
    final downloads = {...state.downloads};
    // A new run when nothing was in flight.
    final fresh = !state.busy;
    var added = 0;
    for (final id in ids) {
      final sound = _library[id];
      if (sound == null || sound.bundled || state.downloaded.contains(id)) {
        continue;
      }
      final queued = _queue.where((j) => j.sound.id == id).firstOrNull;
      if (queued != null) {
        queued.allowMobile = queued.allowMobile || anyNetwork;
        continue;
      }
      _queue.add(_Job(sound, anyNetwork));
      downloads[id] = SoundDownload(
        SoundDownloadPhase.queued,
        total: sound.bytes,
      );
      added++;
    }
    state = state.copyWith(
      downloads: downloads,
      batchTotal: (fresh ? 0 : state.batchTotal) + added,
      batchDone: fresh ? 0 : state.batchDone,
    );
    unawaited(_pump());
  }

  /// Everything of the pack that is not on the phone.
  Future<void> downloadAll({bool anyNetwork = false}) => download([
    for (final s in _library.packSounds)
      if (!state.downloaded.contains(s.id)) s.id,
  ], anyNetwork: anyNetwork);

  /// Retries what failed.
  Future<void> retry({Iterable<String>? ids, bool anyNetwork = false}) =>
      download(
        ids ??
            [
              for (final e in state.downloads.entries)
                if (e.value.phase == SoundDownloadPhase.failed) e.key,
            ],
        anyNetwork: anyNetwork,
      );

  /// Stops [id]: a running download is aborted, a queued one dropped, a
  /// failed one forgotten.
  void cancel(String id) {
    final job = _queue.where((j) => j.sound.id == id).firstOrNull;
    if (job != null) {
      _queue.remove(job);
      job.cancel?.cancel();
    }
    _forget([id]);
  }

  void cancelAll() {
    for (final job in [..._queue]) {
      job.cancel?.cancel();
    }
    _queue.clear();
    state = state.copyWith(
      downloads: const {},
      waitingForWifi: false,
      batchTotal: 0,
      batchDone: 0,
    );
  }

  /// Removes every downloaded sound (Settings › Library & downloads).
  Future<void> deleteAll() async {
    cancelAll();
    await _ready;
    final files = await _filesOnDisk();
    await files.deleteAll();
    if (!ref.mounted) return;
    state = state.copyWith(downloaded: const {}, usedBytes: 0);
  }

  void _forget(Iterable<String> ids) {
    final downloads = {...state.downloads}
      ..removeWhere((id, _) => ids.contains(id));
    state = state.copyWith(
      downloads: downloads,
      waitingForWifi: _queue.isNotEmpty && state.waitingForWifi,
      // What was dropped is no longer part of the run.
      batchTotal: (state.batchTotal - ids.length).clamp(0, state.batchTotal),
    );
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (ref.mounted && _queue.isNotEmpty) {
        final job = _queue.first;
        if (state.wifiOnly &&
            !job.allowMobile &&
            !await _network.onUnmetered()) {
          _waitForWifi();
          return;
        }
        if (state.waitingForWifi) state = state.copyWith(waitingForWifi: false);
        await _run(job);
      }
    } finally {
      _pumping = false;
    }
  }

  /// Holds the queue until Wi-Fi returns.
  void _waitForWifi() {
    state = state.copyWith(waitingForWifi: true);
    _networkSub ??= _network.unmeteredChanges.listen((unmetered) {
      if (!unmetered) return;
      _networkSub?.cancel();
      _networkSub = null;
      unawaited(_pump());
    });
  }

  Future<void> _run(_Job job) async {
    final sound = job.sound;
    final id = sound.id;
    final cancel = job.cancel = SoundDownloadCancel();
    final files = await _filesOnDisk();
    final pin = _library.pack;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    void report(SoundDownload download) {
      if (!ref.mounted || cancel.isCancelled) return;
      state = state.copyWith(downloads: {...state.downloads, id: download});
    }

    report(SoundDownload(SoundDownloadPhase.downloading, total: sound.bytes));
    try {
      if (pin == null) {
        throw const SoundDownloadException(
          SoundDownloadFailure.server,
          'The library pins no sound pack release',
        );
      }
      await _downloader.download(
        sound,
        pin.urlFor(sound),
        files,
        cancel: cancel,
        onProgress: (received, total) {
          final now = DateTime.now();
          if (received < total &&
              now.difference(lastReport) < progressInterval) {
            return;
          }
          lastReport = now;
          report(
            SoundDownload(
              SoundDownloadPhase.downloading,
              received: received,
              total: total,
            ),
          );
        },
      );
      _queue.remove(job);
      if (!ref.mounted) return;
      if (cancel.isCancelled) {
        _forget([id]);
        return;
      }
      final downloads = {...state.downloads}..remove(id);
      state = state.copyWith(
        downloaded: {...state.downloaded, id},
        downloads: downloads,
        batchDone: state.batchDone + 1,
        usedBytes: await files.usedBytes(),
      );
    } on SoundDownloadException catch (e) {
      AppLogger.w('SOUNDSCAPE', 'Could not download $id: $e');
      _queue.remove(job);
      if (!ref.mounted) return;
      report(
        SoundDownload(
          SoundDownloadPhase.failed,
          total: sound.bytes,
          failure: e.failure,
        ),
      );
    } catch (error, stack) {
      AppLogger.e('SOUNDSCAPE', 'Could not download $id', error, stack);
      _queue.remove(job);
      if (!ref.mounted) return;
      report(
        SoundDownload(
          SoundDownloadPhase.failed,
          total: sound.bytes,
          failure: SoundDownloadFailure.storage,
        ),
      );
    }
  }
}
