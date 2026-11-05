/// Stable IDs shared by the library, downloads, pins and completion.
String ytVideoId(String videoId) => 'yt-video-$videoId';
String ytPlaylistId(String playlistId) => 'yt-playlist-$playlistId';
String ytSingleCourseId(String videoId) => ytPlaylistId('single-$videoId');

/// A channel as a teacher: `yt-channel-<key>`, the key from
/// [youtubeChannelKey].
const ytChannelPrefix = 'yt-channel-';
String ytChannelId(String key) => '$ytChannelPrefix$key';
bool isYtChannelId(String id) => id.startsWith(ytChannelPrefix);
String ytChannelKeyOf(String id) => id.substring(ytChannelPrefix.length);

final _channelId = RegExp(r'^UC[A-Za-z0-9_-]{10,}$');
final _channelHandle = RegExp(r'^@[A-Za-z0-9._-]{1,100}$');

/// A channel page's stable key: its `UC…` id, or its `@handle` when the link
/// gives only that. Null for anything else, including an empty or foreign
/// link, so a video with no known channel has no teacher.
String? youtubeChannelKey(String? url) {
  if (url == null || url.isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  if (host != 'youtube.com' && host != 'music.youtube.com') return null;
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2 &&
      parts.first == 'channel' &&
      _channelId.hasMatch(parts[1])) {
    return parts[1];
  }
  if (parts.isNotEmpty && _channelHandle.hasMatch(parts.first)) {
    return parts.first;
  }
  return null;
}

final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _playlistId = RegExp(r'^[A-Za-z0-9_-]+$');

class YoutubeLink {
  const YoutubeLink({this.videoId, this.playlistId});
  final String? videoId;
  final String? playlistId;

  String get videoUrl => 'https://www.youtube.com/watch?v=$videoId';
  String get playlistUrl => 'https://www.youtube.com/playlist?list=$playlistId';
}

/// Accept only real YouTube hosts and supported page shapes; incidental
/// `list` parameters on unrelated sites never turn them into YouTube links.
YoutubeLink? parseYoutubeLink(Uri uri) {
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');
  if (!{
    'youtube.com',
    'youtu.be',
    'music.youtube.com',
    'youtube-nocookie.com',
  }.contains(host)) {
    return null;
  }
  final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  String? video;
  if (host == 'youtu.be' && parts.length == 1) {
    video = parts.first;
  } else if (uri.path == '/watch') {
    video = uri.queryParameters['v'];
  } else if (parts.length == 2 &&
      {'shorts', 'live', 'embed'}.contains(parts.first)) {
    video = parts[1];
  }
  if (video != null && !_videoId.hasMatch(video)) video = null;
  final list = uri.queryParameters['list'];
  final playlist =
      list != null &&
          _playlistId.hasMatch(list) &&
          (video != null || uri.path == '/playlist')
      ? list
      : null;
  return video == null && playlist == null
      ? null
      : YoutubeLink(videoId: video, playlistId: playlist);
}
