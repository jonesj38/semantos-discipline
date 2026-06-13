---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/invoices_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.920215+00:00
---

# archive/apps-semantos-monolith/test/repl/invoices_repository_test.dart

```dart
// D-O4.followup-4 — invoices_repository.dart parser test.
//
// Mirrors the test posture in `apps/loom-svelte` for the equivalent
// `parseInvoices` function and the shape of `quotes_repository_test.
// dart`.  Asserts:
//   • parseInvoices consumes the JSON-array shape the Semantos Brain dispatcher's
//     `invoices.find` emits;
//   • parseInvoiceOne consumes both the success body + the typed
//     not_found envelope;
//   • parseInvoiceCreateResult consumes the success body + the FK-
//     rejection body (`{error: "job_not_found", job_id}`);
//   • parseInvoiceTransitionResult consumes success / already_in_state
//     / typed-error bodies.
//
// Closes the Semantos Brain-side cutover of all 4 oddjobz FSMs.
//
// D-O5.followup-4 client hooks — extended with an `InvoicesRepository
// cacheEvents` group asserting invoice.created + invoice.transitioned
// both surface as InvoicesCacheEvents.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/helm_event_stream.dart';
import 'package:semantos/src/repl/invoices_repository.dart';
import 'package:semantos/src/repl/repl_client.dart';

