import 'package:flutter_test/flutter_test.dart';
import 'package:medito/services/youtube/youtube_ids.dart';

import '../../helpers/youtube_fake.dart';

YoutubeLink? parse(String url) => parseYoutubeLink(Uri.parse(url));

void main() {
  group('stable IDs', () {
    test('videos, playlists and single-video courses are namespaced', () {
      expect(ytVideoId(videoA), 'yt-video-$videoA');
      expect(ytPlaylistId(playlistOne), 'yt-playlist-PLone');
      expect(ytSingleCourseId(videoA), 'yt-playlist-single-$videoA');
    });
  });

  group('link shapes', () {
    final watch = 'https://www.youtube.com/watch?v=$videoA';

    for (final url in [
      watch,
      'https://youtube.com/watch?v=$videoA',
      'https://m.youtube.com/watch?v=$videoA',
      'https://music.youtube.com/watch?v=$videoA',
      'https://youtu.be/$videoA',
      'https://youtu.be/$videoA?si=share',
      'https://www.youtube.com/shorts/$videoA',
      'https://www.youtube.com/live/$videoA',
      'https://www.youtube.com/embed/$videoA',
      'https://www.youtube-nocookie.com/embed/$videoA',
      '$watch&t=90s',
    ]) {
      test('$url is the video, with no playlist', () {
        final link = parse(url)!;
        expect(link.videoId, videoA);
        expect(link.playlistId, isNull);
        expect(link.videoUrl, watch);
      });
    }

    test('a watch link with a list carries both', () {
      final link = parse('$watch&list=$playlistOne&index=3')!;
      expect(link.videoId, videoA);
      expect(link.playlistId, playlistOne);
      expect(link.playlistUrl, 'https://www.youtube.com/playlist?list=PLone');
    });

    test('a short link with a list carries both', () {
      final link = parse('https://youtu.be/$videoA?list=$playlistOne')!;
      expect(link.videoId, videoA);
      expect(link.playlistId, playlistOne);
    });

    test('a playlist page is the playlist alone', () {
      final link = parse('https://www.youtube.com/playlist?list=$playlistOne')!;
      expect(link.videoId, isNull);
      expect(link.playlistId, playlistOne);
    });

    for (final url in [
      // Not YouTube hosts, even with YouTube-shaped parameters.
      'https://example.org/watch?v=$videoA',
      'https://example.org/page?list=$playlistOne',
      'https://notyoutube.com/watch?v=$videoA',
      'https://youtube.com.evil.example/watch?v=$videoA',
      // YouTube pages that are neither a video nor a playlist.
      'https://www.youtube.com/',
      'https://www.youtube.com/@quietchannel',
      'https://www.youtube.com/results?search_query=sit',
      'https://www.youtube.com/channel/UC123',
      // A list parameter alone on a watch page names nothing.
      'https://www.youtube.com/watch?list=$playlistOne',
      // Malformed video IDs.
      'https://www.youtube.com/watch?v=abc',
      'https://youtu.be/abc',
      'https://www.youtube.com/shorts/too-long-to-be-an-id',
      'https://www.youtube.com/watch?v=abc&list=$playlistOne',
    ]) {
      test('$url is not a YouTube link', () => expect(parse(url), isNull));
    }
  });
}
