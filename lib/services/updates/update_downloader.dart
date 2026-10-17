import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:medito/services/updates/update_failure.dart';
import 'package:medito/services/updates/update_release.dart';

/// Lower-case hex SHA-256 of [file], streamed.
Future<String> sha256OfFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Whether [actual] is the published digest. Case and surrounding space are
/// ignored; anything that is not a full digest never matches.
bool sha256Matches(String actual, String expected) {
  final a = actual.trim().toLowerCase();
  final b = expected.trim().toLowerCase();
  return a.length == 64 && a == b;
}

/// Downloads the release APK into [directory] and keeps only files whose
/// SHA-256 matched the published one.
///
/// A download is written to `<name>.part` and renamed once verified, so a file
/// named `meditejo-<code>.apk` has already passed the hash check.
class UpdateDownloader {
  UpdateDownloader({
    required this.directory,
    http.Client? httpClient,
    this.idleTimeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  final Future<Directory> Function() directory;
  final http.Client _http;
  final Duration idleTimeout;

  static final _apkFile = RegExp(r'^meditejo-(\d+)\.apk$');

  Future<File> _target(UpdateRelease release) async {
    final dir = await directory();
    await dir.create(recursive: true);
    return File('${dir.path}/meditejo-${release.versionCode}.apk');
  }

  /// A previously downloaded APK for [release], if it is whole and still
  /// matches the published hash.
  Future<File?> verifiedExisting(UpdateRelease release) async {
    final file = await _target(release);
    if (!await file.exists() || await file.length() != release.size) return null;
    return sha256Matches(await sha256OfFile(file), release.sha256) ? file : null;
  }

  /// Fetches the APK, reporting progress from 0 to 1. Throws
  /// [UpdateException] (`offline`, `downloadFailed` or `hashMismatch`) and
  /// leaves no unverified file behind.
  Future<File> download(
    UpdateRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final existing = await verifiedExisting(release);
    if (existing != null) {
      onProgress?.call(1);
      return existing;
    }

    final target = await _target(release);
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(release.apkUrl))
        ..headers['User-Agent'] = 'Meditejo';
      final response = await _http.send(request).timeout(idleTimeout);
      if (response.statusCode != 200) {
        throw UpdateException(
          response.statusCode == 429
              ? UpdateFailure.rateLimited
              : UpdateFailure.downloadFailed,
          'HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength ?? release.size;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response.stream.timeout(idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received != release.size) {
        throw UpdateException(
          UpdateFailure.downloadFailed,
          'Received $received of ${release.size} bytes',
        );
      }
      if (!sha256Matches(await sha256OfFile(part), release.sha256)) {
        throw const UpdateException(UpdateFailure.hashMismatch);
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      return target;
    } on UpdateException {
      await _discard(part, sink);
      rethrow;
    } on TimeoutException {
      await _discard(part, sink);
      throw const UpdateException(UpdateFailure.downloadFailed, 'Timed out');
    } on SocketException catch (e) {
      await _discard(part, sink);
      throw UpdateException(UpdateFailure.offline, e.message);
    } on http.ClientException catch (e) {
      await _discard(part, sink);
      throw UpdateException(UpdateFailure.offline, e.message);
    } on FileSystemException catch (e) {
      await _discard(part, sink);
      throw UpdateException(UpdateFailure.downloadFailed, e.message);
    }
  }

  Future<void> _discard(File part, IOSink? sink) async {
    try {
      await sink?.close();
    } catch (_) {}
    if (await part.exists()) await part.delete();
  }

  /// Removes interrupted downloads and every APK that is not newer than the
  /// installed build, i.e. the one that just installed itself.
  Future<void> deleteStale({required int installedVersionCode}) async {
    final dir = await directory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final code = int.tryParse(_apkFile.firstMatch(name)?.group(1) ?? '');
      if (name.endsWith('.part') ||
          (code != null && code <= installedVersionCode)) {
        await entity.delete();
      }
    }
  }

  Future<void> delete(UpdateRelease release) async {
    final file = await _target(release);
    if (await file.exists()) await file.delete();
  }

  void close() => _http.close();
}
