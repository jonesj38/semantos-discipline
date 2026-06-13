---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/identity/flutter_secure_store_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.594239+00:00
---

# cartridges/jambox/mobile/lib/src/identity/flutter_secure_store_adapter.dart

```dart
// D-O5m — flutter_secure_storage-backed adapter for ChildCertStore.
//
// Lives in its own file so the import surface of
// `child_cert_store.dart` (the pure-Dart core) stays free of Flutter
// imports. That keeps the unit-test suite runnable under plain
// `dart test` (no Flutter SDK gate). The Flutter app wires this
// adapter into ChildCertStore at app boot in `main.dart`.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'child_cert_store.dart';

/// Production SecureStore — backed by iOS Keychain on iOS and
/// Android Keystore (via EncryptedSharedPreferences) on Android.
class FlutterSecureStoreAdapter implements SecureStore {
  final FlutterSecureStorage _inner;

  FlutterSecureStoreAdapter([FlutterSecureStorage? inner])
      : _inner = inner ?? const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _inner.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _inner.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _inner.delete(key: key);

  @override
  Future<void> deleteAll() => _inner.deleteAll();

  @override
  Future<Map<String, String>> readAll() => _inner.readAll();
}

```
