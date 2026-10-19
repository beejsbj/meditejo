/// Stable IDs shared by the library, downloads, favourites and completion.
String ytVideoId(String videoId) => 'yt-video-$videoId';
String ytPlaylistId(String playlistId) => 'yt-playlist-$playlistId';
String ytSingleCourseId(String videoId) => ytPlaylistId('single-$videoId');

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
