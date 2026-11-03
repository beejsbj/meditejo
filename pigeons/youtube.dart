import 'package:pigeon/pigeon.dart';

// Generate with:
//   dart run pigeon --input pigeons/youtube.dart --package_name=medito
//
// The Kotlin output shares a package with AudioPigeon.g.kt, so its error class
// gets its own name; two generated files cannot both declare `FlutterError`.
@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/youtube_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/app/src/main/kotlin/meditofoundation/medito/pigeon/YoutubeApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'meditofoundation.medito.pigeon',
      errorClassName: 'YoutubeFlutterError',
    ),
  ),
)
// A video and what a player or library needs to show it. Unknown strings are
// empty and an unknown duration is 0.
//
// New fields go last and are nullable, so older callers still line up:
// [channelUrl] is the uploader's channel page and [channelAvatar] its
// picture, null or empty when unknown.
class YoutubeVideo {
  YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.uploader,
    required this.durationSeconds,
    required this.thumbnail,
    required this.description,
    this.channelUrl,
    this.channelAvatar,
  });

  String videoId;
  String title;
  String uploader;
  int durationSeconds;
  String thumbnail;
  String description;
  String? channelUrl;
  String? channelAvatar;
}

/// A playlist row. [uploader] is the channel that made this video, which is
/// not the playlist's own owner; empty when the extractor does not say.
/// [channelUrl] is that channel's page, null or empty when unknown.
class YoutubePlaylistItem {
  YoutubePlaylistItem({
    required this.videoId,
    required this.title,
    required this.uploader,
    required this.durationSeconds,
    required this.thumbnail,
    this.channelUrl,
  });

  String videoId;
  String title;
  String uploader;
  int durationSeconds;
  String thumbnail;
  String? channelUrl;
}

/// A whole playlist, every page of it, in playlist order. [description] is
/// the playlist's own text; [channelUrl] and [channelAvatar] are its owner's
/// channel page and picture. Each is null or empty when unknown.
class YoutubePlaylist {
  YoutubePlaylist({
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.items,
    this.description,
    this.channelUrl,
    this.channelAvatar,
  });

  String title;
  String uploader;
  String thumbnail;
  List<YoutubePlaylistItem> items;
  String? description;
  String? channelUrl;
  String? channelAvatar;
}

/// A channel's own page: its name, picture and "About" text. Unknown strings
/// are empty.
class YoutubeChannel {
  YoutubeChannel({
    required this.url,
    required this.name,
    required this.avatar,
    required this.description,
  });

  String url;
  String name;
  String avatar;
  String description;
}

/// The best audio-only stream for a video: an https URL that is only valid for
/// a while. [bitrate] is bits per second. [expiresAt] is epoch milliseconds,
/// or null when the URL does not say when it stops working.
class YoutubeAudioStream {
  YoutubeAudioStream({
    required this.url,
    required this.mimeType,
    required this.bitrate,
    this.expiresAt,
  });

  String url;
  String mimeType;
  int bitrate;
  int? expiresAt;
}

/// Resolves YouTube links through NewPipeExtractor on Android.
///
/// Every call can fail with a PlatformException whose code is one of
/// `unavailable`, `age-restricted`, `private` or `network`, and whose message
/// is short and safe to show.
@HostApi()
abstract class YoutubeExtractorApi {
  @async
  YoutubePlaylist resolvePlaylist(String url);

  @async
  YoutubeVideo resolveVideo(String urlOrId);

  @async
  YoutubeAudioStream resolveAudioStream(String videoId);

  /// [url] is a channel page, as a video or a playlist reported it.
  @async
  YoutubeChannel resolveChannel(String url);
}
