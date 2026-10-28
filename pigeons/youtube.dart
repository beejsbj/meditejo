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
class YoutubeVideo {
  YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.uploader,
    required this.durationSeconds,
    required this.thumbnail,
    required this.description,
  });

  String videoId;
  String title;
  String uploader;
  int durationSeconds;
  String thumbnail;
  String description;
}

/// A playlist row. [uploader] is the channel that made this video, which is
/// not the playlist's own owner; empty when the extractor does not say.
class YoutubePlaylistItem {
  YoutubePlaylistItem({
    required this.videoId,
    required this.title,
    required this.uploader,
    required this.durationSeconds,
    required this.thumbnail,
  });

  String videoId;
  String title;
  String uploader;
  int durationSeconds;
  String thumbnail;
}

/// A whole playlist, every page of it, in playlist order.
class YoutubePlaylist {
  YoutubePlaylist({
    required this.title,
    required this.uploader,
    required this.thumbnail,
    required this.items,
  });

  String title;
  String uploader;
  String thumbnail;
  List<YoutubePlaylistItem> items;
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
}
