---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.937912+00:00
---

# core/anchor-attestation/src/index.ts

```ts
/**
 * @semantos/anchor-attestation — RM-042.
 *
 * Anchoring a cell on-chain produces an AnchorAttestation cell whose
 * payload binds (targetCellId, txid, anchorHeight, vout, derivationIndex)
 * via `anchorAttestationSchemaV2` registered at Plexus. Replaces the
 * pre-RM-042 `OnChainBinding` header region.
 *
 * Schema v2 (current): the v1 layout had a 24B `bumpHash` field that
 * was never read or written outside test scaffolding (BRC-74 BUMP
 * carries `blockHeight` natively, not a 24B Merkle-root variant). v2
 * retires `bumpHash` and promotes `anchor_height: u64` to a
 * first-class queryable field so the brain's reorg substrate can
 * range-query attestations by height.
 *
 * See `docs/PHASE-H-HEADER-CLEANUP-SPEC.md` §4.5 for design rationale.
 */
export * from './types.js';
export * from './operations.js';
export * from './verify-inclusion.js';
export * from './idempotency.js';
export * from './verify-against-chain.js';
// Audit-chain (L12) lives as a subpath; intentionally not flat-exported
// here so callers explicitly opt-in via the `audit-chain` subpath
// (`import { ... } from '@semantos/anchor-attestation/audit-chain'`).
// Re-importing all symbols at the top level would inflate the bundle
// for callers that only need the SPV/idempotency surfaces.

```
