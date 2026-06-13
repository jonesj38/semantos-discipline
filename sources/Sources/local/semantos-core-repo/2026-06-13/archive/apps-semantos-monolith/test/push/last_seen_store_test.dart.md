---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/push/last_seen_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.915964+00:00
---

# archive/apps-semantos-monolith/test/push/last_seen_store_test.dart

```dart
// Sovereign-push D.2 — LastSeenStore round-trip tests.
//
// LastSeenStore wraps SecureStorage with a per-brain-endpoint slot
// and a monotonic write guard.  Tests use InMemorySecureStore so the
// suite stays Flutter-SDK-free under `dart test`.

import 'package:test/test.dart';

import 'package:semantos/src/identity/child_cert_store.dart'
    show InMemorySecureStore;
import 'package:semantos/src/push/last_seen_store.dart';

void main() {
  group('LastSeenStore', () {
    test('returns defaultValue when nothing has been persisted', () async {
      final store = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      expect(await store.read(), equals(LastSeenStore.defaultValue));
      expect(LastSeenStore.defaultValue, equals(0));
    });

    test('round-trips a written value', () async {
      final store = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      await store.write(1_700_000_001);
      expect(await store.read(), equals(1_700_000_001));
    });

    test('refuses to rewind the cursor (monotonic write)', () async {
      final store = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      await store.write(1_700_000_010);
      await store.write(1_700_000_005); // older — should be rejected
      expect(await store.read(), equals(1_700_000_010));

      await store.write(1_700_000_010); // equal — also rejected
      expect(await store.read(), equals(1_700_000_010));

      await store.write(1_700_000_020); // newer — accepted
      expect(await store.read(), equals(1_700_000_020));
    });

    test('refuses to write a negative value', () async {
      final store = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      await store.write(-1);
      expect(await store.read(), equals(LastSeenStore.defaultValue));
    });

    test('per-brain slots — different endpoints have independent cursors',
        () async {
      final secure = InMemorySecureStore();
      final a = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain-a.example/',
      );
      final b = LastSeenStore(
        secureStore: secure,
        brainEndpoint: 'https://brain-b.example/',
      );
      await a.write(100);
      await b.write(200);
      expect(await a.read(), equals(100));
      expect(await b.read(), equals(200));
      expect(a.slot, isNot(equals(b.slot)));
      expect(a.slot, startsWith('helm.lastSeenTs.'));
    });

    test('clear() wipes the cursor', () async {
      final store = LastSeenStore(
        secureStore: InMemorySecureStore(),
        brainEndpoint: 'https://brain.example/',
      );
      await store.write(1_700_000_001);
      await store.clear();
      expect(await store.read(), equals(LastSeenStore.defaultValue));
    });

    test('malformed persisted value returns defaultValue', () async {
      final secure = InMemorySecureStore();
      final endpoint = 'https://brain.example/';
      // Pre-seed a malformed value at the slot.
      final slot = LastSeenStore(
        secureStore: secure,
        brainEndpoint: endpoint,
      ).slot;
      await secure.write(slot, 'not-a-number');
      final store = LastSeenStore(
        secureStore: secure,
        brainEndpoint: endpoint,
      );
      expect(await store.read(), equals(LastSeenStore.defaultValue));
    });
  });
}

```
