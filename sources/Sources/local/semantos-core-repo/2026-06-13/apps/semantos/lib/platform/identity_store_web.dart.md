---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/platform/identity_store_web.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.099900+00:00
---

# apps/semantos/lib/platform/identity_store_web.dart

```dart
import 'package:idb_shim/idb_browser.dart';
import 'package:semantos_core/semantos_core.dart';

/// PWA IdentityStore adapter — IndexedDB-backed via `idb_shim`.
///
/// `flutter_secure_storage_web` is not usable here: it imports
/// `dart:html`, which the Flutter wasm compiler rejects. `idb_shim`
/// uses `package:web` under the hood and compiles cleanly to WASM.
///
/// Custody model: IndexedDB is origin-scoped and persisted across
/// browser sessions, but it is NOT hardware-backed. The substrate
/// guarantee for PWA operators is honest about this trade — keys
/// stored here can be inspected by anyone with browser access. For
/// keys that warrant hardware custody, the operator pairs to a brain
/// (where the durable identity lives) and uses the PWA as a thin
/// remote.
///
/// Schema: a single object store `semantos.identity` keyed by `key`
/// with a `value` string field. The shell calls read/write/delete via
/// [IdentityStore]; this adapter is the only place that touches the
/// database.
class IndexedDbIdentityStoreAdapter implements IdentityStore {
  static const String _dbName = 'semantos.shell';
  static const int _dbVersion = 1;
  static const String _storeName = 'identity';

  Future<Database>? _dbFuture;

  IndexedDbIdentityStoreAdapter();

  Future<Database> _open() {
    return _dbFuture ??= getIdbFactory()!.open(
      _dbName,
      version: _dbVersion,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (!db.objectStoreNames.contains(_storeName)) {
          db.createObjectStore(_storeName);
        }
      },
    );
  }

  Future<T> _withStore<T>(
    String mode,
    Future<T> Function(ObjectStore store) op,
  ) async {
    final db = await _open();
    final txn = db.transaction(_storeName, mode);
    try {
      final store = txn.objectStore(_storeName);
      final result = await op(store);
      await txn.completed;
      return result;
    } catch (_) {
      // Let txn cleanup happen naturally; rethrow for caller visibility.
      rethrow;
    }
  }

  @override
  Future<String?> read(String key) async {
    return _withStore(idbModeReadOnly, (store) async {
      final v = await store.getObject(key);
      return v is String ? v : null;
    });
  }

  @override
  Future<void> write(String key, String value) async {
    await _withStore(idbModeReadWrite, (store) async {
      await store.put(value, key);
    });
  }

  @override
  Future<void> delete(String key) async {
    await _withStore(idbModeReadWrite, (store) async {
      await store.delete(key);
    });
  }

  @override
  bool get isHardwareBacked => false;
}

/// Build the PWA-default [IdentityStore] — IndexedDB via idb_shim.
IdentityStore buildIdentityStore() => IndexedDbIdentityStoreAdapter();

```
