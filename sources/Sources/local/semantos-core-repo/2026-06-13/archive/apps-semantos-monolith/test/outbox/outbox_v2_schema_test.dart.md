---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/outbox/outbox_v2_schema_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.906790+00:00
---

# archive/apps-semantos-monolith/test/outbox/outbox_v2_schema_test.dart

```dart
// W1.2 — outbox_v1 cell-envelope schema tests (red → green).
//
// The old outbox_v1 schema stored `payload_json TEXT` and
// `last_brain_state TEXT`.  W1.2 recreates the table with the
// cell-envelope shape:
//
//   outbox_v1(
//     id               INTEGER PRIMARY KEY AUTOINCREMENT,
//     cell_id          BLOB(32)        NOT NULL,
//     prev_state_hash  BLOB(32),
//     domain_flag      INTEGER         NOT NULL,
//     payload          BLOB,           -- 1024-byte cell envelope
//     created_at_ms    INTEGER         NOT NULL,
//     attempt_count    INTEGER         NOT NULL DEFAULT 0,
//     last_error       TEXT,
//     last_attempt_ms  INTEGER,
//     failure_reason   TEXT,
//     failure_message  TEXT,
//     failure_at_ms    INTEGER,
//     failure_count    INTEGER         NOT NULL DEFAULT 0
//   )
//
// Tests cover:
//   - new columns present (cell_id, prev_state_hash, domain_flag, payload);
//   - old columns absent (payload_json, last_brain_state);
//   - 1024-byte payload round-trips correctly;
//   - 32-byte cell_id BLOB round-trips;
//   - 32-byte prev_state_hash BLOB round-trips (nullable);
//   - domain_flag NOT NULL enforced;
//   - existing enqueue / peek / dequeue / count semantics preserved.

import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/outbox/outbox_db.dart';

Future<OutboxDb> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return OutboxDb.fromDatabase(db);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('outbox_v1 cell-envelope schema (W1.2)', () {
    test('new columns are present: cell_id, prev_state_hash, domain_flag, payload',
        () async {
      final db = await _openInMemory();
      // PRAGMA table_info returns one row per column.
      final info =
          await db.rawQuery("PRAGMA table_info('outbox_v1')");
      final cols = info.map((r) => r['name'] as String).toSet();
      expect(cols, contains('cell_id'));
      expect(cols, contains('prev_state_hash'));
      expect(cols, contains('domain_flag'));
      expect(cols, contains('payload'));
      await db.close();
    });

    test('old columns are absent: payload_json, last_brain_state', () async {
      final db = await _openInMemory();
      final info =
          await db.rawQuery("PRAGMA table_info('outbox_v1')");
      final cols = info.map((r) => r['name'] as String).toSet();
      expect(cols, isNot(contains('payload_json')));
      expect(cols, isNot(contains('last_brain_state')));
      await db.close();
    });

    test('1024-byte payload blob round-trips correctly', () async {
      final db = await _openInMemory();

      final cellId = Uint8List(32)..fillRange(0, 32, 0xAB);
      final payload = Uint8List(1024);
      for (var i = 0; i < 1024; i++) {
        payload[i] = i & 0xFF;
      }

      final id = await db.enqueue(
        cellId: cellId,
        domainFlag: 0x000101,
        payload: payload,
      );

      final rows = await db.peek();
      expect(rows, hasLength(1));
      expect(rows.first.id, equals(id));

      final gotPayload = rows.first.payload;
      expect(gotPayload, isNotNull);
      expect(gotPayload!.length, equals(1024));
      for (var i = 0; i < 1024; i++) {
        expect(gotPayload[i], equals(i & 0xFF),
            reason: 'payload byte $i mismatch');
      }
      await db.close();
    });

    test('32-byte cell_id BLOB round-trips correctly', () async {
      final db = await _openInMemory();

      final cellId = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        cellId[i] = i;
      }

      await db.enqueue(
        cellId: cellId,
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );

      final rows = await db.peek();
      final gotCellId = rows.first.cellId;
      expect(gotCellId.length, equals(32));
      for (var i = 0; i < 32; i++) {
        expect(gotCellId[i], equals(i));
      }
      await db.close();
    });

    test('prev_state_hash is nullable and round-trips when set', () async {
      final db = await _openInMemory();

      final cellId = Uint8List(32)..fillRange(0, 32, 1);
      final prevHash = Uint8List(32)..fillRange(0, 32, 0xFF);

      // Without prev_state_hash.
      await db.enqueue(
        cellId: cellId,
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );
      final rowsNull = await db.peek();
      expect(rowsNull.first.prevStateHash, isNull);
      await db.dequeue(rowsNull.first.id);

      // With prev_state_hash.
      await db.enqueue(
        cellId: cellId,
        domainFlag: 0x000101,
        payload: Uint8List(1024),
        prevStateHash: prevHash,
      );
      final rowsSet = await db.peek();
      final got = rowsSet.first.prevStateHash;
      expect(got, isNotNull);
      expect(got!.length, equals(32));
      expect(got.every((b) => b == 0xFF), isTrue);
      await db.close();
    });

    test('domain_flag is stored and retrieved correctly', () async {
      final db = await _openInMemory();

      await db.enqueue(
        cellId: Uint8List(32),
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );

      final rows = await db.peek();
      expect(rows.first.domainFlag, equals(0x000101));
      await db.close();
    });

    test('enqueue / peek / dequeue / count semantics preserved', () async {
      final db = await _openInMemory();

      expect(await db.count(), equals(0));

      final id1 = await db.enqueue(
        cellId: Uint8List(32)..fillRange(0, 32, 1),
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final id2 = await db.enqueue(
        cellId: Uint8List(32)..fillRange(0, 32, 2),
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );

      expect(await db.count(), equals(2));

      final rows = await db.peek();
      expect(rows, hasLength(2));
      expect(rows[0].id, equals(id1));
      expect(rows[1].id, equals(id2));

      await db.dequeue(id1);
      expect(await db.count(), equals(1));

      await db.close();
    });

    test('recordFailure increments attempt_count', () async {
      final db = await _openInMemory();

      final id = await db.enqueue(
        cellId: Uint8List(32),
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );

      await db.recordFailure(id: id, error: 'timeout');
      await db.recordFailure(id: id, error: 'timeout again');

      final rows = await db.peek();
      expect(rows.first.attemptCount, equals(2));
      expect(rows.first.lastError, equals('timeout again'));
      await db.close();
    });

    test('typed failure round-trips (recordTypedFailure + peekFailed)', () async {
      final db = await _openInMemory();

      final id = await db.enqueue(
        cellId: Uint8List(32)..fillRange(0, 32, 0xCA),
        domainFlag: 0x000101,
        payload: Uint8List(1024),
      );

      await db.recordTypedFailure(
        id: id,
        kind: OutboxFailureKind.hashMismatch,
        message: 'bad bytes',
      );

      final failed = await db.peekFailed();
      expect(failed, hasLength(1));
      expect(failed.first.kind, equals(OutboxFailureKind.hashMismatch));
      expect(failed.first.message, equals('bad bytes'));
      // lastBrainState no longer exists — confirm there is no such field.
      expect(failed.first, isA<OutboxFailedEntry>());
      await db.close();
    });
  });
}

```
