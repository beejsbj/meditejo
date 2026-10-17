import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:medito/models/player/playback_request.dart';
import 'package:medito/providers/library/library_providers.dart';
import 'package:medito/utils/logger.dart';

/// [request] set to start where the user left off, when they left it
/// partway. The saved place is only a convenience, so any failure to read it
/// just starts from the beginning.
Future<PlaybackRequest> withResumePosition(
  WidgetRef ref,
  PlaybackRequest request,
) async {
  try {
    final point = await ref
        .read(libraryStoreProvider)
        .resumePoint(request.trackId);
    if (point == null) return request;
    return request.copyWith(startPositionMs: point.positionMs);
  } catch (e) {
    AppLogger.w('LIBRARY', 'Could not read the saved position: $e');
    return request;
  }
}
