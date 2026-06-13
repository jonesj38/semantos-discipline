---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/node_target.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.012934+00:00
---

# platforms/flutter/semantos_core/lib/src/node_target.dart

```dart
/// Identifies the runtime target the shell is booting into.
///
/// Determines which adapter set the [NodeResolver] picks for wallet,
/// kernel, STT, and identity custody. Conceptually:
///
///   - native — full sovereign stack: FFI wallet, on-device LLM/STT,
///     Keychain-grade identity custody, offline-capable kernel.
///   - pwa    — thin remote stack: brain-paired wallet, Web Speech STT,
///     IndexedDB identity (recoverable via Plexus), online-only by
///     default (WASM kernel optional for offline read).
///
/// A single Flutter codebase compiles for both; the difference is the
/// adapter tuple [NodeResolver] returns at boot.
enum NodeTarget {
  native,
  pwa,
}

```
