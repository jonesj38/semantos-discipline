---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/cell_signer.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.015528+00:00
---

# platforms/flutter/semantos_core/lib/src/cell_signer.dart

```dart
import 'dart:typed_data';

/// Signs a cell payload. Implementations:
///   - semantos_ffi FfiCellSigner — C ABI bridge (offline).
///   - BrainCellSigner — remote sign via brain HTTP (future).
abstract class CellSigner {
  /// Sign [cellBytes] with the operator's identity key.
  /// Returns a DER-encoded ECDSA signature.
  Future<Uint8List> sign(Uint8List cellBytes);

  /// Returns the operator's compressed identity public key (33 bytes).
  Future<Uint8List> identityPublicKey();
}

```
