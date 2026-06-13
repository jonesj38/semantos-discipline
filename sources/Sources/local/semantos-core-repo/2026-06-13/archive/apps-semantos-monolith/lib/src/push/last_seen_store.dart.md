---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/last_seen_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.871918+00:00
---

# archive/apps-semantos-monolith/lib/src/push/last_seen_store.dart

```dart
// Sovereign-push D.2 — last-seen-ts persistence for the silent-push
// → helm.fetch_since cycle.
//
// The brain stamps every published event with a monotonic
// (event_id, ts) pair.  When the silent-push handler wakes the
// device, it asks the brain `helm.fetch_since(since_ts=<lastSeen>)`.
// The handler then advances the cursor to the highest `ts` returned
// (or the `next_cursor_ts` echoed by the brain when it paginated)
// so the next wake never re-renders an already-shown event.
//
// Storage: SecureStorage, keyed per brain endpoint so a device that
// ever gets re-paired to a different brain (or is paired to multiple
// in a future multi-brain build) keeps independent cursors.  Default
// when missing is 0 — fetch everything since Unix epoch start.
//
// The store is intentionally a thin wrapper around SecureStore (the
// same abstraction `child_cert_store.dart` already uses) so the
// unit-test suite can drive it through `InMemorySecureStore` without
// pulling in `flutter_secure_storage`.

import 'dart:convert';

import '../identity/child_cert_store.dart' show SecureStore;

/// Keyed wrapper around SecureStorage that persists the last-seen
/// timestamp the device has consumed via `helm.fetch_since`.
///
/// One [LastSeenStore] instance is keyed to one brain endpoint —
/// the constructor hashes the endpoint into a stable slot name so
/// re-pairings to a different brain don't trample the previous
/// cursor.  Multiple devices on the same physical phone (operator +
/// helper) would share the slot today; a future rev can extend the
/// key with the bearer suffix if multi-helm-on-one-device becomes
/// a thing.
class LastSeenStore {
  final SecureStore _store;
  final String _slot;

  /// Default value returned by [read] when nothing has been
  /// persisted yet.  0 == fetch everything since Unix epoch start
  /// (the brain caps page size, so this is bounded I/O).
  static const int defaultValue = 0;

  LastSeenStore({
    required SecureStore secureStore,
    required String brainEndpoint,
  })  : _store = secureStore,
        _slot = _slotFor(brainEndpoint);

  /// Return the persisted last-seen-ts, or [defaultValue] if nothing
  /// has been written yet (or the stored value is malformed).
  Future<int> read() async {
    final raw = await _store.read(_slot);
    if (raw == null || raw.isEmpty) return defaultValue;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) return defaultValue;
    return parsed;
  }

  /// Persist [ts] as the new last-seen cursor.  Monotonic — refuses
  /// to write a value smaller than the current persisted cursor so
  /// out-of-order races (e.g. two parallel fetches both calling
  /// write with stale results) don't rewind the device.
  Future<void> write(int ts) async {
    if (ts < 0) return;
    final current = await read();
    if (ts <= current) return;
    await _store.write(_slot, ts.toString());
  }

  /// Wipe the cursor — called on operator-initiated unpair from
  /// `ChildCertStore.clear()` callsites that also blow away the
  /// pairing record.  The next fetch will start from zero.
  Future<void> clear() async {
    await _store.delete(_slot);
  }

  /// The SecureStore slot name this instance writes to.  Exposed
  /// for tests + audit logging — production code should not depend
  /// on this string shape.
  String get slot => _slot;
}

/// Build the SecureStorage slot for a brain endpoint.  We hash the
/// endpoint to a short hex digest so the key length stays bounded
/// regardless of operator-supplied URL shape (some self-hosted
/// brains carry long path prefixes).
///
/// FNV-1a is used because it's tiny, dependency-free, and the input
/// space (a handful of brain endpoints per device) is far below the
/// regime where collisions matter — collisions only mean two brains
/// share a cursor, and the cursor is monotonic so the worst case is
/// a single duplicate notification on first fetch after re-pair.
String _slotFor(String brainEndpoint) {
  final bytes = utf8.encode(brainEndpoint);
  // FNV-1a 64-bit
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in bytes) {
    hash = (hash ^ BigInt.from(b)) & mask;
    hash = (hash * prime) & mask;
  }
  final hex = hash.toRadixString(16).padLeft(16, '0');
  return 'helm.lastSeenTs.$hex';
}

```
