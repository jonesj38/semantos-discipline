---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_shell_native_identity/lib/semantos_shell_native_identity.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.010974+00:00
---

# platforms/flutter/semantos_shell_native_identity/lib/semantos_shell_native_identity.dart

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:semantos_core/semantos_core.dart';

/// IdentityStore adapter backed by `flutter_secure_storage` — Keychain
/// on iOS/macOS, Keystore on Android, libsecret on Linux, DPAPI on
/// Windows. Hardware-backed where the platform supports it.
///
/// This adapter ships in a separate package from the shell to keep
/// `flutter_secure_storage` (and its web plugin
/// `flutter_secure_storage_web`, which imports `dart:html` and breaks
/// the wasm web target) out of the web build graph. The PWA shell
/// imports an IndexedDB-backed adapter instead via conditional
/// import — see `apps/semantos/lib/platform/identity_store_web.dart`.
class FlutterSecureIdentityStore implements IdentityStore {
  final FlutterSecureStorage _storage;

  FlutterSecureIdentityStore()
      : _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  bool get isHardwareBacked => true;
}

/// Build the native-default IdentityStore. Exposed for symmetry with
/// the PWA `buildIdentityStore()` factory in `identity_store_web.dart`.
IdentityStore buildIdentityStore() => FlutterSecureIdentityStore();

```
