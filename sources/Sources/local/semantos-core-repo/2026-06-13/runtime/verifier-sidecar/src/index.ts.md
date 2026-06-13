---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.084531+00:00
---

# runtime/verifier-sidecar/src/index.ts

```ts
/**
 * @semantos/verifier-sidecar — public API.
 *
 * D-V1: VerifierStub interface + reference implementation.
 * Phase 0.5 — blocks D-V3.
 *
 * Spec source: docs/spec/protocol-v0.5.md §9.5.
 * Textbook: docs/textbook/14-verifier-sidecar.md.
 */

// ── Types ────────────────────────────────────────────────────────────────────
export type {
  Verifier,
  VerificationResult,
  VerificationErrorCode,
  RawSignedBundle,
  Brc52Certificate,
  CapabilityTokenRef,
  SpvProvider,
  NonceCache,
  BrcVerifierOptions,
} from "./types.js";

// ── Reference implementation ─────────────────────────────────────────────────
export { BrcVerifier, VerifierStub, constantTimeEqual } from "./verifier.js";

// ── Nonce cache ───────────────────────────────────────────────────────────────
export { InMemoryNonceCache } from "./nonce-cache.js";

// ── HTTP server entry-point (D-V3) ────────────────────────────────────────────
//
// Closes the library/service gap between D-V1 and D-V2: D-V1 shipped the
// verifier as a TS library; D-V2 codified a per-node sidecar process on
// port 8787 with `GET /healthz`; D-V3 binds the library behind that
// HTTP surface so World Host can reach it over loopback.
export {
  VerifierSidecarServer,
  DEFAULT_PORT,
  DEFAULT_BIND,
} from "./server.js";
export type {
  VerifierSidecarServerOptions,
  VerifyRequestBody,
  VerifyResponseBody,
} from "./server.js";

// ── BCA derivation (server-side) ─────────────────────────────────────────────
//
// The HTTP /verify response returns a BCA derived from the verified cert's
// subjectPublicKey so World Host doesn't have to re-derive on the Elixir
// side. This is a minimum-viable port of `core/cell-engine/src/bca.zig`;
// the full library is the D-A0 deliverable.
export { deriveBcaFromPubkey } from "./bca.js";

```
