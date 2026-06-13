---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/pask/sqlite_pask_snapshot_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.908938+00:00
---

# archive/apps-semantos-monolith/test/pask/sqlite_pask_snapshot_store_test.dart

```dart
// W1.3 — SqlitePaskSnapshotStore red tests.
//
// Schema:
//   pask_snapshots(
//     domain_flag  INTEGER NOT NULL,
//     snapshot_key TEXT    NOT NULL,
//     blob         BLOB    NOT NULL,
//     saved_at_ms  INTEGER NOT NULL,
//     PRIMARY KEY (domain_flag, snapshot_key)
//   )
//
// API:
//   SqlitePaskSnapshotStore.fromDatabase(db)  → static factory
//   store.save(domainFlag, key, blob)          → Future<void>
//   store.load(domainFlag, key)                → Future<Uint8List?>
//   store.delete(domainFlag, key)              → Future<bool>
//   store.keys(domainFlag)                     → Future<List<String>>
//   store.count(domainFlag)                    → Future<int>
//
// Tests use sqflite_common_ffi so they run under `dart test`.

import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/pask/sqlite_pask_snapshot_store.dart';

Future<SqlitePaskSnapshotStore> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions());
  return SqlitePaskSnapshotStore.fromDatabase(db);
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('SqlitePaskSnapshotStore (W1.3)', () {
    test('schema: pask_snapshots table is created with required columns', () async {
      final store = await _openInMemory();
      final columns = await store.rawQuery(
          "PRAGMA table_info('pask_snapshots')");
      final names = columns.map((r) => r['name'] as String).toSet();
      expect(names, containsAll({'domain_flag', 'snapshot_key', 'blob', 'saved_at_ms'}));
      await store.close();
    });

    test('save + load round-trips a blob', () async {
      final store = await _openInMemory();
      final blob = Uint8List.fromList([1, 2, 3, 4, 5]);
      await store.save(domainFlag: 0x000101, key: 'graph', blob: blob);
      final loaded = await store.load(domainFlag: 0x000101, key: 'graph');
      expect(loaded, equals(blob));
      await store.close();
    });

    test('load returns null for unknown key', () async {
      final store = await _openInMemory();
      final result = await store.load(domainFlag: 0x000101, key: 'missing');
      expect(result, isNull);
      await store.close();
    });

    test('save upserts — second save overwrites the first', () async {
      final store = await _openInMemory();
      await store.save(
          domainFlag: 0x000101, key: 'graph', blob: Uint8List.fromList([1, 2]));
      await store.save(
          domainFlag: 0x000101, key: 'graph', blob: Uint8List.fromList([9, 8, 7]));
      final loaded = await store.load(domainFlag: 0x000101, key: 'graph');
      expect(loaded, equals(Uint8List.fromList([9, 8, 7])));
      await store.close();
    });

    test('domain_flag scoping: different flags keep separate rows', () async {
      final store = await _openInMemory();
      final blobA = Uint8List.fromList([0xAA]);
      final blobB = Uint8List.fromList([0xBB]);
      await store.save(domainFlag: 0x000101, key: 'graph', blob: blobA);
      await store.save(domainFlag: 0x000202, key: 'graph', blob: blobB);
      expect(await store.load(domainFlag: 0x000101, key: 'graph'), equals(blobA));
      expect(await store.load(domainFlag: 0x000202, key: 'graph'), equals(blobB));
      await store.close();
    });

    test('delete removes a row and returns true', () async {
      final store = await _openInMemory();
      await store.save(
          domainFlag: 0x000101, key: 'g', blob: Uint8List.fromList([0x01]));
      final removed = await store.delete(domainFlag: 0x000101, key: 'g');
      expect(removed, isTrue);
      expect(await store.load(domainFlag: 0x000101, key: 'g'), isNull);
      await store.close();
    });

    test('delete returns false for non-existent key', () async {
      final store = await _openInMemory();
      final removed = await store.delete(domainFlag: 0x000101, key: 'nope');
      expect(removed, isFalse);
      await store.close();
    });

    test('keys returns all keys for a domain_flag, sorted ascending', () async {
      final store = await _openInMemory();
      await store.save(
          domainFlag: 0x000101, key: 'beta', blob: Uint8List.fromList([1]));
      await store.save(
          domainFlag: 0x000101, key: 'alpha', blob: Uint8List.fromList([2]));
      await store.save(
          domainFlag: 0x000202, key: 'other', blob: Uint8List.fromList([3]));
      final keys = await store.keys(domainFlag: 0x000101);
      expect(keys, equals(['alpha', 'beta']));
      await store.close();
    });

    test('count returns correct total for domain_flag', () async {
      final store = await _openInMemory();
      expect(await store.count(domainFlag: 0x000101), equals(0));
      await store.save(
          domainFlag: 0x000101, key: 'a', blob: Uint8List.fromList([1]));
      await store.save(
          domainFlag: 0x000101, key: 'b', blob: Uint8List.fromList([2]));
      expect(await store.count(domainFlag: 0x000101), equals(2));
      await store.close();
    });

    test('large blob (>1 KiB) round-trips correctly', () async {
      final store = await _openInMemory();
      final large = Uint8List(2048);
      for (var i = 0; i < 2048; i++) {
        large[i] = i & 0xFF;
      }
      await store.save(domainFlag: 0x000101, key: 'snapshot', blob: large);
      final loaded = await store.load(domainFlag: 0x000101, key: 'snapshot');
      expect(loaded, equals(large));
      await store.close();
    });
  });
}

```
