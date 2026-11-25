import 'dart:convert';
import 'dart:io';

import 'package:medito/models/pauses/media_spans.dart';
import 'package:medito/utils/logger.dart';

/// Keeps what was found in each recording, one small JSON file per recording,
/// so a recording is read once. Anything unreadable is simply absent.
class PauseMapStore {
  PauseMapStore(this._directory);

  final Future<Directory> Function() _directory;

  /// Most recordings kept; the oldest go first.
  static const maxEntries = 300;

  Future<File> _file(String key) async {
    final dir = await _directory();
    var name = Uri.encodeComponent(key).replaceAll('%', '~');
    if (name.length > 150) name = '${name.substring(0, 120)}-${key.hashCode}';
    return File('${dir.path}/$name.json');
  }

  Future<MediaSpanMap?> read(String key) async {
    try {
      final file = await _file(key);
      if (!await file.exists()) return null;
      return MediaSpanMap.tryFromJson(jsonDecode(await file.readAsString()));
    } catch (e) {
      AppLogger.w('PAUSES', 'Unreadable pause map for $key: $e');
      return null;
    }
  }

  Future<void> write(String key, MediaSpanMap map) async {
    try {
      final file = await _file(key);
      await file.parent.create(recursive: true);
      // Written whole, then moved into place, so a crash leaves no half file.
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(map.toJson()), flush: true);
      await temp.rename(file.path);
      await _prune(file.parent);
    } catch (e) {
      AppLogger.w('PAUSES', 'Could not keep the pause map for $key: $e');
    }
  }

  Future<void> _prune(Directory dir) async {
    final files = <File, DateTime>{};
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        files[entity] = (await entity.stat()).modified;
      }
    }
    if (files.length <= maxEntries) return;
    final oldest = files.keys.toList()
      ..sort((a, b) => files[a]!.compareTo(files[b]!));
    for (final file in oldest.take(files.length - maxEntries)) {
      await file.delete();
    }
  }
}
