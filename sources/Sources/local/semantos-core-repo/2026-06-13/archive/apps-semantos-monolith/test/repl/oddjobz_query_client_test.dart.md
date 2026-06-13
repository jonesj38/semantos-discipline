---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/oddjobz_query_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.922946+00:00
---

# archive/apps-semantos-monolith/test/repl/oddjobz_query_client_test.dart

```dart
// D-DOG.1.0c Phase 3 F.1 — OddjobzQueryClient + HelmEventStream
// callOddjobzQuery wire-shape tests.
//
// Drives a hand-rolled in-memory HelmStreamChannel through the
// oddjobz.list_sites / list_customers / find_jobs_at_site send +
// receive shape, the JSON-RPC error envelope path, and the
// timeout/disconnect failure modes.  Same pattern as
// helm_event_stream_test.dart.

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/oddjobz_query_client.dart';

class _FakeChannel implements HelmStreamChannel {
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  final List<String> sent = <String>[];
  bool clientClosed = false;

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) => sent.add(data);

  @override
  Future<void> close() async {
    clientClosed = true;
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(String data) {
    if (!_toClient.isClosed) _toClient.add(data);
  }
}

void main() {
  group('OddjobzQueryClient', () {
    late _FakeChannel ch;
    HelmStreamChannel makeChannel(Uri uri) {
      ch = _FakeChannel();
      return ch;
    }

    Future<HelmEventStream> connectStream() async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      await stream.connect();
      // Let the helm.subscribe send + microtasks flush.
      await Future<void>.delayed(Duration.zero);
      return stream;
    }

    test('listSites sends the right method + decodes the wire shape',
        () async {
      final stream = await connectStream();
      final client = OddjobzQueryClient(stream);

      // Server ack the subscribe (so state is subscribed) — not
      // strictly required for callOddjobzQuery, but mirrors
      // production order-of-operations.
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true, 'topics': ['jobs']},
      }));

      // Issue the listSites call.  Capture the future without
      // awaiting; we'll synthesise the reply below, then await.
      final future = client.listSites();

      // The send should appear on the channel — find the latest
      // `oddjobz.list_sites` request and reply with the matching id.
      // (HelmEventStream uses `_subscribeId` for both subscribe and
      // RPC frames — the listSites id is whatever was current after
      // the subscribe.)
      final listSitesFrame = ch.sent.firstWhere(
        (f) => json.decode(f)['method'] == 'oddjobz.list_sites',
      );
      final id = (json.decode(listSitesFrame) as Map)['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'sites': [
            {
              'cellId': 's' * 64,
              'typeHash': 't' * 64,
              'normalisedAddress': '47 hygieta st doonside',
              'keyNumber': '177',
              'lookupKey': '47 hygieta st doonside|177',
              'fullAddress': '47 Hygieta St, Doonside',
              'suburb': 'Doonside',
              'postcode': '2767',
              'state': 'NSW',
              'createdAt': 1714003200,
            },
          ],
        },
      }));

      final sites = await future;
      expect(sites, hasLength(1));
      expect(sites[0].cellId, equals('s' * 64));
      expect(sites[0].fullAddress, equals('47 Hygieta St, Doonside'));
      expect(sites[0].keyNumber, equals('177'));
      expect(sites[0].suburb, equals('Doonside'));

      await stream.dispose();
    });

    test('listCustomers decodes both v1 + v2 rows', () async {
      final stream = await connectStream();
      final client = OddjobzQueryClient(stream);

      final future = client.listCustomers();
      final reqFrame = ch.sent.firstWhere(
        (f) => json.decode(f)['method'] == 'oddjobz.list_customers',
      );
      final id = (json.decode(reqFrame) as Map)['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'customers': [
            // v2 row — populated cellId etc.
            {
              'id': 'cust-1',
              'display_name': 'Sarah Liu',
              'phone': '555-0100',
              'email': 'sarah@example.com',
              'address': '',
              'notes': '',
              'created_at': '',
              'cellId': 'c' * 64,
              'typeHash': 't' * 64,
              'role': 'tenant',
              'normalisedPhone': '5550100',
              'sourceProvenance': null,
              'siteRef': 's' * 64,
            },
            // v1 row — every v2 field null.
            {
              'id': 'cust-2',
              'display_name': 'Legacy Bob',
              'phone': '',
              'email': 'bob@example.com',
              'address': '',
              'notes': '',
              'created_at': '',
              'cellId': null,
              'typeHash': null,
              'role': null,
              'normalisedPhone': null,
              'sourceProvenance': null,
              'siteRef': null,
            },
          ],
        },
      }));

      final customers = await future;
      expect(customers, hasLength(2));
      expect(customers[0].displayName, equals('Sarah Liu'));
      expect(customers[0].isV2, isTrue);
      expect(customers[0].cellId, equals('c' * 64));
      expect(customers[0].role, equals('tenant'));
      expect(customers[1].displayName, equals('Legacy Bob'));
      expect(customers[1].isV2, isFalse);
      expect(customers[1].cellId, isNull);

      await stream.dispose();
    });

    test('JSON-RPC error envelope surfaces as OddjobzQueryError', () async {
      final stream = await connectStream();
      final client = OddjobzQueryClient(stream);

      final future = client.listSites();
      final reqFrame = ch.sent.firstWhere(
        (f) => json.decode(f)['method'] == 'oddjobz.list_sites',
      );
      final id = (json.decode(reqFrame) as Map)['id'] as int;

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {
          'code': -32603,
          'message': 'sites store unavailable',
        },
      }));

      await expectLater(
        future,
        throwsA(isA<OddjobzQueryError>()
            .having((e) => e.code, 'code', equals(-32603))
            .having((e) => e.message, 'message',
                equals('sites store unavailable'))),
      );

      await stream.dispose();
    });

    test('callOddjobzQuery without an open WSS throws StateError', () async {
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['jobs'],
        channelFactory: makeChannel,
      );
      // Don't connect.
      await expectLater(
        stream.callOddjobzQuery('oddjobz.list_sites', const {}),
        throwsA(isA<StateError>()),
      );
      await stream.dispose();
    });

    test('disconnect drains pending oddjobz queries with OddjobzQueryError',
        () async {
      final stream = await connectStream();
      final client = OddjobzQueryClient(stream);

      // Issue but don't reply.
      final future = client.listSites();
      // Allow the send to flush before disconnecting.
      await Future<void>.delayed(Duration.zero);

      // Tear down — pending Future should error out, not hang.
      await stream.disconnect();

      await expectLater(
        future,
        throwsA(isA<OddjobzQueryError>()
            .having((e) => e.code, 'code', equals(-32000))),
      );
    });

    test('findJobsAtSite returns the raw rows verbatim for caller shaping',
        () async {
      final stream = await connectStream();
      final client = OddjobzQueryClient(stream);

      final future = client.findJobsAtSite('a' * 64);
      final reqFrame = ch.sent.firstWhere(
        (f) => json.decode(f)['method'] == 'oddjobz.find_jobs_at_site',
      );
      final reqDecoded = json.decode(reqFrame) as Map;
      final id = reqDecoded['id'] as int;
      // Confirm the params were sent.
      expect(reqDecoded['params'], equals({'siteRef': 'a' * 64}));

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'jobs': [
            {
              'version': 2,
              'id': 'J1',
              'customer_name': '',
              'state': 'lead',
              'scheduled_at': '',
              'created_at': '',
              'cellId': 'j' * 64,
              'siteRef': 'a' * 64,
              'hasPhotos': true,
            },
          ],
        },
      }));

      final rows = await future;
      expect(rows, hasLength(1));
      expect(rows[0]['cellId'], equals('j' * 64));
      expect(rows[0]['hasPhotos'], isTrue);

      await stream.dispose();
    });
  });
}

```
