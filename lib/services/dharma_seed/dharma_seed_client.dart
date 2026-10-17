import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Dharma Seed's unofficial API, the one its own Android app uses.
///
/// Every call is `POST https://www.dharmaseed.org/api/1/<kind>/` with a
/// multipart form. `detail=0` lists IDs (`{edition, items, x_items}`); pass
/// `edition` back to list only what changed since. `detail=1&items=<ids>`
/// returns full records keyed by ID. `x_items` are IDs that were removed or
/// hidden. There is no search endpoint.
///
/// This client makes one request at a time and retries transient failures
/// with backoff. Pacing between requests belongs to the sync service.
class DharmaSeedClient {
  DharmaSeedClient({
    http.Client? httpClient,
    Uri? baseUri,
    this.userAgent = defaultUserAgent,
    this.maxAttempts = 4,
    this.timeout = const Duration(seconds: 45),
    Duration Function(int attempt)? backoff,
    Future<void> Function(Duration)? sleep,
  }) : _http = httpClient ?? http.Client(),
       baseUri = baseUri ?? Uri.parse('https://www.dharmaseed.org/api/1/'),
       _backoff = backoff ?? _defaultBackoff,
       _sleep = sleep ?? Future<void>.delayed;

  static const defaultUserAgent =
      'Meditejo (personal meditation app; '
      '+https://github.com/beejsbj/meditejo)';

  final http.Client _http;
  final Uri baseUri;
  final String userAgent;
  final int maxAttempts;
  final Duration timeout;
  final Duration Function(int attempt) _backoff;
  final Future<void> Function(Duration) _sleep;

  static Duration _defaultBackoff(int attempt) =>
      Duration(seconds: 2 << (attempt - 1)); // 2, 4, 8 s

  /// IDs of every record of [kind], or of those changed since [edition].
  Future<DsIdList> fetchIds(DsKind kind, {String? edition}) async {
    final json = await _post(kind, {
      'detail': '0',
      'edition': ?edition,
    });
    return DsIdList(
      edition: json['edition'] as String? ?? '',
      items: _ids(json['items']),
      removed: _ids(json['x_items']),
    );
  }

  /// Full records for [ids]. Requested IDs that come back in `x_items`, or
  /// not at all, are gone from Dharma Seed.
  Future<DsDetails> fetchDetails(DsKind kind, List<int> ids) async {
    if (ids.isEmpty) return const DsDetails(edition: '', records: {});
    final json = await _post(kind, {'detail': '1', 'items': ids.join(',')});
    final items = json['items'];
    final records = <int, Map<String, Object?>>{};
    if (items is Map) {
      for (final entry in items.entries) {
        final id = int.tryParse('${entry.key}');
        if (id != null && entry.value is Map) {
          records[id] = (entry.value as Map).cast<String, Object?>();
        }
      }
    }
    return DsDetails(edition: json['edition'] as String? ?? '', records: records);
  }

  Future<Map<String, Object?>> _post(
    DsKind kind,
    Map<String, String> fields,
  ) async {
    final uri = baseUri.resolve('${kind.path}/');
    for (var attempt = 1; ; attempt++) {
      try {
        final request = http.MultipartRequest('POST', uri)
          ..headers['User-Agent'] = userAgent
          ..headers['Accept'] = 'application/json'
          ..fields.addAll(fields);
        final streamed = await _http.send(request).timeout(timeout);
        final response = await http.Response.fromStream(
          streamed,
        ).timeout(timeout);
        final status = response.statusCode;
        if (status == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, Object?>) return decoded;
          throw const DharmaSeedApiException('Unexpected response shape');
        }
        final transient = status == 429 || status >= 500;
        if (!transient || attempt >= maxAttempts) {
          throw DharmaSeedApiException('HTTP $status', statusCode: status);
        }
      } on DharmaSeedApiException {
        rethrow;
      } on FormatException catch (e) {
        throw DharmaSeedApiException('Malformed response: ${e.message}');
      } on Object catch (e) {
        final transient =
            e is SocketException ||
            e is TimeoutException ||
            e is http.ClientException ||
            e is HttpException;
        if (!transient) rethrow;
        if (attempt >= maxAttempts) {
          throw DharmaSeedApiException('Network unavailable', cause: e);
        }
      }
      await _sleep(_backoff(attempt));
    }
  }

  static List<int> _ids(Object? value) => value is List
      ? [for (final id in value) ?_asInt(id)]
      : const [];

  void close() => _http.close();
}

int? _asInt(Object? value) =>
    value is int ? value : (value is num ? value.toInt() : int.tryParse('$value'));

enum DsKind {
  teachers('teachers'),
  retreats('retreats'),
  talks('talks');

  const DsKind(this.path);

  final String path;
}

class DsIdList {
  const DsIdList({
    required this.edition,
    required this.items,
    required this.removed,
  });

  final String edition;
  final List<int> items;
  final List<int> removed;
}

class DsDetails {
  const DsDetails({required this.edition, required this.records});

  final String edition;
  final Map<int, Map<String, Object?>> records;
}

class DharmaSeedApiException implements Exception {
  const DharmaSeedApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() => 'Dharma Seed: $message';
}

/// Field parsing shared by the database writer. Dharma Seed values are loose
/// (numbers as floats, empty strings for missing), so read defensively.
extension DsRecordFields on Map<String, Object?> {
  String str(String key) {
    final value = this[key];
    return value == null ? '' : '$value'.trim();
  }

  int? integer(String key) => _asInt(this[key]);

  bool flag(String key, {bool orElse = false}) {
    final value = this[key];
    return value is bool ? value : orElse;
  }

  List<int> ints(String key) => DharmaSeedClient._ids(this[key]);
}
