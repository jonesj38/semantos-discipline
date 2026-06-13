---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/outbox/outbox_db_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.907670+00:00
---

# archive/apps-semantos-monolith/test/outbox/outbox_db_test.dart

```dart
// W1.2 — outbox_db.dart conformance test (cell-envelope schema).
//
// Exercises:
//   - schema creation (drop + recreate on fromDatabase);
//   - enqueue → peek (FIFO order) with cell-envelope fields;
//   - dequeue removes the row;
//   - recordFailure increments attempt_count + records last_error;
//   - count() returns the right depth;
//   - typed failure round-trips;
//   - flush-on-reconnect skeleton via OutboxService (mocked ReplClient).
//
// Backed by sqflite_common_ffi so the test runs under plain
// `dart test` without a Flutter SDK gate.

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db =
      await factory.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions());
  return OutboxDb.fromDatabase(db);
}

Uint8List _cellId(int fill) => Uint8List(32)..fillRange(0, 32, fill);
Uint8List _payload() => Uint8List(1024);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('OutboxDb (W1.2 cell-envelope schema)', () {
    test('schema creation produces new cell-envelope columns', () async {
      final db = await _openInMemory();
      expect(await db.count(), equals(0));
      await db.close();
    });

    test('enqueue + peek returns FIFO order with cell-envelope fields', () async {
      final db = await _openInMemory();
      final id1 = await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final id2 = await db.enqueue(
        cellId: _cellId(0x02),
        domainFlag: 0x000101,
        payload: _payload(),
      );

      final rows = await db.peek();
      expect(rows, hasLength(2));
      expect(rows[0].id, equals(id1));
      expect(rows[0].cellId[0], equals(0x01));
      expect(rows[0].domainFlag, equals(0x000101));
      expect(rows[0].payload, isNotNull);
      expect(rows[0].payload!.length, equals(1024));
      expect(rows[0].attemptCount, equals(0));
      expect(rows[1].id, equals(id2));

      await db.close();
    });

    test('dequeue removes a single row', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0xAA),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      expect(await db.count(), equals(1));
      final removed = await db.dequeue(id);
      expect(removed, equals(1));
      expect(await db.count(), equals(0));
      await db.close();
    });

    test('recordFailure increments attempt_count + writes last_error',
        () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0xBB),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.recordFailure(id: id, error: 'simulated 503');
      await db.recordFailure(id: id, error: 'still 503');
      final rows = await db.peek();
      expect(rows, hasLength(1));
      expect(rows.first.attemptCount, equals(2));
      expect(rows.first.lastError, equals('still 503'));
      expect(rows.first.lastAttemptMs, isNotNull);
      await db.close();
    });

    test('prevStateHash nullable — round-trips when set', () async {
      final db = await _openInMemory();
      final prevHash = Uint8List(32)..fillRange(0, 32, 0xFF);

      final id = await db.enqueue(
        cellId: _cellId(0xCC),
        domainFlag: 0x000101,
        payload: _payload(),
        prevStateHash: prevHash,
      );

      final rows = await db.peek();
      expect(rows.first.prevStateHash, isNotNull);
      expect(rows.first.prevStateHash![0], equals(0xFF));

      await db.dequeue(id);
      await db.close();
    });

    test('recordTypedFailure persists kind + message + count', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0xDD),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.stateMovedOn,
        message: 'job advanced',
      );
      final entry = (await db.peek()).first;
      expect(entry.failureReason, equals(OutboxFailureKind.stateMovedOn));
      expect(entry.failureMessage, equals('job advanced'));
      expect(entry.failureCount, equals(1));
      expect(entry.failureAtMs, isNotNull);
      expect(entry.hasFailed, isTrue);
      await db.close();
    });

    test('recordTypedFailure increments failureCount on each call', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0xEE),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.recordTypedFailure(id: id, kind: OutboxFailureKind.networkError);
      await db.recordTypedFailure(id: id, kind: OutboxFailureKind.networkError);
      await db.recordTypedFailure(id: id, kind: OutboxFailureKind.networkError);
      final entry = (await db.peek()).first;
      expect(entry.failureCount, equals(3));
      expect(entry.attemptCount, greaterThanOrEqualTo(3));
      await db.close();
    });

    test('clearFailure resets failure_count + clears typed metadata', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0xFF),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.stateMovedOn,
        message: 'oops',
      );
      await db.clearFailure(id);
      final entry = (await db.peek()).first;
      expect(entry.failureReason, isNull);
      expect(entry.failureMessage, isNull);
      expect(entry.failureCount, equals(0));
      expect(entry.hasFailed, isFalse);
      await db.close();
    });

    test('peekFailed returns only entries with a recorded failure', () async {
      final db = await _openInMemory();
      final failedId = await db.enqueue(
        cellId: _cellId(0x11),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.enqueue(
        cellId: _cellId(0x22),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await db.recordTypedFailure(
        id: failedId,
        kind: OutboxFailureKind.hashMismatch,
        message: 'bad bytes',
      );
      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.entry.id, equals(failedId));
      expect(failed.first.kind, equals(OutboxFailureKind.hashMismatch));
      expect(failed.first.message, equals('bad bytes'));
      expect(await db.failedCount(), equals(1));
      expect(await db.count(), equals(2));
      await db.close();
    });

    test('OutboxFailedEntry.fromEntry returns null for pristine entries',
        () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x33),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      final entry = (await db.peek()).first;
      expect(OutboxFailedEntry.fromEntry(entry), isNull);
      await db.close();
    });
  });

  group('OutboxService.flush (W1.2)', () {
    test('happy path: every entry pushed through REPL is dequeued', () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.enqueue(
        cellId: _cellId(0x02),
        domainFlag: 0x000101,
        payload: _payload(),
      );

      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 200,
          body: utf8Encode('{"result":"ok","exit":"continue"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);

      // Adapter: serialize the cell-id bytes as a REPL command stub.
      final summary = await svc.flush(
        (entry) => 'sync-cell ${entry.domainFlag}',
      );

      expect(summary.succeeded, equals(2));
      expect(summary.unauthorised, isFalse);
      expect(summary.validationFailed, equals(0));
      expect(summary.retryable, equals(0));
      expect(await db.count(), equals(0));

      await db.close();
    });

    test('401 from REPL halts flush + signals unauthorised=true', () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.enqueue(
        cellId: _cellId(0x02),
        domainFlag: 0x000101,
        payload: _payload(),
      );

      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 401,
          body: utf8Encode('{"error":"bearer rejected"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);
      final summary = await svc.flush((entry) => 'noop');
      expect(summary.unauthorised, isTrue);
      expect(summary.succeeded, equals(0));
      expect(await db.count(), equals(2));
      await db.close();
    });

    test('400 leaves entry queued + records failure', () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );

      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 400,
          body: utf8Encode('{"error":"unknown verb"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);
      final summary = await svc.flush((entry) => 'noop');
      expect(summary.validationFailed, equals(1));
      final rows = await db.peek();
      expect(rows, hasLength(1));
      expect(rows.first.attemptCount, equals(1));
      expect(rows.first.lastError, contains('unknown verb'));
      await db.close();
    });

    test('400 with hash_mismatch maps to OutboxFailureKind.hashMismatch',
        () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );

      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 400,
          body: utf8Encode('{"error":"hash_mismatch"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);
      await svc.flush((entry) => 'noop');

      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.hashMismatch));
      await db.close();
    });

    test('400 with not_reachable maps to stateMovedOn', () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 400,
          body: utf8Encode(
              '{"error":"not_reachable","from":"in_progress","to":"quoted"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);
      final summary = await svc.flush((entry) => 'transition');
      expect(summary.stateMovedOn, equals(1));
      expect(summary.validationFailed, equals(0));
      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.stateMovedOn));
      await db.close();
    });

    test('401 records typed unauthorised failure on the failing entry',
        () async {
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 401,
          body: utf8Encode('{"error":"bearer_invalid"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);
      final summary = await svc.flush((entry) => 'noop');
      expect(summary.unauthorised, isTrue);
      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.unauthorised));
      await db.close();
    });

    test('failedEntries stream emits on flush + retry', () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 400,
          body: utf8Encode('{"error":"hash_mismatch"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'https://oddjobtodd.info',
        bearer: 'b' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);

      final emissionsFuture = svc.failedEntries.take(3).toList();

      await svc.flush((entry) => 'noop');
      await svc.retry(id);
      final emissions = await emissionsFuture;
      expect(emissions, hasLength(3));
      expect(emissions[1].length, equals(1));
      expect(emissions[2].length, equals(0));
      await svc.dispose();
      await db.close();
    });

    test('retry clears failure metadata; discard removes entry entirely',
        () async {
      final db = await _openInMemory();
      final id = await db.enqueue(
        cellId: _cellId(0x01),
        domainFlag: 0x000101,
        payload: _payload(),
      );
      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.networkError,
      );
      final svc = OutboxService(
        db: db,
        repl: ReplClient.withBearer(
          http: Dio(),
          baseUrl: 'https://oddjobtodd.info',
          bearer: 'b' * 64,
        ),
      );

      await svc.retry(id);
      final afterRetry = await db.peek();
      expect(afterRetry, hasLength(1));
      expect(afterRetry.first.failureReason, isNull);
      expect(afterRetry.first.failureCount, equals(0));

      await svc.discard(id);
      expect(await db.count(), equals(0));
      await svc.dispose();
      await db.close();
    });
  });
}

// ─── helpers ─────────────────────────────────────────────────────────

List<int> utf8Encode(String s) => s.codeUnits;

class _StaticAdapter implements HttpClientAdapter {
  final int statusCode;
  final List<int> body;
  _StaticAdapter({required this.statusCode, required this.body});

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromBytes(body, statusCode, headers: const {
      Headers.contentTypeHeader: ['application/json'],
    });
  }
}

```
