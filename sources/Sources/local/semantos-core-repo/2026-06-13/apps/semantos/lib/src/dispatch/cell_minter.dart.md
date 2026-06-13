---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/dispatch/cell_minter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.118097+00:00
---

# apps/semantos/lib/src/dispatch/cell_minter.dart

```dart
/// cell_minter.dart — the mint surface the [IntentDispatcher] depends on.
///
/// Implemented by BOTH transports:
///   - BrainRpcClient  → `cells.mint` over the unified `/api/v1/rpc` WSS
///     channel (the M1.7b path — what the shell wires at boot).
///   - BrainHttpClient → legacy `POST /api/v1/cells` (kept only for
///     read/info surfaces not yet migrated; no longer the dispatcher's minter).
///
/// Decoupling the dispatcher from the concrete client behind this interface
/// is what lets M1.7b point mints at the RPC channel without touching the
/// dispatch logic, and what lets tests inject a fake minter.
library;

import '../brain/brain_http_client.dart' show MintCellResult;

// Re-export so consumers depend on this seam, not the HTTP client, for the
// mint result type.
export '../brain/brain_http_client.dart' show MintCellResult;

abstract interface class CellMinter {
  /// Unsigned mint — body `{typeHashHex, payload}`.
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  });

  /// Operator-signed (sovereign) mint — adds `{signatureHex, signerCertIdHex}`.
  /// The brain re-derives the payload digest, recovers the signer pubkey, and
  /// matches it against `signerCertIdHex` before persisting (#828).
  Future<MintCellResult> mintCellSigned({
    required String typeHashHex,
    required Map<String, dynamic> payload,
    required String signatureHex,
    required String signerCertIdHex,
  });
}

```
