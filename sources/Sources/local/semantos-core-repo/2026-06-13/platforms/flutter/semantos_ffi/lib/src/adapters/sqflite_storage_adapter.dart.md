---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/adapters/sqflite_storage_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.009602+00:00
---

# platforms/flutter/semantos_ffi/lib/src/adapters/sqflite_storage_adapter.dart

```dart
// SqfliteStorageAdapter — SQLite-backed cell storage for Flutter.
//
// Uses sqflite with WAL mode for concurrent reads. Data is stored as BLOBs
// keyed by path. The database lives in the app's documents directory.

import 'dart:typed_data' show Uint8List;

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Persists cell data to SQLite via sqflite.
class SqfliteStorageAdapter {
  Database? _db;
  final String _dbName;

  SqfliteStorageAdapter({String dbName = 'semantos_cells.db'})
      : _dbName = dbName;

  /// Open (or create) the database. Must be called before read/write.
  Future<void> open() async {
    if (_db != null) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$_dbName';

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cells (
            path TEXT PRIMARY KEY,
            data BLOB NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
      onOpen: (db) async {
        // Enable WAL mode for better concurrent read performance.
        await db.rawQuery('PRAGMA journal_mode=WAL');
      },
    );
  }

  /// Write cell data at the given path. Overwrites if exists.
  Future<void> write(String path, Uint8List data) async {
    final db = _requireDb();
    await db.insert(
      'cells',
      {
        'path': path,
        'data': data,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Read cell data at the given path. Returns null if not found.
  Future<Uint8List?> read(String path) async {
    final db = _requireDb();
    final rows = await db.query(
      'cells',
      columns: ['data'],
      where: 'path = ?',
      whereArgs: [path],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final blob = rows.first['data'];
    if (blob is Uint8List) return blob;
    if (blob is List<int>) return Uint8List.fromList(blob);
    return null;
  }

  /// Check if a cell exists at the given path.
  Future<bool> exists(String path) async {
    final db = _requireDb();
    final result = await db.rawQuery(
      'SELECT 1 FROM cells WHERE path = ? LIMIT 1',
      [path],
    );
    return result.isNotEmpty;
  }

  /// Delete a cell at the given path. Returns true if it existed.
  Future<bool> delete(String path) async {
    final db = _requireDb();
    final count = await db.delete(
      'cells',
      where: 'path = ?',
      whereArgs: [path],
    );
    return count > 0;
  }

  /// List all paths matching a prefix.
  Future<List<String>> list(String prefix) async {
    final db = _requireDb();
    final rows = await db.query(
      'cells',
      columns: ['path'],
      where: 'path LIKE ?',
      whereArgs: ['$prefix%'],
      orderBy: 'path ASC',
    );
    return rows.map((r) => r['path'] as String).toList();
  }

  /// Close the database.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError(
        'SqfliteStorageAdapter not opened. Call open() first.',
      );
    }
    return db;
  }
}

```
