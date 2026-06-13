---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/identity_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.012647+00:00
---

# platforms/flutter/semantos_core/lib/src/identity_store.dart

```dart
/// Identity custody seam.
///
/// Implementations:
///   - SecureIdentityStore (semantos_ffi) — flutter_secure_storage backed
///     (iOS Keychain / Android Keystore) for native targets.
///   - IndexedDbIdentityStore (semantos_web) — encrypted IndexedDB for PWA;
///     less secure than Keychain but workable when paired to Plexus for
///     recovery.
///
/// The shell never touches the underlying storage directly — all reads
/// and writes go through this seam so the boot-time adapter swap is the
/// only place that has to know about the target's custody model.
abstract class IdentityStore {
  /// Read a value by key. Returns null if absent.
  Future<String?> read(String key);

  /// Write a value. Overwrites any existing value at [key].
  Future<void> write(String key, String value);

  /// Remove a value. No-op if absent.
  Future<void> delete(String key);

  /// True if the underlying store provides hardware-backed custody
  /// (Keychain/Keystore). False for IndexedDB-backed PWA stores.
  bool get isHardwareBacked;
}

```
