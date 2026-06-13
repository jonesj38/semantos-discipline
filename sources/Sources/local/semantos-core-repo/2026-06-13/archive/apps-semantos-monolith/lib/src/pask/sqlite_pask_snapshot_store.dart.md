---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/pask/sqlite_pask_snapshot_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.864930+00:00
---

# archive/apps-semantos-monolith/lib/src/pask/sqlite_pask_snapshot_store.dart

```dart
// W1.3 — SQLite-backed Pask graph snapshot store.
//
// Persists opaque pask kernel snapshot BLOBs (produced by
// `pask_snapshot_state`) to a SQLite table so the graph survives
// app restarts.  On next foreground the snapshot is loaded and
// passed to `pask_restore_state` to resume the in-WASM graph from
// the last saved state.
//
// Schema:
//
//   pask_snapshots(
//     domain_flag  INTEGER NOT NULL,  -- hat domain (e.g. 0x000101)
//     snapshot_key TEXT    NOT NULL,  -- logical name (e.g. 'graph')
//     blob         BLOB    NOT NULL,  -- raw snapshot bytes
//     saved_at_ms  INTEGER NOT NULL,  -- wall-clock ms
//     PRIMARY KEY (domain_flag, snapshot_key)
//   )
//
// Why sqflite: the sqflite_common_ffi backend works under `dart test`
// (no Flutter SDK gate); production uses sqflite's MethodChannel adapter
// on iOS + Android.  Both are SQLite under the hood.

import 'dart:typed_data';

import 'package:sqflite_common/sqlite_api.dart';

const String _table = 'pask_snapshots';

const String _ddl = '''
  CREATE TABLE IF NOT EXISTS pask_snapshots (
    domain_flag  INTEGER NOT NULL,
    snapshot_key TEXT    NOT NULL,
    blob         BLOB    NOT NULL,
    saved_at_ms  INTEGER NOT NULL,
    PRIMARY KEY (domain_flag, snapshot_key)
  )
''';

/// SQLite-backed Pask graph snapshot store.
///
/// Call [fromDatabase] with a pre-opened [Database] to initialise the
/// schema; then use [save] / [load] to persist snapshot BLOBs.
class SqlitePaskSnapshotStore {
  final Database _db;
  SqlitePaskSnapshotStore._(this._db);

  /// Open the schema on [db].  Creates the table if it does not exist.
  static Future<SqlitePaskSnapshotStore> fromDatabase(Database db) async {
    await db.execute(_ddl);
    return SqlitePaskSnapshotStore._(db);
  }

  /// Expose raw DB for tests (PRAGMA queries, etc.).
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? args]) =>
      _db.rawQuery(sql, args);

  /// Persist [blob] under ([domainFlag], [key]).  Overwrites any prior
  /// snapshot at the same key.
  Future<void> save({
    required int domainFlag,
    required String key,
    required Uint8List blob,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      _table,
      {
        'domain_flag': domainFlag,
        'snapshot_key': key,
        'blob': blob,
        'saved_at_ms': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load the snapshot BLOB for ([domainFlag], [key]).
  /// Returns null when no snapshot has been saved for that key.
  Future<Uint8List?> load({
    required int domainFlag,
    required String key,
  }) async {
    final rows = await _db.query(
      _table,
      columns: ['blob'],
      where: 'domain_flag = ? AND snapshot_key = ?',
      whereArgs: [domainFlag, key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['blob'];
    if (raw is Uint8List) return raw;
    if (raw is List<int>) return Uint8List.fromList(raw);
    return null;
  }

  /// Remove the snapshot for ([domainFlag], [key]).
  /// Returns true if the row existed and was deleted; false otherwise.
  Future<bool> delete({
    required int domainFlag,
    required String key,
  }) async {
    final count = await _db.delete(
      _table,
      where: 'domain_flag = ? AND snapshot_key = ?',
      whereArgs: [domainFlag, key],
    );
    return count > 0;
  }

  /// List all snapshot keys for [domainFlag], sorted ascending.
  Future<List<String>> keys({required int domainFlag}) async {
    final rows = await _db.query(
      _table,
      columns: ['snapshot_key'],
      where: 'domain_flag = ?',
      whereArgs: [domainFlag],
      orderBy: 'snapshot_key ASC',
    );
    return rows.map((r) => r['snapshot_key'] as String).toList();
  }

  /// Count snapshots stored for [domainFlag].
  Future<int> count({required int domainFlag}) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_table WHERE domain_flag = ?',
      [domainFlag],
    );
    final c = rows.first['c'];
    return (c is int) ? c : (c as num).toInt();
  }

  /// Close the underlying database connection.
  Future<void> close() => _db.close();
}

```
