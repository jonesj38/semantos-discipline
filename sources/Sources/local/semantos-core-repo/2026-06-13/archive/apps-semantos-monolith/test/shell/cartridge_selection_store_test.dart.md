---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/shell/cartridge_selection_store_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.929097+00:00
---

# archive/apps-semantos-monolith/test/shell/cartridge_selection_store_test.dart

```dart
// Tests for CartridgeSelectionStore — welcome flag + last-used
// cartridge persistence over the SecureStore abstraction.
//
// Uses the in-memory SecureStore so tests don't touch keychain.

import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/shell/cartridge_selection_store.dart';

void main() {
  group('CartridgeSelectionStore', () {
    late InMemorySecureStore secure;
    late CartridgeSelectionStore store;

    setUp(() {
      secure = InMemorySecureStore();
      store = CartridgeSelectionStore(secureStore: secure);
    });

    test('isWelcomed defaults to false on first launch', () async {
      expect(await store.isWelcomed(), isFalse);
    });

    test('markWelcomed persists the flag', () async {
      await store.markWelcomed();
      expect(await store.isWelcomed(), isTrue);
    });

    test('lastUsedCartridgeId is null until set', () async {
      expect(await store.lastUsedCartridgeId(), isNull);
    });

    test('setLastUsedCartridgeId round-trips', () async {
      await store.setLastUsedCartridgeId('oddjobz');
      expect(await store.lastUsedCartridgeId(), 'oddjobz');
    });

    test('reset clears welcomed flag and last-used', () async {
      await store.markWelcomed();
      await store.setLastUsedCartridgeId('self');
      await store.reset();
      expect(await store.isWelcomed(), isFalse);
      expect(await store.lastUsedCartridgeId(), isNull);
    });

    test('switching cartridge overwrites prior last-used', () async {
      await store.setLastUsedCartridgeId('oddjobz');
      await store.setLastUsedCartridgeId('self');
      expect(await store.lastUsedCartridgeId(), 'self');
    });
  });
}

```
