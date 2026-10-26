import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/utils/logger.dart';

/// How far copying a picked folder has got, for the progress line.
@immutable
class FolderProgress {
  const FolderProgress({
    required this.filesDone,
    required this.filesTotal,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.name = '',
  });

  factory FolderProgress.fromMap(Map<Object?, Object?> map) => FolderProgress(
    filesDone: (map['filesDone'] as num?)?.toInt() ?? 0,
    filesTotal: (map['filesTotal'] as num?)?.toInt() ?? 0,
    bytesDone: (map['bytesDone'] as num?)?.toInt() ?? 0,
    bytesTotal: (map['bytesTotal'] as num?)?.toInt() ?? 0,
    name: map['name'] as String? ?? '',
  );

  final int filesDone;
  final int filesTotal;
  final int bytesDone;
  final int bytesTotal;

  /// The file being copied.
  final String name;

  /// 0..1 by bytes when sizes are known, otherwise by files; null when
  /// nothing is known yet.
  double? get fraction {
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    if (filesTotal > 0) return (filesDone / filesTotal).clamp(0.0, 1.0);
    return null;
  }
}

/// Folder import: the user picks a folder, its audio (subfolders included)
/// is copied into the app's cache, and the files come back as an ordinary
/// [PickedFolder] for the usual preview. Returns null when the user backs out
/// or cancels; failures are [ImportFailure]s.
abstract interface class FolderImporter {
  Future<PickedFolder?> importFolder({
    void Function(FolderProgress)? onProgress,
  });

  /// Stops a pick, scan or copy in progress; it then ends as a cancel.
  Future<void> cancel();

  /// Removes whatever a folder import left in the cache.
  Future<void> discard();
}

/// The Android implementation, over `meditejo/folder` (`FolderImportBridge`).
///
/// Since Android 11 an app cannot list a folder by path, so the folder is
/// granted through the system picker (the Storage Access Framework) and read
/// by the native side, which copies the audio off the main thread and reports
/// progress. The permission is temporary and never kept.
class ChannelFolderImporter implements FolderImporter {
  ChannelFolderImporter({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_onCall);
  }

  static const channelName = 'meditejo/folder';

  final MethodChannel _channel;
  void Function(FolderProgress)? _onProgress;

  Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'progress' && call.arguments is Map) {
      _onProgress?.call(
        FolderProgress.fromMap(call.arguments as Map<Object?, Object?>),
      );
    }
    return null;
  }

  @override
  Future<PickedFolder?> importFolder({
    void Function(FolderProgress)? onProgress,
  }) async {
    _onProgress = onProgress;
    try {
      final picked = await _channel.invokeMapMethod<String, Object?>('pick');
      if (picked == null) return null;
      final name = picked['name'] as String? ?? '';

      final scan = await _channel.invokeMapMethod<String, Object?>('scan');
      final audioCount = (scan?['audioCount'] as num?)?.toInt() ?? 0;
      final totalBytes = (scan?['totalBytes'] as num?)?.toInt() ?? 0;
      final entriesSeen = (scan?['entriesSeen'] as num?)?.toInt() ?? 0;
      final unreadableFolders =
          (scan?['unreadableFolders'] as num?)?.toInt() ?? 0;
      if (scan?['truncated'] == true) {
        throw const ImportFailure(ImportFailureReason.folderTooLarge);
      }
      if (audioCount == 0) {
        throw ImportFailure(
          entriesSeen > 0
              ? ImportFailureReason.noAudioFiles
              : unreadableFolders > 0
              ? ImportFailureReason.folderUnreadable
              : ImportFailureReason.folderEmpty,
          name,
        );
      }

      onProgress?.call(
        FolderProgress(
          filesDone: 0,
          filesTotal: audioCount,
          bytesTotal: totalBytes,
        ),
      );
      final copy = await _channel.invokeMapMethod<String, Object?>('copy');
      final files = [
        for (final file in (copy?['files'] as List<Object?>? ?? const []))
          if (file is Map && file['path'] is String)
            PickedFile(
              path: file['path'] as String,
              name: file['name'] as String?,
              mimeType: file['mimeType'] as String?,
              sizeBytes: (file['size'] as num?)?.toInt(),
            ),
      ];
      final skipped = (copy?['skipped'] as List<Object?>? ?? const []).length;
      if (files.isEmpty) {
        throw ImportFailure(ImportFailureReason.folderUnreadable, name);
      }
      return PickedFolder.copied(
        name: name,
        files: files,
        unreadable: skipped + unreadableFolders,
      );
    } on PlatformException catch (e) {
      final reason = switch (e.code) {
        'cancelled' => null,
        'no_space' => ImportFailureReason.folderNoSpace,
        'no_picker' => ImportFailureReason.folderUnavailable,
        _ => ImportFailureReason.folderUnreadable,
      };
      if (reason == null) return null;
      AppLogger.d('LIBRARY', 'Folder import failed: ${e.code} ${e.message}');
      throw ImportFailure(reason, e.message);
    } finally {
      _onProgress = null;
    }
  }

  @override
  Future<void> cancel() => _quietly('cancel');

  @override
  Future<void> discard() => _quietly('discard');

  Future<void> _quietly(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      AppLogger.d('LIBRARY', 'Folder $method failed: ${e.code}');
    } on MissingPluginException {
      // Not Android, or an engine without the bridge: nothing to stop.
    }
  }
}
