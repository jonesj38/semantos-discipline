---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/cartridge_selection_store.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.901606+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/cartridge_selection_store.dart

```dart
// CartridgeSelectionStore — operator-facing shell preferences.
//
// Persists which cartridge the operator was last using and whether the
// first-launch welcome flow has completed.  Backed by [SecureStore] for
// now (keychain on iOS, encrypted SharedPreferences on Android — same
// storage layer the rest of the shell uses for credentials).
//
// **Migration note.** Per the `config-as-intents` canon
// (docs/design/SHELL-CARTRIDGE-MODEL.md §9 and the corresponding memory
// note), shell preferences should ultimately flow as cells via
// verb.dispatch — not as keychain reads.  A follow-up commit will:
//   1. Ship a `shell-config` cartridge with the cell-type schemas
//      (`shell.config.welcomed.v0`, `shell.config.default_cartridge.v0`).
//   2. Replace SecureStore read/write here with REPL cell-query + mint
//      against that cartridge.
// SecureStore is the offline-first fallback chosen for v1 to unblock the
// composition refactor without also having to install a new brain
// cartridge.  Both backends will co-exist during migration so the
// switcher works even when the brain is unreachable.

import '../identity/child_cert_store.dart';

/// Storage keys used by this store.  Namespaced under `shell.` so they
/// don't collide with anything else that calls into the same SecureStore.
class _Keys {
  static const welcomed = 'shell.welcomed.v0';
  static const lastUsedCartridgeId = 'shell.lastUsedCartridgeId.v0';
}

class CartridgeSelectionStore {
  CartridgeSelectionStore({required SecureStore secureStore})
      : _secureStore = secureStore;

  final SecureStore _secureStore;

  /// True if the operator has completed the first-launch welcome flow.
  /// Null-or-empty value → not yet welcomed.
  Future<bool> isWelcomed() async {
    final v = await _secureStore.read(_Keys.welcomed);
    return v == '1';
  }

  /// Mark the welcome flow as complete.  Idempotent.
  Future<void> markWelcomed() async {
    await _secureStore.write(_Keys.welcomed, '1');
  }

  /// The cartridge id the operator was last interacting with.  Null on
  /// first launch (drives the welcome flow to ask for a default).
  Future<String?> lastUsedCartridgeId() async {
    final v = await _secureStore.read(_Keys.lastUsedCartridgeId);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  /// Persist the cartridge the operator just switched to.  ShellNav
  /// calls this on every cartridge change so the next cold start
  /// resumes where they left off.
  Future<void> setLastUsedCartridgeId(String id) async {
    await _secureStore.write(_Keys.lastUsedCartridgeId, id);
  }

  /// Reset everything — used by the "re-run welcome" affordance in
  /// settings and by the dev tooling tear-down path.
  Future<void> reset() async {
    await _secureStore.delete(_Keys.welcomed);
    await _secureStore.delete(_Keys.lastUsedCartridgeId);
  }
}

```
