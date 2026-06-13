---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/wallet/edge_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.123724+00:00
---

# apps/semantos/test/wallet/edge_store_test.dart

```dart
// Unit tests for `edge_store.dart` — persistence round-trip, replace-by-
// edgeId idempotence, index advance, findEdgeTo recency, and clear.

import 'package:flutter_test/flutter_test.dart';

import 'package:semantos/src/identity/child_cert_store.dart'
    show InMemorySecureStore;
import 'package:semantos/src/wallet/edge_store.dart';

LocalEdgeEnvelope _env({
  required String edgeId,
  String theirCertId = 'peer',
  int signingKeyIndex = 0,
  int createdAt = 0,
}) =>
    LocalEdgeEnvelope(
      edgeId: edgeId,
      myCertId: 'me',
      theirCertId: theirCertId,
      theirPublicKey: '02${'ab' * 32}',
      signingKeyIndex: signingKeyIndex,
      edgeType: kEdgeTypeMessaging,
      backupRecipe: 'cc' * 32,
      createdAt: createdAt,
    );

void main() {
  late EdgeStore store;

  setUp(() {
    store = EdgeStore(InMemorySecureStore());
  });

  test('empty store loads an empty list', () async {
    expect(await store.loadAll(), isEmpty);
    expect(await store.get('nope'), isNull);
    expect(await store.findEdgeTo('nope'), isNull);
  });

  test('save then load round-trips all fields', () async {
    final e = _env(edgeId: 'aa', signingKeyIndex: 5, createdAt: 99);
    await store.save(e);
    final all = await store.loadAll();
    expect(all, hasLength(1));
    final got = all.single;
    expect(got.edgeId, 'aa');
    expect(got.signingKeyIndex, 5);
    expect(got.createdAt, 99);
    expect(got.theirPublicKey, e.theirPublicKey);
    expect(got.backupRecipe, e.backupRecipe);
    expect(got.edgeType, kEdgeTypeMessaging);
  });

  test('save replaces row with same edgeId (idempotent re-accept)', () async {
    await store.save(_env(edgeId: 'aa', signingKeyIndex: 0));
    await store.save(_env(edgeId: 'aa', signingKeyIndex: 9));
    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.single.signingKeyIndex, 9);
  });

  test('distinct edgeIds append', () async {
    await store.save(_env(edgeId: 'aa'));
    await store.save(_env(edgeId: 'bb'));
    expect(await store.loadAll(), hasLength(2));
    expect((await store.get('bb'))!.edgeId, 'bb');
  });

  test('advanceIndex bumps the signing-key index', () async {
    await store.save(_env(edgeId: 'aa', signingKeyIndex: 3));
    await store.advanceIndex('aa');
    expect((await store.get('aa'))!.signingKeyIndex, 4);
  });

  test('advanceIndex is a no-op for unknown edges', () async {
    await store.advanceIndex('ghost'); // must not throw
    expect(await store.loadAll(), isEmpty);
  });

  test('findEdgeTo returns the most recent edge to a peer', () async {
    await store.save(
        _env(edgeId: 'old', theirCertId: 'bob', createdAt: 100));
    await store.save(
        _env(edgeId: 'new', theirCertId: 'bob', createdAt: 200));
    await store.save(
        _env(edgeId: 'other', theirCertId: 'carol', createdAt: 999));
    final found = await store.findEdgeTo('bob');
    expect(found, isNotNull);
    expect(found!.edgeId, 'new');
  });

  test('clear wipes the log', () async {
    await store.save(_env(edgeId: 'aa'));
    await store.clear();
    expect(await store.loadAll(), isEmpty);
  });

  test('corrupt slot throws FormatException on load', () async {
    final raw = InMemorySecureStore();
    await raw.write(kEdgeStoreSlot, '{"not":"an array"}');
    final s = EdgeStore(raw);
    expect(() => s.loadAll(), throwsA(isA<FormatException>()));
  });
}

```
