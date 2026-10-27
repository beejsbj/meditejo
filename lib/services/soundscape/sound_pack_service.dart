import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../models/soundscape/sound_library.dart';
import '../../services/updates/update_release.dart' show kReleaseDownloadPrefix;

/// Why a sound's download did not finish.
enum SoundDownloadFailure {
  /// No network, a timeout, or a connection that broke part-way.
  network,

  /// The release answered with an error (a missing file, a rate limit).
  server,

  /// What arrived is not the file the library pins (its size or SHA-256).
  integrity,

  /// The phone could not store it.
  storage,
}

class SoundDownloadException implements Exception {
  const SoundDownloadException(this.failure, [this.detail = '']);

  final SoundDownloadFailure failure;
  final String detail;

  @override
  String toString() => 'SoundDownloadException(${failure.name}: $detail)';
}

/// Lets a running download be stopped from outside.
class SoundDownloadCancel {
  bool _cancelled = false;
  final _stopped = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _stopped.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _stopped.complete();
  }
}

/// The downloaded sounds on disk, in one directory of the app's own storage.
///
/// A file is `<id>-<first 12 hex of its SHA-256>.opus`, so a sound that a
/// later pack changed is a different file and the old one is simply stale.
/// Only a complete file is ever at that name: a download streams into a
/// `.part` file, is checked against the library's size and SHA-256, and is
/// renamed into place.
class SoundPackFiles {
  SoundPackFiles(this.directory);

  final Directory directory;

  static const partSuffix = '.part';

  File fileFor(SoundEntry sound) => File(
    '${directory.path}${Platform.pathSeparator}'
    '${sound.id}-${sound.sha256.substring(0, 12)}.opus',
  );

  File partFor(SoundEntry sound) => File('${fileFor(sound).path}$partSuffix');

  /// The ids of [sounds] whose file is here and the right size. A file is
  /// only moved into place after its hash was checked, so its size is the
  /// cheap test that it is still whole. Anything else in the directory
  /// (stale files from an older pack, abandoned partial downloads) is
  /// removed when [tidy] is set.
  Future<Set<String>> scan(
    Iterable<SoundEntry> sounds, {
    bool tidy = false,
  }) async {
    if (!await directory.exists()) return {};
    final wanted = {for (final s in sounds) fileFor(s).path: s};
    final present = <String>{};
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File) continue;
      final sound = wanted[entry.path];
      if (sound != null && await entry.length() == sound.bytes) {
        present.add(sound.id);
      } else if (tidy) {
        await _tryDelete(entry);
      }
    }
    return present;
  }

  /// The bytes the downloaded sounds take on disk.
  Future<int> usedBytes() async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && !entry.path.endsWith(partSuffix)) {
        total += await entry.length();
      }
    }
    return total;
  }

  /// Removes every downloaded sound.
  Future<void> deleteAll() async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File) await _tryDelete(entry);
    }
  }

  Future<void> _tryDelete(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // Already gone, or in use; the next scan tidies it.
    }
  }
}

/// Downloads one sound of the pack and proves it is the pinned file.
class SoundPackDownloader {
  SoundPackDownloader({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;

  /// How long to wait for the connection, and for the next piece of data.
  final Duration timeout;

  static const userAgent =
      'Meditejo (personal meditation app; +https://github.com/beejsbj/meditejo)';

  /// Streams [sound] from [url] into [files], reporting `received, total`.
  /// Completes when the verified file is in place, and returns early without
  /// a file when [cancel] fires. Throws [SoundDownloadException].
  Future<void> download(
    SoundEntry sound,
    Uri url,
    SoundPackFiles files, {
    void Function(int received, int total)? onProgress,
    SoundDownloadCancel? cancel,
  }) async {
    if (!url.toString().startsWith(kReleaseDownloadPrefix)) {
      throw SoundDownloadException(
        SoundDownloadFailure.integrity,
        'Refusing $url: not a release download of this repository',
      );
    }
    final part = files.partFor(sound);
    IOSink? sink;
    try {
      await files.directory.create(recursive: true);
      final response = await _client
          .send(http.Request('GET', url)..headers['User-Agent'] = userAgent)
          .timeout(timeout);
      if (response.statusCode != 200) {
        await response.stream.drain<void>().catchError((_) {});
        throw SoundDownloadException(
          SoundDownloadFailure.server,
          'HTTP ${response.statusCode}',
        );
      }
      final total = sound.bytes;
      final output = AccumulatorSink<Digest>();
      final hash = sha256.startChunkedConversion(output);
      sink = part.openWrite();
      var received = 0;
      final done = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      subscription = response.stream
          .timeout(timeout)
          .listen(
            (chunk) {
              received += chunk.length;
              if (received > total) {
                subscription.cancel();
                done.completeError(
                  SoundDownloadException(
                    SoundDownloadFailure.integrity,
                    '${sound.id}: more than the pinned $total bytes',
                  ),
                );
                return;
              }
              hash.add(chunk);
              sink!.add(chunk);
              onProgress?.call(received, total);
            },
            onError: (Object error, StackTrace stack) {
              if (!done.isCompleted) done.completeError(error, stack);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      // A stalled connection would otherwise hold a cancel until it timed out.
      unawaited(
        cancel?.whenCancelled.then((_) {
          subscription.cancel();
          if (!done.isCompleted) done.complete();
        }),
      );
      await done.future;
      if (cancel?.isCancelled ?? false) {
        await _closeAndDiscard(sink, part);
        sink = null;
        return;
      }
      await sink.flush();
      await sink.close();
      sink = null;
      hash.close();
      if (received != total ||
          output.events.single.toString() != sound.sha256) {
        throw SoundDownloadException(
          SoundDownloadFailure.integrity,
          '${sound.id}: got $received bytes / ${output.events.single}, '
          'the library pins $total / ${sound.sha256}',
        );
      }
      await part.rename(files.fileFor(sound).path);
    } on SoundDownloadException {
      await _closeAndDiscard(sink, part);
      rethrow;
    } on FileSystemException catch (e) {
      await _closeAndDiscard(sink, part);
      throw SoundDownloadException(SoundDownloadFailure.storage, e.message);
    } on TimeoutException {
      await _closeAndDiscard(sink, part);
      throw const SoundDownloadException(
        SoundDownloadFailure.network,
        'Timed out',
      );
    } on http.ClientException catch (e) {
      await _closeAndDiscard(sink, part);
      throw SoundDownloadException(SoundDownloadFailure.network, e.message);
    } on SocketException catch (e) {
      await _closeAndDiscard(sink, part);
      throw SoundDownloadException(SoundDownloadFailure.network, e.message);
    } on HandshakeException catch (e) {
      await _closeAndDiscard(sink, part);
      throw SoundDownloadException(SoundDownloadFailure.network, e.message);
    }
  }

  Future<void> _closeAndDiscard(IOSink? sink, File part) async {
    try {
      await sink?.close();
    } on Object {
      // The file is being thrown away anyway.
    }
    await _discard(part);
  }

  Future<void> _discard(File part) async {
    try {
      if (await part.exists()) await part.delete();
    } on FileSystemException {
      // Tidied by the next scan.
    }
  }

  void close() => _client.close();
}

/// Collects what a chunked conversion emits (`package:crypto`'s digest
/// arrives as a single event on close).
class AccumulatorSink<T> implements Sink<T> {
  final events = <T>[];

  @override
  void add(T event) => events.add(event);

  @override
  void close() {}
}
