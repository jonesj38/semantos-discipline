---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/quotes_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.921114+00:00
---

# archive/apps-semantos-monolith/test/repl/quotes_repository_test.dart

```dart
// D-O4.followup-3 — quotes_repository.dart parser test.
//
// Mirrors the test posture in `apps/loom-svelte` for the equivalent
// `parseQuotes` function and the shape of `visits_repository_test.
// dart`.  Asserts:
//   • parseQuotes consumes the JSON-array shape the Semantos Brain dispatcher's
//     `quotes.find` emits;
//   • parseQuoteOne consumes both the success body + the typed
//     not_found envelope;
//   • parseQuoteCreateResult consumes the success body + the FK-
//     rejection body (`{error: "job_not_found", job_id}`);
//   • parseQuoteTransitionResult consumes success / already_in_state /
//     typed-error bodies.
//
// D-O5.followup-4 client hooks — extended with a `QuotesRepository
// cacheEvents` group asserting quote.created + quote.transitioned both
// surface as QuotesCacheEvents.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/quotes_repository.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parseQuotes', () {
    test('decodes a JSON-array response (dispatcher shape)', () {
      // Verbatim shape from `quotes_handler.zig::writeQuoteJson`.
      final body = json.encode([
        {
          'id': 'q-001',
          'job_id': 'j-001',
          'status': 'draft',
          'cost_min': 5000,
          'cost_max': 20000,
          'notes': 'first quote',
          'accepted_at': '',
          'rejected_at': '',
          'created_at': '2026-05-02T10:00:00Z',
          'updated_at': '2026-05-02T10:00:00Z',
        },
        {
          'id': 'q-002',
          'job_id': 'j-001',
          'status': 'accepted',
          'cost_min': 1000,
          'cost_max': 1500,
          'notes': '',
          'accepted_at': '2026-05-15T09:00:00Z',
          'rejected_at': '',
          'created_at': '2026-05-15T08:30:00Z',
          'updated_at': '2026-05-15T11:00:00Z',
        },
      ]);
      final rows = parseQuotes(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('q-001'));
      expect(rows[0].jobId, equals('j-001'));
      expect(rows[0].status, equals('draft'));
      expect(rows[0].costMin, equals(5000));
      expect(rows[0].costMax, equals(20000));
      expect(rows[0].notes, equals('first quote'));
      expect(rows[1].status, equals('accepted'));
      expect(rows[1].acceptedAt, equals('2026-05-15T09:00:00Z'));
    });

    test('returns empty list for empty / non-JSON / malformed responses', () {
      expect(parseQuotes(''), isEmpty);
      expect(parseQuotes('   \n   '), isEmpty);
      expect(parseQuotes('not json'), isEmpty);
      expect(parseQuotes('[bad json'), isEmpty);
    });
  });

  group('parseQuoteOne', () {
    test('decodes the dispatcher single-quote response shape', () {
      const body =
          '{"id":"q-001","job_id":"j-001","status":"presented",'
          '"cost_min":5000,"cost_max":20000,"notes":"on site",'
          '"accepted_at":"","rejected_at":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final q = parseQuoteOne(body);
      expect(q, isNotNull);
      expect(q!.id, equals('q-001'));
      expect(q.status, equals('presented'));
      expect(q.costMin, equals(5000));
      expect(q.costMax, equals(20000));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing"}';
      expect(parseQuoteOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseQuoteOne(''), isNull);
      expect(parseQuoteOne('text'), isNull);
      expect(parseQuoteOne('{bad'), isNull);
    });
  });

  group('parseQuoteCreateResult', () {
    test('decodes the success body', () {
      const body = '{"id":"q-001","status":"created"}';
      final r = parseQuoteCreateResult(body);
      expect(r, isA<QuoteCreateSuccess>());
      final s = r as QuoteCreateSuccess;
      expect(s.id, equals('q-001'));
      expect(s.status, equals('created'));
    });

    test('decodes the already_exists body', () {
      const body = '{"id":"q-002","status":"already_exists"}';
      final r = parseQuoteCreateResult(body);
      expect(r, isA<QuoteCreateSuccess>());
      expect((r as QuoteCreateSuccess).status, equals('already_exists'));
    });

    test('decodes the FK-rejection body', () {
      const body = '{"error":"job_not_found","job_id":"j-missing"}';
      final r = parseQuoteCreateResult(body);
      expect(r, isA<QuoteCreateError>());
      final e = r as QuoteCreateError;
      expect(e.kind, equals('job_not_found'));
      expect(e.jobId, equals('j-missing'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseQuoteCreateResult('not json');
      expect(r, isA<QuoteCreateError>());
      expect((r as QuoteCreateError).kind, equals('parse_error'));
    });
  });

  group('parseQuoteTransitionResult', () {
    test('decodes the success body (post-transition Quote)', () {
      const body =
          '{"id":"q-001","job_id":"j-001","status":"presented",'
          '"cost_min":5000,"cost_max":20000,"notes":"",'
          '"accepted_at":"","rejected_at":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final r = parseQuoteTransitionResult(body);
      expect(r, isA<QuoteTransitionSuccess>());
      expect((r as QuoteTransitionSuccess).quote.status, equals('presented'));
    });

    test('decodes the already_in_state body', () {
      const body =
          '{"status":"already_in_state","quote":{"id":"q-001","job_id":"j-001",'
          '"status":"draft","cost_min":5000,"cost_max":20000,"notes":"",'
          '"accepted_at":"","rejected_at":"",'
          '"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}';
      final r = parseQuoteTransitionResult(body);
      expect(r, isA<QuoteTransitionAlreadyInState>());
      expect((r as QuoteTransitionAlreadyInState).quote.status, equals('draft'));
    });

    test('decodes the typed not_reachable error body', () {
      const body =
          '{"error":"not_reachable","from":"draft","to":"accepted","cap_required":null}';
      final r = parseQuoteTransitionResult(body);
      expect(r, isA<QuoteTransitionError>());
      final e = r as QuoteTransitionError;
      expect(e.kind, equals('not_reachable'));
      expect(e.from, equals('draft'));
      expect(e.to, equals('accepted'));
      expect(e.capRequired, isNull);
      expect(e.message, contains('Cannot transition'));
    });

    test('decodes the wrong_principal error body', () {
      const body =
          '{"error":"wrong_principal","from":"presented","to":"accepted","cap_required":null}';
      final r = parseQuoteTransitionResult(body);
      expect(r, isA<QuoteTransitionError>());
      expect((r as QuoteTransitionError).kind, equals('wrong_principal'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseQuoteTransitionResult('not json');
      expect(r, isA<QuoteTransitionError>());
      expect((r as QuoteTransitionError).kind, equals('parse_error'));
    });
  });

  // D-O5.followup-4 client hooks — drive an in-memory HelmEventStream
  // and assert the repo surfaces both `quote.created` AND
  // `quote.transitioned` as QuotesCacheEvents, ignores unrelated
  // event types, and stops emitting after dispose().
  group('QuotesRepository cacheEvents', () {
    test('emits quoteChanged when stream produces quote.created', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['quotes'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = QuotesRepository(_stubReplClient(), eventStream: stream);
      final received = <QuotesCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'quote.created',
          'data': {'id': 'q-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));
      expect(received.first.quoteId, equals('q-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('emits quoteChanged when stream produces quote.transitioned',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['quotes'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = QuotesRepository(_stubReplClient(), eventStream: stream);
      final received = <QuotesCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'quote.transitioned',
          'data': {'id': 'q-001', 'from': 'draft', 'to': 'presented'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));
      expect(received.first.quoteId, equals('q-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores unrelated event types', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['quotes'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = QuotesRepository(_stubReplClient(), eventStream: stream);
      final received = <QuotesCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'invoice.created',
          'data': {'id': 'i-001'},
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
        topics: const ['quotes'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = QuotesRepository(_stubReplClient(), eventStream: stream);
      final received = <QuotesCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'quote.created',
          'data': {'id': 'q-001'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await repo.dispose();
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'quote.created',
          'data': {'id': 'q-002'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));

      await stream.dispose();
    });
  });
}

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
