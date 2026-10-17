import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';

/// What came back from one request.
class FetchResult {
  const FetchResult({
    required this.status,
    required this.finalUri,
    this.headers = const {},
    this.bytes,
    this.truncated = false,
  });

  final int status;

  /// The address after redirects; relative links resolve against it.
  final Uri finalUri;

  /// Response headers, lower-cased.
  final Map<String, String> headers;

  /// The body, or null when it was not read (audio, or a 304).
  final Uint8List? bytes;

  /// The body was longer than the limit and was cut off.
  final bool truncated;

  String get contentType => (headers['content-type'] ?? '').toLowerCase();

  bool get ok => status >= 200 && status < 300;
  bool get notModified => status == 304;

  /// Whether the server says this is audio, so the body is not worth reading.
  bool get isAudio =>
      contentType.startsWith('audio/') ||
      contentType.startsWith('application/ogg');

  String? get etag => headers['etag'];
  String? get lastModified => headers['last-modified'];

  /// The body as text, honouring a declared Latin-1 charset.
  String get text {
    final data = bytes ?? Uint8List(0);
    final charset = RegExp(r'charset=([\w-]+)').firstMatch(contentType)?.group(1);
    if (charset == 'iso-8859-1' || charset == 'latin1' || charset == 'us-ascii') {
      return latin1.decode(data);
    }
    return utf8.decode(data, allowMalformed: true);
  }
}

/// A polite client for importing: one request per import, a clear
/// User-Agent, a timeout, and a cap on how much of a page it will read. It
/// follows redirects (the `http` package does, up to five) and never reads
/// the body of something that announces itself as audio.
class ImportHttp {
  ImportHttp({
    http.Client? client,
    this.userAgent = DharmaSeedClient.defaultUserAgent,
    this.timeout = const Duration(seconds: 20),
    this.maxBytes = 8 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String userAgent;
  final Duration timeout;
  final int maxBytes;

  void close() => _client.close();

  /// GET [uri], optionally conditional on validators from an earlier fetch.
  Future<FetchResult> get(
    Uri uri, {
    String? etag,
    String? lastModified,
    bool headersOnly = false,
  }) async {
    final request = http.Request('GET', uri)
      ..headers['User-Agent'] = userAgent
      ..headers['Accept'] =
          'application/rss+xml, application/atom+xml, application/xml;q=0.9, '
          'text/xml;q=0.9, audio/*;q=0.8, text/html;q=0.5, */*;q=0.1'
      ..headers['Accept-Encoding'] = 'gzip';
    if (etag != null && etag.isNotEmpty) request.headers['If-None-Match'] = etag;
    if (lastModified != null && lastModified.isNotEmpty) {
      request.headers['If-Modified-Since'] = lastModified;
    }
    final response = await _client.send(request).timeout(timeout);
    final headers = {
      for (final entry in response.headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final finalUri = response is http.BaseResponseWithUrl
        ? (response as http.BaseResponseWithUrl).url
        : (response.request?.url ?? uri);

    final type = (headers['content-type'] ?? '').toLowerCase();
    final audio = type.startsWith('audio/') || type.startsWith('application/ogg');
    if (response.statusCode == 304 || headersOnly || audio) {
      // Not read: stop the transfer rather than download an audio file.
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      return FetchResult(status: response.statusCode, finalUri: finalUri, headers: headers);
    }

    final builder = BytesBuilder(copy: false);
    var truncated = false;
    final done = Completer<void>();
    late StreamSubscription<List<int>> subscription;
    subscription = response.stream.listen(
      (chunk) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          truncated = true;
          subscription.cancel();
          if (!done.isCompleted) done.complete();
        }
      },
      onError: (Object e, StackTrace st) {
        if (!done.isCompleted) done.completeError(e, st);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future.timeout(timeout, onTimeout: () {
      subscription.cancel();
      throw TimeoutException('Reading $uri took too long');
    });
    return FetchResult(
      status: response.statusCode,
      finalUri: finalUri,
      headers: headers,
      bytes: builder.takeBytes(),
      truncated: truncated,
    );
  }
}
