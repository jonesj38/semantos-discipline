---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/ratification/ratification_queue_client_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.916601+00:00
---

# archive/apps-semantos-monolith/test/ratification/ratification_queue_client_test.dart

```dart
// D-O5m.followup-7 Phase B — RatificationQueueClient parser + verb
// dispatch tests.
//
// Mirrors test/repl/jobs_repository_test.dart's posture: each parser
// branch is asserted against the verbatim brain-handler response shape so
// a future brain-side rename breaks loud here, plus each verb dispatch
// is asserted via a recording dio adapter that captures the REPL line.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/ratification/ratification_queue_client.dart';
import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parsePendingLeads', () {
    test('decodes the dispatcher leads.find response shape', () {
      // Verbatim shape from leads_handler.zig::writeLeadJson.
      const body = '['
          '{"id":"L1","customer_name":"Alice","phone":"555-0100","email":"alice@example.com",'
          '"summary":"Wants a hedge trim","source":"chat","source_correlation_id":"thread-42",'
          '"status":"pending","rejection_reason":"","hat_id":"hat-mowing",'
          '"created_at":"2026-05-02T09:00:00Z","updated_at":"2026-05-02T09:00:00Z"},'
          '{"id":"L2","customer_name":"Bob","phone":"","email":"","summary":"",'
          '"source":"manual","source_correlation_id":"","status":"pending",'
          '"rejection_reason":"","hat_id":"",'
          '"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}'
          ']';
      final rows = parsePendingLeads(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('L1'));
      expect(rows[0].customerName, equals('Alice'));
      expect(rows[0].phone, equals('555-0100'));
      expect(rows[0].source, equals('chat'));
      expect(rows[0].sourceCorrelationId, equals('thread-42'));
      expect(rows[0].hatId, equals('hat-mowing'));
      expect(rows[1].id, equals('L2'));
      expect(rows[1].phone, isEmpty);
      expect(rows[1].source, equals('manual'));
    });

    test('returns empty list on empty / non-JSON input', () {
      expect(parsePendingLeads(''), isEmpty);
      expect(parsePendingLeads('   '), isEmpty);
      expect(parsePendingLeads('not json'), isEmpty);
      expect(parsePendingLeads('[{"id":"L1",'), isEmpty);
    });
  });

  group('parsePendingLeadOne', () {
    test('decodes the single-lead success shape', () {
      const body =
          '{"id":"L1","customer_name":"Alice","phone":"","email":"",'
          '"summary":"Wants a quote","source":"voice","source_correlation_id":"",'
          '"status":"pending","rejection_reason":"","hat_id":"",'
          '"created_at":"2026-05-02T09:00:00Z","updated_at":"2026-05-02T09:00:00Z"}';
      final lead = parsePendingLeadOne(body);
      expect(lead, isNotNull);
      expect(lead!.id, equals('L1'));
      expect(lead.customerName, equals('Alice'));
      expect(lead.source, equals('voice'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing"}';
      expect(parsePendingLeadOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parsePendingLeadOne(''), isNull);
      expect(parsePendingLeadOne('not json'), isNull);
      expect(parsePendingLeadOne('{not valid'), isNull);
    });
  });

  group('RatificationQueueClient verb dispatch', () {
    RatificationQueueClient newClient(_RecordingAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      final client = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'a' * 64,
      );
      return RatificationQueueClient(client);
    }

    String wrapResult(String inner) => json.encode({
          'result': inner,
          'exit': 'continue',
        });

    String successLeadBody(String state) => json.encode({
          'id': 'L1',
          'customer_name': 'Alice',
          'phone': '',
          'email': '',
          'summary': '',
          'source': 'chat',
          'source_correlation_id': '',
          'status': state,
          'rejection_reason': '',
          'hat_id': '',
          'created_at': '2026-05-02T09:00:00Z',
          'updated_at': '2026-05-02T09:30:00Z',
        });

    test('findPending sends `find leads --status pending`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult('[]')),
      );
      final client = newClient(adapter);
      final rows = await client.findPending();
      expect(rows, isEmpty);
      expect(adapter.lastBody!['cmd'], equals('find leads --status pending'));
    });

    test('findPending with hatId appends --hat <id>', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult('[]')),
      );
      final client = newClient(adapter);
      await client.findPending(hatId: 'hat-mowing');
      expect(
        adapter.lastBody!['cmd'],
        equals('find leads --status pending --hat hat-mowing'),
      );
    });

    test('findById sends `find lead <id>` and decodes a Lead', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(successLeadBody('pending'))),
      );
      final client = newClient(adapter);
      final lead = await client.findById('L1');
      expect(lead, isNotNull);
      expect(lead!.id, equals('L1'));
      expect(adapter.lastBody!['cmd'], equals('find lead L1'));
    });

    test('ratify sends `ratify lead <id>` and decodes success', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(successLeadBody('ratified'))),
      );
      final client = newClient(adapter);
      final r = await client.ratify('L1');
      expect(r, isA<RatifySuccess>());
      expect((r as RatifySuccess).lead.status, equals('ratified'));
      expect(adapter.lastBody!['cmd'], equals('ratify lead L1'));
    });

    test('ratify decodes already_in_state body', () async {
      const body =
          '{"status":"already_in_state","lead":{"id":"L1","customer_name":"Alice",'
          '"phone":"","email":"","summary":"","source":"chat",'
          '"source_correlation_id":"","status":"ratified","rejection_reason":"",'
          '"hat_id":"","created_at":"","updated_at":""}}';
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(body)),
      );
      final client = newClient(adapter);
      final r = await client.ratify('L1');
      expect(r, isA<RatifyAlreadyInState>());
      expect((r as RatifyAlreadyInState).lead.status, equals('ratified'));
    });

    test('ratify decodes typed wrong_cap error', () async {
      const body =
          '{"error":"wrong_cap","from":"pending","to":"ratified",'
          '"cap_required":"cap.oddjobz.write_customer"}';
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(body)),
      );
      final client = newClient(adapter);
      final r = await client.ratify('L1');
      expect(r, isA<RatifyError>());
      final e = r as RatifyError;
      expect(e.kind, equals('wrong_cap'));
      expect(e.capRequired, equals('cap.oddjobz.write_customer'));
      expect(e.message, contains('cap.oddjobz.write_customer'));
    });

    test('reject sends `reject lead <id> --reason <wire>`', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(successLeadBody('rejected'))),
      );
      final client = newClient(adapter);
      final r = await client.reject('L1', RejectionReason.spam);
      expect(r, isA<RejectSuccess>());
      expect(
        adapter.lastBody!['cmd'],
        equals('reject lead L1 --reason spam'),
      );
    });

    test('reject decodes typed not_found error', () async {
      const body =
          '{"error":"not_found","from":"","to":"rejected","cap_required":null}';
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(body)),
      );
      final client = newClient(adapter);
      final r = await client.reject('L1', RejectionReason.duplicate);
      expect(r, isA<RejectError>());
      expect((r as RejectError).kind, equals('not_found'));
      expect(r.message, contains('no longer exists'));
    });

    test('defer sends `defer lead <id>` and decodes success', () async {
      final adapter = _RecordingAdapter(
        statusCode: 200,
        body: utf8.encode(wrapResult(successLeadBody('deferred'))),
      );
      final client = newClient(adapter);
      final r = await client.defer('L1');
      expect(r, isA<DeferSuccess>());
      expect((r as DeferSuccess).lead.status, equals('deferred'));
      expect(adapter.lastBody!['cmd'], equals('defer lead L1'));
    });
  });

  group('RatificationQueueClient cache events', () {
    test('emits LeadCacheEvent on lead.created with operator-attention',
        () async {
      // Drive a fake HelmEventStream by injecting a channel factory
      // backed by an in-memory StreamController.  Pattern mirrors
      // test/repl/helm_event_stream_test.dart's `_FakeChannel`.
      final fake = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'wss://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['leads'],
        channelFactory: (_) => fake,
        reconnectBackoff: const [Duration(milliseconds: 1)],
      );

      // No real REPL needed for the cache-event path.
      final repl = ReplClient.withBearer(
        http: Dio()..httpClientAdapter = _RecordingAdapter(
          statusCode: 200,
          body: utf8.encode('{"result":"","exit":"continue"}'),
        ),
        baseUrl: 'https://example.test',
        bearer: 'a' * 64,
      );
      final client = RatificationQueueClient(repl, eventStream: stream);

      final received = <LeadCacheEvent>[];
      final sub = client.cacheEvents.listen(received.add);

      await stream.connect();
      // Ack the subscribe so the state machine is stable.
      fake.send(json.encode({
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'subscribed': true},
      }));
      // Drive a `lead.created` notification.
      fake.send(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'lead.created',
          'data': {
            'lead_id': 'L1',
            'id': 'L1',
            'customer_name': 'Alice',
            'summary': 'Hedge trim',
            'source': 'chat',
            'hat_id': '',
            'created_at': '2026-05-02T09:00:00Z',
          },
        },
      }));

      // Yield so the broadcast subscriber fires.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(received, hasLength(1));
      expect(received[0].kind, equals('lead.created'));
      expect(received[0].leadId, equals('L1'));

      // Drive a `lead.transitioned` notification.
      fake.send(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'lead.transitioned',
          'data': {
            'id': 'L1',
            'from': 'pending',
            'to': 'ratified',
            'transitioned_at': '2026-05-02T10:00:00Z',
          },
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, hasLength(2));
      expect(received[1].kind, equals('lead.transitioned'));
      expect(received[1].fromState, equals('pending'));
      expect(received[1].toState, equals('ratified'));

      await sub.cancel();
      await client.dispose();
      await stream.dispose();
    });
  });
}

/// In-memory channel — the production HelmEventStream wires
/// WebSocketChannel.connect; tests inject a fake backed by a
/// StreamController so frames can be driven from the test body.
class _FakeChannel implements HelmStreamChannel {
  final _ctl = StreamController<dynamic>.broadcast();

  @override
  Stream<dynamic> get stream => _ctl.stream;

  @override
  void sendText(String data) {
    // Outgoing frames (helm.subscribe) are dropped — tests don't need
    // to assert on them for the cache-event test.
  }

  void send(String data) => _ctl.add(data);

  @override
  Future<void> close() async {
    if (!_ctl.isClosed) await _ctl.close();
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  Map<String, dynamic>? lastBody;
  _RecordingAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final raw = await requestStream
          .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
      try {
        final decoded = json.decode(utf8.decode(raw));
        if (decoded is Map<String, dynamic>) lastBody = decoded;
      } catch (_) {
        // Ignore non-JSON.
      }
    }
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

```
