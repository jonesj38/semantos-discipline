---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/wallet/identity_store_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.105276+00:00
---

# apps/semantos/lib/src/wallet/identity_store_adapter.dart

```dart
// C11 PR-C11-4e — `IdentityStore` ⇄ `SecureStore` adapter.
//
// Why: PR-C11-4c built `CertBodyStore` and `RecipeStore` against the
// `SecureStore` abstraction defined in
// `apps/semantos/lib/src/identity/child_cert_store.dart`. The
// production shell wires `IdentityStore` (from `semantos_core`) into
// `SemantosPlatform.identityStore`. The two interfaces have the same
// shape — read/write/delete by string key — so a one-page adapter
// lets the wallet primitives consume the production seam without
// changing 4c's API.
//
// `SecureStore.deleteAll()` and `readAll()` are not part of
// `IdentityStore`; we surface them as `UnimplementedError` rather than
// silently downgrade. The wallet code paths never call them.

import 'package:semantos_core/semantos_core.dart' show IdentityStore;

import '../identity/child_cert_store.dart' show SecureStore;

/// Wrap an [IdentityStore] so wallet primitives keyed on [SecureStore]
/// can use it unchanged.
class IdentityStoreSecureStoreAdapter implements SecureStore {
  IdentityStoreSecureStoreAdapter(this._store);

  final IdentityStore _store;

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<void> delete(String key) => _store.delete(key);

  @override
  Future<void> deleteAll() async {
    // IdentityStore intentionally doesn't expose bulk-delete — the
    // shell's identity model is "edit specific slots" not "wipe the
    // box". Calling this would silently nuke shell-wide state we
    // don't own.
    throw UnimplementedError(
        'IdentityStoreSecureStoreAdapter does not implement deleteAll');
  }

  @override
  Future<Map<String, String>> readAll() async {
    throw UnimplementedError(
        'IdentityStoreSecureStoreAdapter does not implement readAll');
  }
}

```
