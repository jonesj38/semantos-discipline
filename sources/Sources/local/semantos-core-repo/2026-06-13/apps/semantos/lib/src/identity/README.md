---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/identity/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.111389+00:00
---

# identity — canonical PWA substrate primitive

**Track**: C1 (PWA Primitive Forklift). First move 2026-05-27.
**Source**: forklifted from `apps/semantos/lib/src/identity/`.

## What's here (first move — pure-Dart core only)

| File | Purpose |
|------|---------|
| `auth_state.dart` | Mobile auth state machine (authenticated / unauthenticated / re-auth-needed) |
| `cell_signer.dart` | Pure-Dart ECDSA-secp256k1-sha256 cell signer matching brain `signed_bundle.zig::verifySignature` |
| `child_cert_store.dart` | Persists/retrieves BRC-42 child cert + brain endpoints + bearer token via an adapter contract (no Flutter import) |
| `secure_signing_key.dart` | Adapter abstraction for secure-enclave-backed signing (no Flutter import) |

All four files are pure Dart — no `package:flutter/*` imports. They depend only on `dart:*` and `pointycastle:*`.

## What's deferred (second move)

The two adapter files that bind to Flutter platform channels:
- `flutter_secure_store_adapter.dart` (uses `flutter_secure_storage`)
- `platform_secure_signing_key_adapter.dart` (uses `package:flutter/services.dart` MethodChannel)

These need to route through the shell's existing `semantos_shell_native_identity` sub-package per the PWA-WASM-BUILD pattern (keeps `flutter_secure_storage_web` out of the wasm graph). Wiring them is the second C1 move.

## Status vs C7 golden slice

The slice needs the identity substrate at:
- **Layer 5** (cell): `cell_signer.devicePubFromPriv` derives the `OWNER_ID` header byte range.
- **Layer 6** (wallet sign): `cell_signer.signCellPayload` produces the secp256k1 sig over sha256(cell-hash).

Both are present here, but no caller in the canonical shell wires them yet. The C1 second move (adapters + main.dart wiring) closes that.

Re-run `tests/canonicalization/golden-slice/v1_release.dart` after the second move — layers 5 + 6 should narrow from "primitive not present" to "primitive present but not wired into Bootstrap".
