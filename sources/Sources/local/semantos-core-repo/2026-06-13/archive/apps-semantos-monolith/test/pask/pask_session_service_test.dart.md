---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/pask/pask_session_service_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.908652+00:00
---

# archive/apps-semantos-monolith/test/pask/pask_session_service_test.dart

```dart
// W1.3 — PaskSessionService unit tests.
//
// Exercises the lifecycle seam:
//   - onResume() loads and restores snapshot from the store.
//   - onFsmAction() calls interact, captures snapshot, persists it.
//   - Cold start (no snapshot) — onResume is a no-op.
//   - Second resume after a save picks up the updated snapshot.

import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/pask/pask_session_service.dart';
import 'package:semantos/src/pask/sqlite_pask_snapshot_store.dart';

Future<SqlitePaskSnapshotStore> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions());
  return SqlitePaskSnapshotStore.fromDatabase(db);
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('PaskSessionService (W1.3)', () {
    test('cold start: onResume is a no-op when no snapshot exists', () async {
      final store = await _openInMemory();
      final restored = <Uint8List>[];
      final svc = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
        restoreCall: (blob) {
          restored.add(blob);
          return 0;
        },
      );
      await svc.onResume();
      expect(svc.isRestored, isFalse);
      expect(restored, isEmpty);
      await store.close();
    });

    test('onResume loads stored snapshot and calls restoreCall', () async {
      final store = await _openInMemory();
      final expected = Uint8List.fromList([0x01, 0x02, 0x03]);
      await store.save(
          domainFlag: 0x000101, key: kPaskGraphSnapshotKey, blob: expected);

      final restored = <Uint8List>[];
      final svc = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
        restoreCall: (blob) {
          restored.add(blob);
          return 0;
        },
      );
      await svc.onResume();
      expect(svc.isRestored, isTrue);
      expect(restored, hasLength(1));
      expect(restored.first, equals(expected));
      expect(svc.cachedSnapshot, equals(expected));
      await store.close();
    });

    test('onFsmAction calls interactAndSnapshot + persists result', () async {
      final store = await _openInMemory();
      final newSnapshot = Uint8List.fromList([0xAA, 0xBB]);
      final interactions = <({String cellId, String kindPath})>[];

      final svc = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
        interactAndSnapshot: (cellId, kindPath) async {
          interactions.add((cellId: cellId, kindPath: kindPath));
          return newSnapshot;
        },
      );

      await svc.onFsmAction('job-123', 'oddjobz.job.quote');
      expect(interactions, hasLength(1));
      expect(interactions.first.cellId, equals('job-123'));
      expect(interactions.first.kindPath, equals('oddjobz.job.quote'));
      expect(svc.cachedSnapshot, equals(newSnapshot));

      // The snapshot must have been persisted.
      final loaded =
          await store.load(domainFlag: 0x000101, key: kPaskGraphSnapshotKey);
      expect(loaded, equals(newSnapshot));
      await store.close();
    });

    test('second resume after onFsmAction loads updated snapshot', () async {
      final store = await _openInMemory();
      final v1 = Uint8List.fromList([0x11]);
      final v2 = Uint8List.fromList([0x22]);
      await store.save(
          domainFlag: 0x000101, key: kPaskGraphSnapshotKey, blob: v1);

      final restored = <Uint8List>[];
      final svc = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
        restoreCall: (blob) {
          restored.add(blob);
          return 0;
        },
        interactAndSnapshot: (cellId, kindPath) async => v2,
      );

      // First resume restores v1.
      await svc.onResume();
      expect(restored.last, equals(v1));

      // FSM action — produces v2 and persists it.
      await svc.onFsmAction('job-99', 'oddjobz.job.invoice');

      // Second resume restores v2.
      await svc.onResume();
      expect(restored.last, equals(v2));
      await store.close();
    });

    test('onFsmAction is a no-op when no interactAndSnapshot provided', () async {
      final store = await _openInMemory();
      final svc = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
      );
      // Should not throw.
      await svc.onFsmAction('job-1', 'oddjobz.job.quote');
      expect(await store.count(domainFlag: 0x000101), equals(0));
      await store.close();
    });

    test('domain_flag isolation: different services do not cross-pollinate', () async {
      final store = await _openInMemory();
      final blobA = Uint8List.fromList([0xA1]);
      final blobB = Uint8List.fromList([0xB1]);

      final svcA = PaskSessionService(
        store: store,
        domainFlag: 0x000101,
        interactAndSnapshot: (_, __) async => blobA,
      );
      final svcB = PaskSessionService(
        store: store,
        domainFlag: 0x000202,
        interactAndSnapshot: (_, __) async => blobB,
      );

      await svcA.onFsmAction('cell-a', 'domain.a.action');
      await svcB.onFsmAction('cell-b', 'domain.b.action');

      expect(
          await store.load(
              domainFlag: 0x000101, key: kPaskGraphSnapshotKey),
          equals(blobA));
      expect(
          await store.load(
              domainFlag: 0x000202, key: kPaskGraphSnapshotKey),
          equals(blobB));
      await store.close();
    });
  });
}

```
