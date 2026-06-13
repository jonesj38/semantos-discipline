---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/outbox/outbox_service_flush_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.907382+00:00
---

# archive/apps-semantos-monolith/test/outbox/outbox_service_flush_test.dart

```dart
// Tier 2P Phase A — OutboxService.flush unit tests.
//
// Exercises the periodic-flush path wired up by AuthRouter + HomeScreen:
//   1. Queued cell is flushed (dequeued) when flush() is called and the
//      REPL client succeeds.
//   2. Queued cell is retained and failure recorded when the REPL client
//      returns a network error.
//   3. flush() with a null-returning adapter skips entries (they stay
//      queued, no attempt recorded).
//
// W1.2 — enqueue() now takes cellId/domainFlag/payload.  The flush
// adapter is updated to decode the payload bytes as a UTF-8 command
// string, mirroring the production adapter in home_screen.dart.
//
// Uses sqflite_common_ffi + a Dio HttpClientAdapter stub so the tests
// run under `dart test` without a Flutter SDK gate, matching the pattern
// established in outbox_db_test.dart and outbox_service_mesh_test.dart.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';
import 'package:semantos/src/repl/repl_client.dart';

// ─── helpers ─────────────────────────────────────────────────────────

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions());
  return OutboxDb.fromDatabase(db);
}

List<int> _utf8Bytes(String s) => s.codeUnits;

Uint8List _cellId32(String s) {
  final b = utf8.encode(s);
  final out = Uint8List(32);
  out.setRange(0, b.length.clamp(0, 32), b);
  return out;
}

/// A static Dio adapter that returns the same status code + body for
/// every request.  Mirrors the _StaticAdapter in outbox_db_test.dart.
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
  ) async =>
      ResponseBody.fromBytes(body, statusCode, headers: const {
        Headers.contentTypeHeader: ['application/json'],
      });
}

// ─── tests ────────────────────────────────────────────────────────────

void main() {
  setUpAll(sqfliteFfiInit);

  group('OutboxService.flush — Tier 2P Phase A (W1.2)', () {
    test(
        'queued cell is dequeued on REPL success (flush adapter decodes '
        'payload bytes as command)', () async {
      // Arrange: one queued entry with a cell-envelope payload.
      final db = await _openInMemory();
      const cmd = 'set-job-state --id job-42 --state quoted';
      await db.enqueue(
        cellId: _cellId32('job-42'),
        domainFlag: 0x000101,
        payload: Uint8List.fromList(utf8.encode(cmd)),
      );

      final dio = Dio()
        ..httpClientAdapter = _StaticAdapter(
          statusCode: 200,
          body: _utf8Bytes('{"result":"ok","exit":"continue"}'),
        );
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'http://brain.test',
        bearer: '0' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);

      // Act: flush adapter decodes payload bytes as a REPL command string.
      final summary = await svc.flush(
          (entry) => entry.payload != null ? utf8.decode(entry.payload!) : null);

      // Assert: entry dequeued, summary reports success.
      expect(summary.succeeded, equals(1));
      expect(summary.retryable, equals(0));
      expect(summary.unauthorised, isFalse);
      expect(await db.count(), equals(0),
          reason: 'successfully flushed entry must be removed from the queue');

      await svc.dispose();
      await db.close();
    });

    test(
        'queued cell is retained and networkError recorded when REPL is '
        'unreachable (DioException)', () async {
      // Arrange: one queued entry.
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId32('job-99'),
        domainFlag: 0x000101,
        payload: Uint8List.fromList(utf8.encode('{"id":"job-99"}')),
      );

      // Simulate a network failure: Dio throws a DioException for
      // every request.  We use a custom adapter that always throws.
      final dio = Dio()..httpClientAdapter = _ErrorAdapter();
      final repl = ReplClient.withBearer(
        http: dio,
        baseUrl: 'http://brain.test',
        bearer: '0' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);

      // Act.
      final summary = await svc.flush(
          (entry) => entry.payload != null ? utf8.decode(entry.payload!) : null);

      // Assert: entry retained, failure recorded.
      expect(summary.succeeded, equals(0));
      expect(summary.retryable, equals(1),
          reason: 'DioException must map to a retryable network error');
      expect(await db.count(), equals(1),
          reason: 'entry must stay queued on network failure');
      final entries = await db.peek();
      expect(entries.first.attemptCount, equals(1),
          reason: 'attempt_count must be incremented');
      expect(entries.first.lastError, isNotNull,
          reason: 'last_error must record the failure message');

      await svc.dispose();
      await db.close();
    });

    test(
        'flush with null-returning adapter skips entry (queue depth unchanged, '
        'no failure recorded)', () async {
      // Arrange: one queued entry.
      final db = await _openInMemory();
      await db.enqueue(
        cellId: _cellId32('job-1'),
        domainFlag: 0x000101,
        payload: Uint8List.fromList(utf8.encode('{"id":"job-1"}')),
      );

      final repl = ReplClient.withBearer(
        http: Dio(),
        baseUrl: 'http://brain.test',
        bearer: '0' * 64,
      );
      final svc = OutboxService(db: db, repl: repl);

      // Act: adapter returns null → entry is skipped entirely.
      final summary = await svc.flush((_) => null);

      // Assert: entry stays queued, no failure recorded.
      expect(summary.succeeded, equals(0));
      expect(summary.retryable, equals(0));
      expect(await db.count(), equals(1));
      final entry = (await db.peek()).first;
      expect(entry.attemptCount, equals(0),
          reason: 'skipped entries must not have their attempt_count bumped');
      expect(entry.lastError, isNull);

      await svc.dispose();
      await db.close();
    });
  });
}

/// A Dio adapter that always throws a [DioException] (simulates total
/// network failure / connection refused).
class _ErrorAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      message: 'connection refused (stub)',
    );
  }
}

```
