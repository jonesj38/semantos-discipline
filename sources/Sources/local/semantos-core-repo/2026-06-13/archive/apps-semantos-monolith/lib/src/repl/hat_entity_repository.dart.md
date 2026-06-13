---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/hat_entity_repository.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.879722+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/hat_entity_repository.dart

```dart
// W1.1 — HatEntityRepository: universal SQLite-backed entity cache.
//
// Replaces the file-based `jobs_cache_<url>.json` pattern with a
// single `hat_entity_cache` table that works for any hat (domain_flag).
//
// Schema:
//   hat_entity_cache(
//     id          TEXT    NOT NULL,
//     domain_flag INTEGER NOT NULL,
//     state       TEXT,
//     scheduled_at TEXT,
//     entity_json TEXT,
//     updated_at  TEXT,
//     PRIMARY KEY (id, domain_flag)
//   )
//
// Indices:
//   (domain_flag, state)        — queryByState hot path
//   (domain_flag, scheduled_at) — queryByScheduledAt / calendar hot path
//
// Why sqflite_common: the sqflite_common_ffi backend runs under
// `dart test` without a Flutter SDK gate; production uses sqflite's
// MethodChannel adapter on iOS + Android. Both share the same DDL.

import 'package:sqflite_common/sqlite_api.dart';

const String _table = 'hat_entity_cache';

const String _ddl = '''
  CREATE TABLE IF NOT EXISTS hat_entity_cache (
    id           TEXT    NOT NULL,
    domain_flag  INTEGER NOT NULL,
    state        TEXT,
    scheduled_at TEXT,
    entity_json  TEXT,
    updated_at   TEXT,
    PRIMARY KEY (id, domain_flag)
  )
''';

const String _idxState = '''
  CREATE INDEX IF NOT EXISTS hat_entity_cache_domain_state_idx
    ON hat_entity_cache (domain_flag, state)
''';

const String _idxScheduledAt = '''
  CREATE INDEX IF NOT EXISTS hat_entity_cache_domain_sched_idx
    ON hat_entity_cache (domain_flag, scheduled_at)
''';

/// One row of the universal hat entity cache.
class HatEntity {
  final String id;
  final int domainFlag;
  final String state;
  final String scheduledAt;
  final String entityJson;
  final String updatedAt;

  const HatEntity({
    required this.id,
    required this.domainFlag,
    required this.state,
    required this.scheduledAt,
    required this.entityJson,
    required this.updatedAt,
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'domain_flag': domainFlag,
        'state': state,
        'scheduled_at': scheduledAt,
        'entity_json': entityJson,
        'updated_at': updatedAt,
      };

  static HatEntity fromRow(Map<String, Object?> row) => HatEntity(
        id: row['id'] as String,
        domainFlag: row['domain_flag'] as int,
        state: (row['state'] as String?) ?? '',
        scheduledAt: (row['scheduled_at'] as String?) ?? '',
        entityJson: (row['entity_json'] as String?) ?? '',
        updatedAt: (row['updated_at'] as String?) ?? '',
      );
}

/// SQLite-backed repository for the universal hat entity cache.
///
/// Construct via [HatEntityRepository.fromDatabase]. Pass a
/// pre-opened [Database] (production or in-memory FFI for tests).
///
/// All queries are scoped to [domainFlag] so multiple hats can share
/// the same table without interference.
class HatEntityRepository {
  final Database _db;

  HatEntityRepository._(this._db);

  /// Open (or migrate) the schema on an existing [db] connection and
  /// return a ready [HatEntityRepository].
  static Future<HatEntityRepository> fromDatabase(Database db) async {
    await db.execute(_ddl);
    await db.execute(_idxState);
    await db.execute(_idxScheduledAt);
    return HatEntityRepository._(db);
  }

  // ── Writes ──────────────────────────────────────────────────────────

  /// Insert or replace a row (keyed by id + domain_flag).
  Future<void> upsert(HatEntity entity) async {
    await _db.insert(
      _table,
      entity.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Delete a row by id + domain_flag. Returns the number of rows
  /// deleted (0 if absent, 1 if present).
  Future<int> delete({required String id, required int domainFlag}) async {
    return _db.delete(
      _table,
      where: 'id = ? AND domain_flag = ?',
      whereArgs: [id, domainFlag],
    );
  }

  // ── Reads ────────────────────────────────────────────────────────────

  /// Return all rows for [domainFlag], ordered by updated_at DESC.
  Future<List<HatEntity>> queryAll({required int domainFlag}) async {
    final rows = await _db.query(
      _table,
      where: 'domain_flag = ?',
      whereArgs: [domainFlag],
      orderBy: 'updated_at DESC',
    );
    return rows.map(HatEntity.fromRow).toList();
  }

  /// Return rows matching [state] for [domainFlag].
  /// Uses the (domain_flag, state) index.
  Future<List<HatEntity>> queryByState({
    required int domainFlag,
    required String state,
  }) async {
    final rows = await _db.query(
      _table,
      where: 'domain_flag = ? AND state = ?',
      whereArgs: [domainFlag, state],
      orderBy: 'updated_at DESC',
    );
    return rows.map(HatEntity.fromRow).toList();
  }

  /// Return rows matching [scheduledAt] for [domainFlag].
  /// Uses the (domain_flag, scheduled_at) index.
  Future<List<HatEntity>> queryByScheduledAt({
    required int domainFlag,
    required String scheduledAt,
  }) async {
    final rows = await _db.query(
      _table,
      where: 'domain_flag = ? AND scheduled_at = ?',
      whereArgs: [domainFlag, scheduledAt],
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(HatEntity.fromRow).toList();
  }

  /// Return conversation cells (entity_json containing '"mode":') for
  /// [domainFlag], ordered by updated_at DESC.
  ///
  /// Conversation cells are identified by the presence of a 'mode' key
  /// in their entity_json (values: self/direct/squad/agent/broadcast).
  /// This avoids a separate table or schema migration for W0 scope.
  /// A dedicated entity_tag column (M-level) will replace this filter.
  Future<List<HatEntity>> queryConversations({
    required int domainFlag,
    int limit = 50,
  }) async {
    final rows = await _db.query(
      _table,
      where: "domain_flag = ? AND entity_json LIKE '%\"mode\":%'",
      whereArgs: [domainFlag],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(HatEntity.fromRow).toList();
  }

  /// Total row count for [domainFlag].
  Future<int> count({required int domainFlag}) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE domain_flag = ?',
      [domainFlag],
    );
    final c = rows.first['c'];
    return (c is int) ? c : (c as num).toInt();
  }

  /// Close the underlying DB connection.
  Future<void> close() => _db.close();
}

```
