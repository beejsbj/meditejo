import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:medito/services/library/import_models.dart';
import 'package:medito/utils/logger.dart';

/// What another app shared with Meditejo: a link as text, or audio files
/// (already copied into the app's cache, since the sender's permission to
/// read them ends with the share).
@immutable
class SharedPayload {
  const SharedPayload({this.text, this.files = const []});

  factory SharedPayload.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const SharedPayload();
    final text = map['text'];
    final files = map['files'];
    return SharedPayload(
      text: text is String && text.trim().isNotEmpty ? text.trim() : null,
      files: [
        if (files is List)
          for (final file in files)
            if (file is Map && file['path'] is String)
              PickedFile(
                path: file['path'] as String,
                name: file['name'] as String?,
                mimeType: file['mimeType'] as String?,
                sizeBytes: (file['size'] as num?)?.toInt(),
              ),
      ],
    );
  }

  final String? text;
  final List<PickedFile> files;

  bool get isEmpty => (text == null || text!.isEmpty) && files.isEmpty;
}

/// The Android share target: "Share → Meditejo" from a browser, a podcast app
/// or a file manager.
abstract interface class ShareIntake {
  /// What the app was started with, once; null if it was started normally.
  Future<SharedPayload?> initial();

  /// Shares that arrive while the app is open.
  Stream<SharedPayload> get shares;
}

/// Talks to `MainActivity`, which owns the Android intents.
class PlatformShareIntake implements ShareIntake {
  PlatformShareIntake() {
    _channel.setMethodCallHandler(_onCall);
  }

  static const _channel = MethodChannel('meditejo/share');
  final _controller = StreamController<SharedPayload>.broadcast();

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'onShare') return;
    final payload = SharedPayload.fromMap(
      call.arguments as Map<Object?, Object?>?,
    );
    if (!payload.isEmpty) _controller.add(payload);
  }

  @override
  Future<SharedPayload?> initial() async {
    // Only Android has the share target; elsewhere nothing answers.
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'getInitial',
      );
      final payload = SharedPayload.fromMap(map);
      return payload.isEmpty ? null : payload;
    } on MissingPluginException {
      return null;
    } catch (e) {
      AppLogger.w('SHARE', 'Could not read the share that started the app: $e');
      return null;
    }
  }

  @override
  Stream<SharedPayload> get shares => _controller.stream;
}
