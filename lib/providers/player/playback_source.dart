import 'package:medito/models/player/playback_request.dart';
import 'package:medito/models/track/track.dart';

/// Where a session plays from. A downloaded file comes first and nothing is
/// looked up for it, so a downloaded YouTube video opens offline, rate-limited
/// or with the extractor stuck. Only a YouTube video that is not downloaded
/// asks [resolve] for a fresh stream, immediately before using it. Anything
/// else plays from the address its request carries.
Future<String> playbackSource(
  PlaybackRequest request, {
  required String? downloadPath,
  required Future<Track> Function(String trackId) resolve,
}) async {
  if (downloadPath != null) return downloadPath;
  if (request.trackId.startsWith('yt-video-')) {
    final fresh = await resolve(request.trackId);
    return fresh.voices.single.audioFiles.single.path;
  }
  return request.remoteUrl;
}
