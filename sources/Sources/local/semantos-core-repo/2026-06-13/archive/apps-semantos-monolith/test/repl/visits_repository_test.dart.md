---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/visits_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.923243+00:00
---

# archive/apps-semantos-monolith/test/repl/visits_repository_test.dart

```dart
// D-O4.followup-2 — visits_repository.dart parser test.
//
// Mirrors the test posture in `apps/loom-svelte` for the equivalent
// `parseVisits` function and the shape of `customers_repository_test.
// dart` + `jobs_repository_test.dart`.  Asserts:
//   • parseVisits consumes the JSON-array shape the Semantos Brain dispatcher's
//     `visits.find` emits;
//   • parseVisitOne consumes both the success body + the typed
//     not_found envelope;
//   • parseVisitCreateResult consumes the success body + the FK-
//     rejection body (`{error: "job_not_found", job_id}`);
//   • parseVisitTransitionResult consumes success / already_in_state /
//     typed-error bodies.
//
// D-O5.followup-4 client hooks — extended with a `VisitsRepository
// cacheEvents` group asserting visit.created + visit.transitioned both
// surface as VisitsCacheEvents and that unrelated event types are
// ignored.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/repl/visits_repository.dart';

void main() {
  group('parseVisits', () {
    test('decodes a JSON-array response (dispatcher shape)', () {
      // Verbatim shape from `visits_handler.zig::writeVisitJson`.
      final body = json.encode([
        {
          'id': 'v-001',
          'job_id': 'j-001',
          'visit_type': 'scheduled_work',
          'status': 'scheduled',
          'notes': 'first inspection',
          'actual_start': '',
          'outcome': '',
          'created_at': '2026-05-02T10:00:00Z',
          'updated_at': '2026-05-02T10:00:00Z',
        },
        {
          'id': 'v-002',
          'job_id': 'j-001',
          'visit_type': 'return_visit',
          'status': 'completed',
          'notes': '',
          'actual_start': '2026-05-15T09:00:00Z',
          'outcome': 'completed',
          'created_at': '2026-05-15T08:30:00Z',
          'updated_at': '2026-05-15T11:00:00Z',
        },
      ]);
      final rows = parseVisits(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('v-001'));
      expect(rows[0].jobId, equals('j-001'));
      expect(rows[0].visitType, equals('scheduled_work'));
      expect(rows[0].status, equals('scheduled'));
      expect(rows[0].notes, equals('first inspection'));
      expect(rows[1].status, equals('completed'));
      expect(rows[1].outcome, equals('completed'));
      expect(rows[1].actualStart, equals('2026-05-15T09:00:00Z'));
    });

    test('returns empty list for empty / non-JSON / malformed responses', () {
      expect(parseVisits(''), isEmpty);
      expect(parseVisits('   \n   '), isEmpty);
      expect(parseVisits('not json'), isEmpty);
      expect(parseVisits('[bad json'), isEmpty);
    });
  });

  group('parseVisitOne', () {
    test('decodes the dispatcher single-visit response shape', () {
      const body =
          '{"id":"v-001","job_id":"j-001","visit_type":"scheduled_work",'
          '"status":"in_progress","notes":"on site",'
          '"actual_start":"2026-05-15T09:00:00Z","outcome":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final v = parseVisitOne(body);
      expect(v, isNotNull);
      expect(v!.id, equals('v-001'));
      expect(v.status, equals('in_progress'));
      expect(v.actualStart, equals('2026-05-15T09:00:00Z'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing"}';
      expect(parseVisitOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseVisitOne(''), isNull);
      expect(parseVisitOne('text'), isNull);
      expect(parseVisitOne('{bad'), isNull);
    });
  });

  group('parseVisitCreateResult', () {
    test('decodes the success body', () {
      const body = '{"id":"v-001","status":"created"}';
      final r = parseVisitCreateResult(body);
      expect(r, isA<VisitCreateSuccess>());
      final s = r as VisitCreateSuccess;
      expect(s.id, equals('v-001'));
      expect(s.status, equals('created'));
    });

    test('decodes the already_exists body', () {
      const body = '{"id":"v-002","status":"already_exists"}';
      final r = parseVisitCreateResult(body);
      expect(r, isA<VisitCreateSuccess>());
      expect((r as VisitCreateSuccess).status, equals('already_exists'));
    });

    test('decodes the FK-rejection body', () {
      const body = '{"error":"job_not_found","job_id":"j-missing"}';
      final r = parseVisitCreateResult(body);
      expect(r, isA<VisitCreateError>());
      final e = r as VisitCreateError;
      expect(e.kind, equals('job_not_found'));
      expect(e.jobId, equals('j-missing'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseVisitCreateResult('not json');
      expect(r, isA<VisitCreateError>());
      expect((r as VisitCreateError).kind, equals('parse_error'));
    });
  });

  group('parseVisitTransitionResult', () {
    test('decodes the success body (post-transition Visit)', () {
      const body =
          '{"id":"v-001","job_id":"j-001","visit_type":"scheduled_work",'
          '"status":"in_progress","notes":"",'
          '"actual_start":"2026-05-15T09:00:00Z","outcome":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final r = parseVisitTransitionResult(body);
      expect(r, isA<VisitTransitionSuccess>());
      expect((r as VisitTransitionSuccess).visit.status, equals('in_progress'));
    });

    test('decodes the already_in_state body', () {
      const body =
          '{"status":"already_in_state","visit":{"id":"v-001","job_id":"j-001",'
          '"visit_type":"scheduled_work","status":"scheduled","notes":"",'
          '"actual_start":"","outcome":"",'
          '"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}';
      final r = parseVisitTransitionResult(body);
      expect(r, isA<VisitTransitionAlreadyInState>());
      expect((r as VisitTransitionAlreadyInState).visit.status, equals('scheduled'));
    });

    test('decodes the typed not_reachable error body', () {
      const body =
          '{"error":"not_reachable","from":"scheduled","to":"completed","cap_required":null}';
      final r = parseVisitTransitionResult(body);
      expect(r, isA<VisitTransitionError>());
      final e = r as VisitTransitionError;
      expect(e.kind, equals('not_reachable'));
      expect(e.from, equals('scheduled'));
      expect(e.to, equals('completed'));
      expect(e.capRequired, isNull);
      expect(e.message, contains('Cannot transition'));
    });

    test('decodes the wrong_principal error body', () {
      const body =
          '{"error":"wrong_principal","from":"scheduled","to":"in_progress","cap_required":null}';
      final r = parseVisitTransitionResult(body);
      expect(r, isA<VisitTransitionError>());
      expect((r as VisitTransitionError).kind, equals('wrong_principal'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseVisitTransitionResult('not json');
      expect(r, isA<VisitTransitionError>());
      expect((r as VisitTransitionError).kind, equals('parse_error'));
    });
  });

  // D-O5.followup-4 client hooks — drive an in-memory HelmEventStream
  // and assert the repo surfaces both `visit.created` AND
  // `visit.transitioned` as VisitsCacheEvents, ignores unrelated
  // event types, and stops emitting after dispose().
  group('VisitsRepository cacheEvents', () {
    test('emits visitChanged when stream produces visit.created', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['visits'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = VisitsRepository(_stubReplClient(), eventStream: stream);
      final received = <VisitsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'visit.created',
          'data': {'id': 'v-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.first.visitId, equals('v-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('emits visitChanged when stream produces visit.transitioned',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['visits'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = VisitsRepository(_stubReplClient(), eventStream: stream);
      final received = <VisitsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'visit.transitioned',
          'data': {'id': 'v-001', 'from': 'scheduled', 'to': 'in_progress'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(received, hasLength(1));
      expect(received.first.visitId, equals('v-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores unrelated event types', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['visits'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = VisitsRepository(_stubReplClient(), eventStream: stream);
      final received = <VisitsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'job.transitioned',
          'data': {'id': 'job-001'},
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
        topics: const ['visits'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = VisitsRepository(_stubReplClient(), eventStream: stream);
      final received = <VisitsCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'visit.created',
          'data': {'id': 'v-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await repo.dispose();
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'visit.created',
          'data': {'id': 'v-002'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await stream.dispose();
    });
  });
}

/// In-memory HelmStreamChannel — same shape as the one inside
/// `helm_event_stream_test.dart`.
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
