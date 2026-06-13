---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/repl/hat_entity_repository_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.921400+00:00
---

# archive/apps-semantos-monolith/test/repl/hat_entity_repository_test.dart

```dart
// W1.1 — HatEntityRepository tests (red → green).
//
// Exercises:
//   - insert and query by domain_flag;
//   - index on (domain_flag, state) works (query by state);
//   - index on (domain_flag, scheduled_at) works (query by scheduled_at);
//   - cold-start read returns persisted rows (re-open same DB);
//   - upsert (update) replaces an existing row;
//   - delete removes a row;
//   - queryAll with no filter returns all rows for a domain_flag.
//
// Backed by sqflite_common_ffi so the test runs under `dart test`
// without a Flutter SDK gate.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'package:semantos/src/repl/hat_entity_repository.dart';

Future<HatEntityRepository> _openInMemory() async {
  final factory = databaseFactoryFfi;
  final db = await factory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(),
  );
  return HatEntityRepository.fromDatabase(db);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  group('HatEntityRepository', () {
    test('schema creation is idempotent', () async {
      final repo = await _openInMemory();
      expect(await repo.count(domainFlag: 0x000101), equals(0));
      await repo.close();
    });

    test('insert and queryAll by domain_flag', () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'job-1',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '2026-05-10T09:00:00Z',
        entityJson: '{"id":"job-1","state":"lead"}',
        updatedAt: '2026-05-10T00:00:00Z',
      ));
      await repo.upsert(HatEntity(
        id: 'job-2',
        domainFlag: 0x000101,
        state: 'scheduled',
        scheduledAt: '2026-05-11T10:00:00Z',
        entityJson: '{"id":"job-2","state":"scheduled"}',
        updatedAt: '2026-05-10T00:00:00Z',
      ));

      final rows = await repo.queryAll(domainFlag: 0x000101);
      expect(rows, hasLength(2));
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, containsAll(['job-1', 'job-2']));
      await repo.close();
    });

    test('queryAll only returns rows for the given domain_flag', () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'job-a',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));
      await repo.upsert(HatEntity(
        id: 'other-b',
        domainFlag: 0x000202,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));

      final rows = await repo.queryAll(domainFlag: 0x000101);
      expect(rows, hasLength(1));
      expect(rows.first.id, equals('job-a'));
      await repo.close();
    });

    test('queryByState uses (domain_flag, state) index path', () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'j-lead',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));
      await repo.upsert(HatEntity(
        id: 'j-sched',
        domainFlag: 0x000101,
        state: 'scheduled',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));
      await repo.upsert(HatEntity(
        id: 'j-lead2',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));

      final leads = await repo.queryByState(
        domainFlag: 0x000101,
        state: 'lead',
      );
      expect(leads, hasLength(2));
      for (final r in leads) {
        expect(r.state, equals('lead'));
      }

      final sched = await repo.queryByState(
        domainFlag: 0x000101,
        state: 'scheduled',
      );
      expect(sched, hasLength(1));
      expect(sched.first.id, equals('j-sched'));
      await repo.close();
    });

    test('queryByScheduledAt uses (domain_flag, scheduled_at) index path',
        () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'j-may10',
        domainFlag: 0x000101,
        state: 'scheduled',
        scheduledAt: '2026-05-10T08:00:00Z',
        entityJson: '{}',
        updatedAt: '',
      ));
      await repo.upsert(HatEntity(
        id: 'j-may11',
        domainFlag: 0x000101,
        state: 'scheduled',
        scheduledAt: '2026-05-11T08:00:00Z',
        entityJson: '{}',
        updatedAt: '',
      ));
      await repo.upsert(HatEntity(
        id: 'j-no-date',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));

      final onMay10 = await repo.queryByScheduledAt(
        domainFlag: 0x000101,
        scheduledAt: '2026-05-10T08:00:00Z',
      );
      expect(onMay10, hasLength(1));
      expect(onMay10.first.id, equals('j-may10'));
      await repo.close();
    });

    test('upsert replaces existing row (same id)', () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'job-x',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{"v":1}',
        updatedAt: '2026-05-10T00:00:00Z',
      ));
      await repo.upsert(HatEntity(
        id: 'job-x',
        domainFlag: 0x000101,
        state: 'scheduled',
        scheduledAt: '2026-05-12T09:00:00Z',
        entityJson: '{"v":2}',
        updatedAt: '2026-05-10T01:00:00Z',
      ));

      final rows = await repo.queryAll(domainFlag: 0x000101);
      expect(rows, hasLength(1));
      expect(rows.first.state, equals('scheduled'));
      expect(rows.first.entityJson, equals('{"v":2}'));
      await repo.close();
    });

    test('cold-start: rows persist across re-open of same DB path', () async {
      // Use a named in-memory path so the second open reuses it.
      const path = 'hat_entity_cold_start_test';
      final factory = databaseFactoryFfi;

      final db1 = await factory.openDatabase(path, options: OpenDatabaseOptions());
      final repo1 = await HatEntityRepository.fromDatabase(db1);
      await repo1.upsert(HatEntity(
        id: 'persisted-job',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{"id":"persisted-job"}',
        updatedAt: '2026-05-10T00:00:00Z',
      ));
      await repo1.close();

      final db2 = await factory.openDatabase(path, options: OpenDatabaseOptions());
      final repo2 = await HatEntityRepository.fromDatabase(db2);
      final rows = await repo2.queryAll(domainFlag: 0x000101);
      expect(rows, hasLength(1));
      expect(rows.first.id, equals('persisted-job'));
      await repo2.close();

      // Cleanup.
      await factory.deleteDatabase(path);
    });

    test('delete removes a row by id + domain_flag', () async {
      final repo = await _openInMemory();
      await repo.upsert(HatEntity(
        id: 'to-delete',
        domainFlag: 0x000101,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));
      expect(await repo.count(domainFlag: 0x000101), equals(1));
      final removed = await repo.delete(id: 'to-delete', domainFlag: 0x000101);
      expect(removed, equals(1));
      expect(await repo.count(domainFlag: 0x000101), equals(0));
      await repo.close();
    });

    test('count is scoped to domain_flag', () async {
      final repo = await _openInMemory();
      for (var i = 0; i < 3; i++) {
        await repo.upsert(HatEntity(
          id: 'a-$i',
          domainFlag: 0x000101,
          state: 'lead',
          scheduledAt: '',
          entityJson: '{}',
          updatedAt: '',
        ));
      }
      await repo.upsert(HatEntity(
        id: 'b-0',
        domainFlag: 0x000202,
        state: 'lead',
        scheduledAt: '',
        entityJson: '{}',
        updatedAt: '',
      ));
      expect(await repo.count(domainFlag: 0x000101), equals(3));
      expect(await repo.count(domainFlag: 0x000202), equals(1));
      await repo.close();
    });
  });
}

```
