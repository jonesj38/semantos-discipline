---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/platform/identity_store_stub.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.099043+00:00
---

# apps/semantos/lib/platform/identity_store_stub.dart

```dart
import 'package:semantos_core/semantos_core.dart';
import 'package:semantos_shell_native_identity/semantos_shell_native_identity.dart'
    as native_identity;

/// Native-default IdentityStore adapter — re-exports the
/// flutter_secure_storage-backed adapter from the
/// `semantos_shell_native_identity` sub-package.
///
/// The native adapter lives in a separate package so
/// `flutter_secure_storage` stays out of the shell's top-level pubspec.
/// Even with conditional imports, Flutter's web plugin registrant
/// imports every web-plugin dep declared in pubspec — keeping the
/// secure-storage dep out of the shell's pubspec keeps
/// `flutter_secure_storage_web` (and its `dart:html` import) out of
/// the web build graph entirely.
///
/// This file is the *stub* in the target-conditional import pair —
/// selected on `dart.library.io` targets. The web counterpart in
/// `identity_store_web.dart` uses `idb_shim` (IndexedDB) and is
/// selected via conditional import for `dart.library.html`.
class SecureIdentityStoreAdapter implements IdentityStore {
  final IdentityStore _delegate;

  SecureIdentityStoreAdapter() : _delegate = native_identity.buildIdentityStore();

  @override
  Future<String?> read(String key) => _delegate.read(key);

  @override
  Future<void> write(String key, String value) => _delegate.write(key, value);

  @override
  Future<void> delete(String key) => _delegate.delete(key);

  @override
  bool get isHardwareBacked => _delegate.isHardwareBacked;
}

/// Build the native-default [IdentityStore].
IdentityStore buildIdentityStore() => SecureIdentityStoreAdapter();

```
