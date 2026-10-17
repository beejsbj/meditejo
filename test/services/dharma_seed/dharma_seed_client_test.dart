import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medito/services/dharma_seed/dharma_seed_client.dart';

import '../../helpers/dharma_seed_fake_api.dart';

void main() {
  group('DharmaSeedClient', () {
    test('lists IDs with a multipart POST and a Meditejo User-Agent', () async {
      final api = FakeDharmaSeedApi();
      final list = await api.client().fetchIds(DsKind.talks);

      expect(list.edition, dsFirstEdition);
      expect(list.items, contains(99974));
      expect(list.removed, [15, 43]);
      final request = api.requests.single;
      expect(request.kind, 'talks');
      expect(request.fields, {'detail': '0'});
      expect(request.headers['User-Agent'], contains('Meditejo'));
      expect(
        request.headers['User-Agent'],
        contains('github.com/beejsbj/meditejo'),
      );
    });

    test('passes the edition back for incremental lists', () async {
      final api = FakeDharmaSeedApi();
      final list = await api.client().fetchIds(
        DsKind.talks,
        edition: dsFirstEdition,
      );

      expect(api.requests.single.fields['edition'], dsFirstEdition);
      expect(list.edition, dsSecondEdition);
      expect(list.items, [99974]);
      expect(list.removed, [95073]);
    });

    test('fetches detail records keyed by ID', () async {
      final api = FakeDharmaSeedApi();
      final details = await api.client().fetchDetails(DsKind.talks, [
        95073,
        97073,
        12345,
      ]);

      expect(api.requests.single.fields['items'], '95073,97073,12345');
      expect(details.records.keys, unorderedEquals([95073, 97073]));
      final talk = details.records[95073]!;
      expect(talk.str('title'), 'talk: Renewing motivation');
      expect(talk.integer('teacher_id'), 637);
      expect(talk.str('audio_url'), startsWith('/talks/95073/'));
    });

    test('decodes a large batch off the main isolate, unchanged', () async {
      // Well over the 32 KiB threshold, with non-ASCII text to prove the
      // UTF-8 round trip.
      final items = {
        for (var id = 1; id <= 400; id++)
          '$id': {
            'id': id,
            'title': 'Ñāṇa $id ${'x' * 120}',
            'duration_in_minutes': 12.5,
          },
      };
      final client = DharmaSeedClient(
        httpClient: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode({'edition': 'e', 'items': items})),
            200,
          ),
        ),
      );
      final details = await client.fetchDetails(DsKind.talks, [1, 400]);
      expect(details.records.length, 400);
      expect(details.records[7]!.str('title'), startsWith('Ñāṇa 7 '));
    });

    test('makes no request for an empty detail list', () async {
      final api = FakeDharmaSeedApi();
      final details = await api.client().fetchDetails(DsKind.talks, []);
      expect(details.records, isEmpty);
      expect(api.requests, isEmpty);
    });

    test('backs off and retries server errors', () async {
      final api = FakeDharmaSeedApi(
        fail: (_, index) => index < 2 ? http.Response('busy', 503) : null,
      );
      final waits = <Duration>[];
      final client = DharmaSeedClient(
        httpClient: api.httpClient,
        sleep: (d) async => waits.add(d),
      );

      final list = await client.fetchIds(DsKind.teachers);

      expect(list.items, [210, 637, 198]);
      expect(api.requests, hasLength(3));
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 4)]);
    });

    test('does not retry client errors', () async {
      final api = FakeDharmaSeedApi(fail: (_, _) => http.Response('no', 404));
      final client = DharmaSeedClient(
        httpClient: api.httpClient,
        sleep: (_) async {},
      );

      await expectLater(
        client.fetchIds(DsKind.teachers),
        throwsA(
          isA<DharmaSeedApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
      expect(api.requests, hasLength(1));
    });

    test('gives up on a dead network after its attempts', () async {
      var calls = 0;
      final client = DharmaSeedClient(
        httpClient: MockClient((_) async {
          calls++;
          throw const SocketException('offline');
        }),
        maxAttempts: 3,
        sleep: (_) async {},
      );

      await expectLater(
        client.fetchIds(DsKind.retreats),
        throwsA(isA<DharmaSeedApiException>()),
      );
      expect(calls, 3);
    });
  });
}