void main() {
  group('parseInvoices', () {
    test('decodes a JSON-array response (dispatcher shape)', () {
      // Verbatim shape from `invoices_handler.zig::writeInvoiceJson`.
      final body = json.encode([
        {
          'id': 'i-001',
          'job_id': 'j-001',
          'status': 'draft',
          'amount': 25000,
          'amount_paid': 0,
          'external_invoice_id': '',
          'notes': 'first invoice',
          'sent_at': '',
          'viewed_at': '',
          'paid_at': '',
          'created_at': '2026-05-02T10:00:00Z',
          'updated_at': '2026-05-02T10:00:00Z',
        },
        {
          'id': 'i-002',
          'job_id': 'j-001',
          'status': 'paid',
          'amount': 1500,
          'amount_paid': 1500,
          'external_invoice_id': 'INV-2026-001',
          'notes': '',
          'sent_at': '2026-05-15T08:30:00Z',
          'viewed_at': '2026-05-15T09:00:00Z',
          'paid_at': '2026-06-01T11:00:00Z',
          'created_at': '2026-05-15T08:30:00Z',
          'updated_at': '2026-06-01T11:00:00Z',
        },
      ]);
      final rows = parseInvoices(body);
      expect(rows, hasLength(2));
      expect(rows[0].id, equals('i-001'));
      expect(rows[0].jobId, equals('j-001'));
      expect(rows[0].status, equals('draft'));
      expect(rows[0].amount, equals(25000));
      expect(rows[0].notes, equals('first invoice'));
      expect(rows[1].status, equals('paid'));
      expect(rows[1].amountPaid, equals(1500));
      expect(rows[1].externalInvoiceId, equals('INV-2026-001'));
      expect(rows[1].paidAt, equals('2026-06-01T11:00:00Z'));
    });

    test('returns empty list for empty / non-JSON / malformed responses', () {
      expect(parseInvoices(''), isEmpty);
      expect(parseInvoices('   \n   '), isEmpty);
      expect(parseInvoices('not json'), isEmpty);
      expect(parseInvoices('[bad json'), isEmpty);
    });
  });

  group('parseInvoiceOne', () {
    test('decodes the dispatcher single-invoice response shape', () {
      const body =
          '{"id":"i-001","job_id":"j-001","status":"sent",'
          '"amount":25000,"amount_paid":0,'
          '"external_invoice_id":"","notes":"on site",'
          '"sent_at":"2026-05-15T08:30:00Z","viewed_at":"","paid_at":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final inv = parseInvoiceOne(body);
      expect(inv, isNotNull);
      expect(inv!.id, equals('i-001'));
      expect(inv.status, equals('sent'));
      expect(inv.amount, equals(25000));
      expect(inv.sentAt, equals('2026-05-15T08:30:00Z'));
    });

    test('returns null for the typed not_found envelope', () {
      const body = '{"error":"not_found","id":"missing"}';
      expect(parseInvoiceOne(body), isNull);
    });

    test('returns null for empty / malformed responses', () {
      expect(parseInvoiceOne(''), isNull);
      expect(parseInvoiceOne('text'), isNull);
      expect(parseInvoiceOne('{bad'), isNull);
    });
  });

  group('parseInvoiceCreateResult', () {
    test('decodes the success body', () {
      const body = '{"id":"i-001","status":"created"}';
      final r = parseInvoiceCreateResult(body);
      expect(r, isA<InvoiceCreateSuccess>());
      final s = r as InvoiceCreateSuccess;
      expect(s.id, equals('i-001'));
      expect(s.status, equals('created'));
    });

    test('decodes the already_exists body', () {
      const body = '{"id":"i-002","status":"already_exists"}';
      final r = parseInvoiceCreateResult(body);
      expect(r, isA<InvoiceCreateSuccess>());
      expect((r as InvoiceCreateSuccess).status, equals('already_exists'));
    });

    test('decodes the FK-rejection body', () {
      const body = '{"error":"job_not_found","job_id":"j-missing"}';
      final r = parseInvoiceCreateResult(body);
      expect(r, isA<InvoiceCreateError>());
      final e = r as InvoiceCreateError;
      expect(e.kind, equals('job_not_found'));
      expect(e.jobId, equals('j-missing'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseInvoiceCreateResult('not json');
      expect(r, isA<InvoiceCreateError>());
      expect((r as InvoiceCreateError).kind, equals('parse_error'));
    });
  });

  group('parseInvoiceTransitionResult', () {
    test('decodes the success body (post-transition Invoice)', () {
      const body =
          '{"id":"i-001","job_id":"j-001","status":"sent",'
          '"amount":25000,"amount_paid":0,"external_invoice_id":"","notes":"",'
          '"sent_at":"2026-05-15T09:00:00Z","viewed_at":"","paid_at":"",'
          '"created_at":"2026-05-15T08:30:00Z","updated_at":"2026-05-15T09:00:00Z"}';
      final r = parseInvoiceTransitionResult(body);
      expect(r, isA<InvoiceTransitionSuccess>());
      expect((r as InvoiceTransitionSuccess).invoice.status, equals('sent'));
    });

    test('decodes the already_in_state body', () {
      const body =
          '{"status":"already_in_state","invoice":{"id":"i-001","job_id":"j-001",'
          '"status":"draft","amount":25000,"amount_paid":0,'
          '"external_invoice_id":"","notes":"",'
          '"sent_at":"","viewed_at":"","paid_at":"",'
          '"created_at":"2026-05-02T10:00:00Z","updated_at":"2026-05-02T10:00:00Z"}}';
      final r = parseInvoiceTransitionResult(body);
      expect(r, isA<InvoiceTransitionAlreadyInState>());
      expect((r as InvoiceTransitionAlreadyInState).invoice.status, equals('draft'));
    });

    test('decodes the typed not_reachable error body', () {
      const body =
          '{"error":"not_reachable","from":"draft","to":"paid","cap_required":null}';
      final r = parseInvoiceTransitionResult(body);
      expect(r, isA<InvoiceTransitionError>());
      final e = r as InvoiceTransitionError;
      expect(e.kind, equals('not_reachable'));
      expect(e.from, equals('draft'));
      expect(e.to, equals('paid'));
      expect(e.capRequired, isNull);
      expect(e.message, contains('Cannot transition'));
    });

    test('decodes the wrong_principal error body', () {
      const body =
          '{"error":"wrong_principal","from":"sent","to":"paid","cap_required":null}';
      final r = parseInvoiceTransitionResult(body);
      expect(r, isA<InvoiceTransitionError>());
      expect((r as InvoiceTransitionError).kind, equals('wrong_principal'));
    });

    test('returns parse_error for malformed responses', () {
      final r = parseInvoiceTransitionResult('not json');
      expect(r, isA<InvoiceTransitionError>());
      expect((r as InvoiceTransitionError).kind, equals('parse_error'));
    });
  });

  // D-O5.followup-4 client hooks — drive an in-memory HelmEventStream
  // and assert the repo surfaces both `invoice.created` AND
  // `invoice.transitioned` as InvoicesCacheEvents.
  group('InvoicesRepository cacheEvents', () {
    test('emits invoiceChanged when stream produces invoice.created',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['invoices'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = InvoicesRepository(_stubReplClient(), eventStream: stream);
      final received = <InvoicesCacheEvent>[];
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
      expect(received, hasLength(1));
      expect(received.first.invoiceId, equals('i-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('emits invoiceChanged when stream produces invoice.transitioned',
        () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['invoices'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = InvoicesRepository(_stubReplClient(), eventStream: stream);
      final received = <InvoicesCacheEvent>[];
      repo.cacheEvents.listen(received.add);

      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'invoice.transitioned',
          'data': {'id': 'i-001', 'from': 'sent', 'to': 'paid'},
        },
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, hasLength(1));
      expect(received.first.invoiceId, equals('i-001'));

      await repo.dispose();
      await stream.dispose();
    });

    test('ignores unrelated event types', () async {
      final ch = _FakeChannel();
      final stream = HelmEventStream(
        wssUrl: 'ws://example.test/api/v1/wallet',
        bearer: 'a' * 64,
        topics: const ['invoices'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = InvoicesRepository(_stubReplClient(), eventStream: stream);
      final received = <InvoicesCacheEvent>[];
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
        topics: const ['invoices'],
        channelFactory: (_) => ch,
      );
      await stream.connect();
      await Future<void>.delayed(Duration.zero);

      final repo = InvoicesRepository(_stubReplClient(), eventStream: stream);
      final received = <InvoicesCacheEvent>[];
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
      expect(received, hasLength(1));

      await repo.dispose();
      ch.serverSend(json.encode({
        'jsonrpc': '2.0',
        'method': 'helm.event',
        'params': {
          'type': 'invoice.created',
          'data': {'id': 'i-002'},
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
