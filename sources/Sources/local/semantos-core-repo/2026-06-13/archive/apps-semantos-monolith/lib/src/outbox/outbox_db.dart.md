---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/outbox/outbox_db.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.863250+00:00
---

# archive/apps-semantos-monolith/lib/src/outbox/outbox_db.dart

```dart
// W1.2 — Outbox queue DB — cell-envelope schema.
//
// The outbox_v1 table is recreated with the canonical cell-envelope shape.
// No data migration: this is a prototype; any existing rows are dropped.
//
// Schema:
//
//   outbox_v1(
//     id               INTEGER PRIMARY KEY AUTOINCREMENT,
//     cell_id          BLOB(32)        NOT NULL,   -- 32-byte cell identity
//     prev_state_hash  BLOB(32),                   -- prior snapshot hash (W1.2)
//     domain_flag      INTEGER         NOT NULL,   -- hat domain e.g. 0x000101
//     payload          BLOB,                       -- 1024-byte cell envelope
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
// Replacing the old columns:
//   cell_type    TEXT    → carried inside the 1024-byte payload envelope
//   payload_json TEXT    → superseded by payload BLOB
//   blob_path    TEXT    → obsolete; attachment blobs now inline or cell-ref'd
//   last_brain_state TEXT → renamed prev_state_hash BLOB(32)
//
// Why sqflite: the sqflite_common_ffi backend works under `dart test`
// (no Flutter SDK gate); production uses sqflite's MethodChannel
// adapter on iOS + Android. Both are SQLite under the hood.

import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

const String outboxTable = 'outbox_v1';

// Drop-and-recreate DDL — no migration needed (prototype, no prod data).
const String _dropDdl = 'DROP TABLE IF EXISTS outbox_v1';

const String _ddl = '''
  CREATE TABLE IF NOT EXISTS outbox_v1 (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    cell_id          BLOB    NOT NULL,
    prev_state_hash  BLOB,
    domain_flag      INTEGER NOT NULL,
    payload          BLOB,
    created_at_ms    INTEGER NOT NULL,
    attempt_count    INTEGER NOT NULL DEFAULT 0,
    last_error       TEXT,
    last_attempt_ms  INTEGER,
    failure_reason   TEXT,
    failure_message  TEXT,
    failure_at_ms    INTEGER,
    failure_count    INTEGER NOT NULL DEFAULT 0
  )
''';

const String _idxCreatedAt = '''
  CREATE INDEX IF NOT EXISTS outbox_v1_created_at_idx
    ON outbox_v1 (created_at_ms)
''';

/// Typed failure kinds — stable wire-form strings persisted in
/// `failure_reason`.  Unchanged from the pre-W1.2 schema so the
/// conflict screen's kind → message mapping still applies.
enum OutboxFailureKind {
  networkError('network_error'),
  hashMismatch('hash_mismatch'),
  signatureInvalid('signature_invalid'),
  certUnknown('cert_unknown'),
  visitNotFound('visit_not_found'),

  /// K1 conflict — job state advanced on the brain while the phone
  /// held an offline transition.  The `prev_state_hash` column now
  /// carries the prior hash rather than a human-readable state name.
  stateMovedOn('state_moved_on'),

  replay('replay'),
  validationFailed('validation_failed'),
  unauthorised('unauthorised');

  final String wire;
  const OutboxFailureKind(this.wire);

  static OutboxFailureKind fromWire(String? wire) {
    if (wire == null) return OutboxFailureKind.validationFailed;
    for (final k in OutboxFailureKind.values) {
      if (k.wire == wire) return k;
    }
    return OutboxFailureKind.validationFailed;
  }
}

/// Single queued outbox entry — cell-envelope shape.
class OutboxEntry {
  final int id;

  /// 32-byte cell identity BLOB.
  final Uint8List cellId;

  /// Prior snapshot hash (32 bytes), or null when none.
  final Uint8List? prevStateHash;

  /// Hat domain flag (e.g. 0x000101 for oddjobz).
  final int domainFlag;

  /// 1024-byte cell envelope, or null when the row was created without
  /// a full envelope (development only).
  final Uint8List? payload;

  final int createdAtMs;
  final int attemptCount;
  final String? lastError;
  final int? lastAttemptMs;

  final OutboxFailureKind? failureReason;
  final String? failureMessage;
  final int? failureAtMs;
  final int failureCount;

  const OutboxEntry({
    required this.id,
    required this.cellId,
    required this.domainFlag,
    this.prevStateHash,
    this.payload,
    required this.createdAtMs,
    required this.attemptCount,
    this.lastError,
    this.lastAttemptMs,
    this.failureReason,
    this.failureMessage,
    this.failureAtMs,
    this.failureCount = 0,
  });

  bool get hasFailed => failureReason != null;

  static Uint8List _toBytes(Object? raw) {
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return Uint8List(0);
  }

  static OutboxEntry fromRow(Map<String, Object?> row) => OutboxEntry(
        id: row['id'] as int,
        cellId: _toBytes(row['cell_id']),
        prevStateHash: row['prev_state_hash'] == null
            ? null
            : _toBytes(row['prev_state_hash']),
        domainFlag: row['domain_flag'] as int,
        payload: row['payload'] == null ? null : _toBytes(row['payload']),
        createdAtMs: row['created_at_ms'] as int,
        attemptCount: row['attempt_count'] as int,
        lastError: row['last_error'] as String?,
        lastAttemptMs: row['last_attempt_ms'] as int?,
        failureReason: row['failure_reason'] == null
            ? null
            : OutboxFailureKind.fromWire(row['failure_reason'] as String),
        failureMessage: row['failure_message'] as String?,
        failureAtMs: row['failure_at_ms'] as int?,
        failureCount: (row['failure_count'] as int?) ?? 0,
      );
}

/// Failed-entry projection consumed by the conflicts screen.
class OutboxFailedEntry {
  final OutboxEntry entry;
  final OutboxFailureKind kind;
  final String? message;
  final DateTime failedAt;
  final int failureCount;

  const OutboxFailedEntry({
    required this.entry,
    required this.kind,
    required this.message,
    required this.failedAt,
    required this.failureCount,
  });

  static OutboxFailedEntry? fromEntry(OutboxEntry entry) {
    final kind = entry.failureReason;
    if (kind == null) return null;
    final atMs = entry.failureAtMs ?? entry.lastAttemptMs ?? entry.createdAtMs;
    return OutboxFailedEntry(
      entry: entry,
      kind: kind,
      message: entry.failureMessage,
      failedAt: DateTime.fromMillisecondsSinceEpoch(atMs),
      failureCount: entry.failureCount,
    );
  }
}

/// Owns the outbox DB connection.
class OutboxDb {
  final Database _db;
  OutboxDb._(this._db);

  /// Expose raw DB for callers that need PRAGMA queries (e.g. tests).
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? args]) async {
    return _db.rawQuery(sql, args);
  }

  /// Open the schema on [db].  Drops the old table and recreates it
  /// with the W1.2 cell-envelope shape (no migration — prototype only).
  static Future<OutboxDb> fromDatabase(Database db) async {
    await db.execute(_dropDdl);
    await db.execute(_ddl);
    await db.execute(_idxCreatedAt);
    return OutboxDb._(db);
  }

  /// Enqueue a new cell-envelope entry. Returns the auto-generated id.
  Future<int> enqueue({
    required Uint8List cellId,
    required int domainFlag,
    Uint8List? payload,
    Uint8List? prevStateHash,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.insert(outboxTable, {
      'cell_id': cellId,
      'prev_state_hash': prevStateHash,
      'domain_flag': domainFlag,
      'payload': payload,
      'created_at_ms': now,
      'attempt_count': 0,
      'failure_count': 0,
    });
  }

  /// Read pending entries in FIFO order, up to [limit].
  Future<List<OutboxEntry>> peek({int limit = 100}) async {
    final rows = await _db.query(
      outboxTable,
      orderBy: 'created_at_ms ASC, id ASC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromRow).toList();
  }

  /// Read entries with a recorded typed failure (most-recent first).
  Future<List<OutboxFailedEntry>> peekFailed({int limit = 100}) async {
    final rows = await _db.query(
      outboxTable,
      where: 'failure_reason IS NOT NULL',
      orderBy: 'failure_at_ms DESC, id DESC',
      limit: limit,
    );
    return rows
        .map(OutboxEntry.fromRow)
        .map(OutboxFailedEntry.fromEntry)
        .whereType<OutboxFailedEntry>()
        .toList();
  }

  /// Remove a successfully-flushed entry.
  Future<int> dequeue(int id) async {
    return _db.delete(outboxTable, where: 'id = ?', whereArgs: [id]);
  }

  /// Increment attempt_count + record last_error. Entry stays queued.
  Future<int> recordFailure({
    required int id,
    required String error,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = await _db.query(
      outboxTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isEmpty) return 0;
    final attempt = (row.first['attempt_count'] as int) + 1;
    return _db.update(
      outboxTable,
      {
        'attempt_count': attempt,
        'last_error': error,
        'last_attempt_ms': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Record a typed K1 conflict failure. Writes the kind + message +
  /// increments failure_count. The conflicts screen reads these fields.
  ///
  /// [prevStateHash] replaces the old `lastBrainState` TEXT parameter.
  /// Callers that previously passed a state-name string should pass the
  /// 32-byte hash of the brain's current snapshot instead, or null when
  /// the hash is not available at the call site.
  Future<int> recordTypedFailure({
    required int id,
    required OutboxFailureKind kind,
    String? message,
    Uint8List? prevStateHash,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = await _db.query(
      outboxTable,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (row.isEmpty) return 0;
    final attempt = (row.first['attempt_count'] as int) + 1;
    final failureCount = ((row.first['failure_count'] as int?) ?? 0) + 1;
    return _db.update(
      outboxTable,
      {
        'attempt_count': attempt,
        'last_error': message ?? kind.wire,
        'last_attempt_ms': now,
        'failure_reason': kind.wire,
        'failure_message': message,
        'failure_at_ms': now,
        'failure_count': failureCount,
        'prev_state_hash': prevStateHash,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Clear typed-failure metadata, resetting failure_count to 0.
  Future<int> clearFailure(int id) async {
    return _db.update(
      outboxTable,
      {
        'failure_reason': null,
        'failure_message': null,
        'failure_at_ms': null,
        'failure_count': 0,
        'prev_state_hash': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Total queue depth.
  Future<int> count() async {
    final rows = await _db.rawQuery('SELECT COUNT(*) AS c FROM $outboxTable');
    final c = rows.first['c'];
    return (c is int) ? c : (c as num).toInt();
  }

  /// Count of entries with a typed failure recorded.
  Future<int> failedCount() async {
    final rows = await _db.rawQuery(
        'SELECT COUNT(*) AS c FROM $outboxTable WHERE failure_reason IS NOT NULL');
    final c = rows.first['c'];
    return (c is int) ? c : (c as num).toInt();
  }

  /// Close the underlying connection.
  Future<void> close() => _db.close();
}

```
