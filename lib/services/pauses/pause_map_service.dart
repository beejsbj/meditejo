import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/pauses/media_spans.dart';
import 'package:medito/models/pauses/pause_hold.dart';
import 'package:medito/services/pauses/pause_distribution.dart';
import 'package:medito/services/pauses/pause_map_store.dart';
import 'package:medito/utils/logger.dart';
import 'package:path_provider/path_provider.dart';

final pauseMapServiceProvider = Provider<PauseMapService>((ref) {
  return PauseMapService(
    PauseMapStore(() async {
      final base = await getApplicationSupportDirectory();
      return Directory('${base.path}/media_spans');
    }),
  );
});

/// Where a recording is quiet, found once on the device (Android only) and
/// kept. The reading itself is native (`meditejo/pauses`); this is the cache,
/// the policy for when to read, and the plan for Extend that follows from it.
class PauseMapService {
  PauseMapService(this._store, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('meditejo/pauses');

  final PauseMapStore _store;
  final MethodChannel _channel;

  final _running = <String, Future<MediaSpanMap?>>{};

  /// Recordings that could not be read this run (a metered connection, a
  /// format the phone cannot decode): not tried again until the app restarts.
  final _unreadable = <String>{};

  /// The key one recording is kept under.
  static String keyFor(String trackId, String fileId) => '$trackId|$fileId';

  /// Whether a recording can be read for pauses at all. A YouTube stream
  /// carries a music bed and a URL that expires, so it never is.
  static bool canAnalyse(String trackId, String source) =>
      source.isNotEmpty && !trackId.startsWith('yt-');

  /// A source's stated length can be rounded (Dharma Seed gives minutes), so
  /// only a clearly different length means a different file.
  static const durationTolerance = Duration(seconds: 90);

  /// What was found before, if the recording is still the same length.
  Future<MediaSpanMap?> cached(String key, {int? durationMs}) async {
    final map = await _store.read(key);
    if (map == null) return null;
    if (durationMs != null &&
        durationMs > 0 &&
        (map.durationMs - durationMs).abs() >
            durationTolerance.inMilliseconds) {
      return null;
    }
    return map;
  }

  /// Reads the recording at [source] (a path or URI on the phone, or a URL
  /// that is only fetched on an unmetered connection) and keeps the result.
  /// Null when it could not be read. Several callers for one recording share
  /// one reading.
  Future<MediaSpanMap?> analyse(String key, String source) {
    if (_unreadable.contains(key)) return Future.value(null);
    return _running[key] ??= _read(key, source).whenComplete(() {
      _running.remove(key);
    });
  }

  Future<MediaSpanMap?> _read(String key, String source) async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'analyze',
        {'source': source},
      );
      final duration = (result?['durationMs'] as num?)?.toInt() ?? 0;
      if (result == null || duration <= 0) return null;
      final spans = [
        for (final raw in (result['spans'] as List?) ?? const [])
          if (raw is Map) ?MediaSpan.tryFromJson({...raw, 'kind': 'silence'}),
      ];
      final map = MediaSpanMap(durationMs: duration, spans: spans);
      await _store.write(key, map);
      return map;
    } on PlatformException catch (e) {
      if (e.code != 'CANCELLED') _unreadable.add(key);
      AppLogger.d('PAUSES', 'No pause map for $key: ${e.code}');
      return null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      _unreadable.add(key);
      AppLogger.w('PAUSES', 'Pause map failed for $key: $e');
      return null;
    }
  }

  /// Stops the reading under way. The player does not call it when a session
  /// ends: a read that finishes is cached for the next one.
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (_) {}
  }

  /// Where [extendMinutes] go for the recording in [map]: holds in its pauses,
  /// the rest after it. Without a map, none: everything at the end.
  static List<PauseHold> holdsFor(MediaSpanMap? map, int extendMinutes) {
    if (map == null || extendMinutes <= 0) return const [];
    return distributeExtension(
      totalMs: extendMinutes * 60000,
      pauses: usablePauses(map),
    ).holds;
  }
}
