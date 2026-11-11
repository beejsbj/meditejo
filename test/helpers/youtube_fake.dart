import 'dart:async';

import 'package:flutter/services.dart';
import 'package:medito/src/youtube_api.g.dart';

const videoA = 'aaaaaaaaaaa';
const videoB = 'bbbbbbbbbbb';
const videoC = 'ccccccccccc';
const playlistOne = 'PLone';
const playlistTwo = 'PLtwo';

/// A channel page as the extractor reports it, for [key] (`UC…`).
String channelUrl(String key) => 'https://www.youtube.com/channel/$key';

YoutubeVideo video(
  String id, {
  String title = 'A quiet sit',
  String uploader = 'Quiet Channel',
  int seconds = 600,
  String description = 'Sit with it.',
  String? channel,
  String? avatar,
}) => YoutubeVideo(
  videoId: id,
  title: title,
  uploader: uploader,
  durationSeconds: seconds,
  thumbnail: '',
  description: description,
  channelUrl: channel == null ? null : channelUrl(channel),
  channelAvatar: avatar,
);

/// [uploader] empty is the extractor saying nothing about the channel.
YoutubePlaylistItem item(
  String id, {
  String? title,
  int seconds = 600,
  String uploader = '',
  String? channel,
}) => YoutubePlaylistItem(
  videoId: id,
  title: title ?? 'Item $id',
  uploader: uploader,
  durationSeconds: seconds,
  thumbnail: '',
  channelUrl: channel == null ? null : channelUrl(channel),
);

YoutubePlaylist playlist(
  List<YoutubePlaylistItem> items, {
  String title = 'Evening Sits',
  String uploader = 'Quiet Channel',
  String? description,
  String? channel,
  String? avatar,
}) => YoutubePlaylist(
  title: title,
  uploader: uploader,
  thumbnail: '',
  items: items,
  description: description,
  channelUrl: channel == null ? null : channelUrl(channel),
  channelAvatar: avatar,
);

/// A stream address that is plainly signed and short-lived.
YoutubeAudioStream stream(
  String id, {
  int? expiresAt,
  String mime = 'audio/webm',
  String? url,
}) => YoutubeAudioStream(
  url: url ?? 'https://rr1.googlevideo.com/audio/$id?sig=SECRET-$id',
  mimeType: mime,
  bitrate: 128000,
  expiresAt: expiresAt,
);

/// A scripted extractor: answers come from the maps, every call is recorded,
/// and nothing touches a platform channel.
class FakeYoutubeApi extends YoutubeExtractorApi {
  final Map<String, YoutubeVideo> videos = {};
  final Map<String, YoutubePlaylist> playlists = {};
  final Map<String, YoutubeAudioStream> streams = {};

  /// Channel pages by key (`UC…`).
  final Map<String, YoutubeChannel> channels = {};

  /// Thrown by every call when set.
  Object? failure;

  /// Thrown when resolving these videos, by id.
  final Map<String, Object> videoFailures = {};

  /// When set, audio resolution waits on this before answering.
  Completer<void>? audioGate;

  /// When set, playlist resolution waits on this before answering.
  Completer<void>? playlistGate;

  final List<String> videoCalls = [];
  final List<String> playlistCalls = [];
  final List<String> audioCalls = [];
  final List<String> channelCalls = [];

  /// When set, video resolution waits on this before answering.
  Completer<void>? videoGate;

  /// When set, channel resolution waits on this before answering.
  Completer<void>? channelGate;

  @override
  Future<YoutubeVideo> resolveVideo(String urlOrId) async {
    videoCalls.add(urlOrId);
    await videoGate?.future;
    if (failure case final error?) throw error;
    final id = urlOrId.contains('v=') ? urlOrId.split('v=').last : urlOrId;
    if (videoFailures[id] case final error?) throw error;
    return videos[id] ?? (throw PlatformException(code: 'unavailable'));
  }

  @override
  Future<YoutubePlaylist> resolvePlaylist(String url) async {
    playlistCalls.add(url);
    await playlistGate?.future;
    if (failure case final error?) throw error;
    final id = url.split('list=').last;
    return playlists[id] ?? (throw PlatformException(code: 'unavailable'));
  }

  @override
  Future<YoutubeAudioStream> resolveAudioStream(String videoId) async {
    audioCalls.add(videoId);
    await audioGate?.future;
    if (failure case final error?) throw error;
    return streams[videoId] ?? (throw PlatformException(code: 'unavailable'));
  }

  @override
  Future<YoutubeChannel> resolveChannel(String url) async {
    channelCalls.add(url);
    await channelGate?.future;
    if (failure case final error?) throw error;
    final key = url.split('/').last;
    return channels[key] ?? (throw PlatformException(code: 'unavailable'));
  }
}

/// A clock the test moves by hand.
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 18, 9);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}
