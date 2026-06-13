---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/customers_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.923532+00:00
---

# archive/apps-semantos-monolith/test/repl/customers_repository_test.dart

```dart
// D-O5.followup-3 — customers_repository.dart parser test.
//
// Mirrors the test posture in `apps/loom-svelte` for the equivalent
// `parseCustomers` function and the shape of `jobs_repository_test.
// dart`: assert each of the three best-effort parser branches (JSON,
// TSV, fallback-empty) produces the expected rows from a representative
// REPL response, and assert parseCustomerOne consumes the typed
// dispatcher response shape verbatim.
//
// D-O5.followup-4 client hooks — extended with a `CustomersRepository
// cacheEvents` group that drives an in-memory HelmEventStream, asserts
// the repo surfaces `customer.created` notifications as
// CustomersCacheEvents, and ignores unrelated event types.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/customers_repository.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parseCustomers', () {
    test('decodes a JSON-array response', () {
      final body = json.encode([
        {
          'id': 'cust-001',
          'display_name': 'Acme Corp',
          'phone': '+61 400 111 222',
          'email': 'ops@acme.example',
          'address': '1 Industrial Way',
          'created_at': '2026-05-02T10:00:00Z',
        },
        {
          'id': 'cust-002',
          'name': 'Globex',
          'phone': '',
          'email': 'ops@globex.example',
          'address': '',
          'created_at': '2026-05-02T11:30:00Z',
        },
      ]);
      final rows = parseCustomers(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('cust-001'));
      expect(rows[0].displayName, equals('Acme Corp'));
      expect(rows[0].phone, equals('+61 400 111 222'));
      expect(rows[0].email, equals('ops@acme.example'));
      expect(rows[0].address, equals('1 Industrial Way'));
      expect(rows[0].createdAt, equals('2026-05-02T10:00:00Z'));
      // Falls back to the `name` key when `display_name` is absent.
      expect(rows[1].displayName, equals('Globex'));
      // List view doesn't ship notes — empty by default on the row.
      expect(rows[0].notes, equals(''));
    });

    test('decodes a TSV response with header line', () {
      const body = '''
# id\tdisplay_name\tphone\temail\taddress\tcreated_at
cust-001\tAlice\t+61 400 1\talice@x\t1 Way\t2026-05-03
cust-002\tBob\t\tbob@y\t\t2026-05-04
''';
      final rows = parseCustomers(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('cust-001'));
      expect(rows[0].displayName, equals('Alice'));
      expect(rows[1].displayName, equals('Bob'));
      expect(rows[1].email, equals('bob@y'));
    });

    test('returns empty list for an empty response', () {
      expect(parseCustomers(''), isEmpty);
      expect(parseCustomers('   \n   '), isEmpty);
    });

    test('handles malformed JSON by falling through to TSV', () {
      // Starts with `[` so the JSON branch is attempted; on parse
      // failure the TSV branch should NOT pick it up (since the
      // first line starts with `[`). Mirrors parseJobs's posture.
      const body = '[not valid json';
      final rows = parseCustomers(body);
      expect(rows, isEmpty);
    });

    // D-O5.followup-3 — integration with the typed `customers`
    // dispatcher resource.  The brain-side resource handler
    // (runtime/semantos-brain/src/resources/customers_handler.zig) emits a JSON
    // array where every row carries the canonical helm field set.
    // This test asserts parseCustomers consumes the exact bytes the
    // dispatcher emits — when a future churn drops a field on the
    // brain side, this test breaks loud.  Notes are deliberately
    // omitted from the list payload (only surfaced via find_by_id).
    test('decodes the D-O5.followup-3 dispatcher list-view response shape', () {
      // Verbatim shape from `customers_handler.zig::writeCustomerListJson`.
      const body =
          '[{"id":"abc123","display_name":"Acme Corp","phone":"+61 400 111 222",'
          '"email":"ops@acme.example","address":"1 Industrial Way",'
          '"created_at":"2026-05-02T10:00:00Z"},'
          '{"id":"def456","display_name":"Globex","phone":"","email":"",'
          '"address":"","created_at":"2026-05-02T11:30:00Z"}]';
      final rows = parseCustomers(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('abc123'));
      expect(rows[0].displayName, equals('Acme Corp'));
      expect(rows[0].phone, equals('+61 400 111 222'));
      expect(rows[0].email, equals('ops@acme.example'));
      expect(rows[0].address, equals('1 Industrial Way'));
      expect(rows[0].createdAt, equals('2026-05-02T10:00:00Z'));
      expect(rows[1].displayName, equals('Globex'));
      expect(rows[1].phone, equals(''));
      // List view doesn't ship notes.
      expect(rows[0].notes, equals(''));
    });
  });

  group('parseCustomerOne', () {
    // D-O5.followup-3 — single-customer response shape from the
    // typed `customers.find_by_id` resource. INCLUDES notes.
    test('decodes the dispatcher detail-view response shape', () {
      const body =
          '{"id":"abc123","display_name":"Acme Corp","phone":"+61 400 111 222",'
          '"email":"ops@acme.example","address":"1 Industrial Way",'
          '"notes":"Regular plumbing customer",'
          '"created_at":"2026-05-02T10:00:00Z"}';
      final c = parseCustomerOne(body);
      expect(c, isNotNull);
      expect(c!.id, equals('abc123'));
      expect(c.displayName, equals('Acme Corp'));
      expect(c.notes, equals('Regular plumbing customer'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing-id"}';
      expect(parseCustomerOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseCustomerOne(''), isNull);
      expect(parseCustomerOne('not a json envelope'), isNull);
      expect(parseCustomerOne('{not valid json'), isNull);
    });
  });

  // D-O5.followup-4 client hooks — when a HelmEventStream is supplied,
  // CustomersRepository subscribes to `customer.created` notifications
  // and surfaces them as CustomersCacheEvents on cacheEvents.  The
  // tests below drive an in-memory HelmEventStream + FakeChannel,
  // assert each event type yields the expected emission, and that the
  // dispose() path cleans up the subscription.
  group('CustomersRepository cacheEvents', () {
    test('emits customerChanged when stream produces customer.created',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['customers'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = CustomersRepository(_stubReplClient(), eventStream: stream);
      final received = <CustomersCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'customer.created',
          'data': {'id': 'cust-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.first.customerId, equals('cust-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores unrelated event types', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['customers'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = CustomersRepository(_stubReplClient(), eventStream: stream);
      final received = <CustomersCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      // Fire a job event — repo must ignore.
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'job.transitioned',
          'data': {'id': 'job-001'},
        },
      }));
      // Fire a customer event with empty id — repo must ignore (id
      // gating).
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'customer.created',
          'data': {'id': ''},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, isEmpty);

      await repo.dispose();
      await stream.dispose();
    });

    test('dispose cancels the subscription (no further emissions)',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['customers'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = CustomersRepository(_stubReplClient(), eventStream: stream);
      final received = <CustomersCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      // First emit is delivered.
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'customer.created',
          'data': {'id': 'cust-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      // After dispose, further events do not reach the repo's
      // (closed) controller.  We assert the count stays at 1.
      await repo.dispose();
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'customer.created',
          'data': {'id': 'cust-002'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await stream.dispose();
    });

    test('null eventStream leaves cacheEvents silent', () async {
      // When the stream isn't supplied (legacy / pull-only mode),
      // the repo behaves as it did pre-followup-4: cacheEvents is a
      // valid stream but never emits.
      final repo = CustomersRepository(_stubReplClient());
      final received = <CustomersCacheEvent>[];
      repo.cacheEvents.listen(received.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);
      await repo.dispose();
    });
  });
}

/// In-memory HelmStreamChannel — same shape as the one inside
/// `helm_event_stream_test.dart`.  Tests `serverSend` to drive the
/// helm side of the WSS pipe.
class _FakeChannel implements HelmStreamChannel {
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  final List<String> sent = <String>[];

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  void sendText(String data) {
    sent.add(data);
  }

  @override
  Future<void> close() async {
    if (!_toClient.isClosed) await _toClient.close();
  }

  void serverSend(String data) {
    if (!_toClient.isClosed) _toClient.add(data);
  }
}

/// Minimal ReplClient that doesn't talk to the network.  Constructed
/// against a Dio with a no-op adapter — none of the cacheEvents tests
/// fire the REPL.
ReplClient _stubReplClient() {
  final dio = Dio()..httpClientAdapter = _NoopAdapter();
  return ReplClient.withBearer(
    http: dio,
    baseUrl: 'https://oddjobtodd.test',
    bearer: 'a' * 64,
  );
}

class _NoopAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(<int>[], 200);
  }
}

```
