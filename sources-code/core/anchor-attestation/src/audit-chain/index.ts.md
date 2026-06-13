---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/src/audit-chain/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.941210+00:00
---

# core/anchor-attestation/src/audit-chain/index.ts

```ts
/**
 * @semantos/anchor-attestation/audit-chain — L12 (CW Lift Matrix).
 *
 * Append-only tamper-evident audit chain with deterministic per-link
 * key derivation via L11. Patents cited: US12375287B2, EP3259724B1
 * (Craig Wright).
 *
 * Layered above @plexus/vendor-sdk's L11 primitives (deriveSegment +
 * deriveSegmentPub). This package owns no crypto of its own — it just
 * binds {entityId, seq, canonical} into a chain and signs entryHash
 * with a derived per-link key.
 *
 * Distinct from cell-routing transport (paid-pubsub): the audit chain
 * RECORDS, transport DELIVERS. See docs/canon/audit-chain-vs-transport-layer.md.
 *
 * Usage:
 *   import {
 *     genesisSignedEntry,
 *     appendSignedEntry,
 *     verifyAuditChain,
 *   } from '@semantos/anchor-attestation/audit-chain';
 *
 *   const g  = genesisSignedEntry('oddjobz:invoice:abc', payload0, masterPriv);
 *   const e1 = appendSignedEntry(g.entry,  payload1, masterPriv);
 *   const e2 = appendSignedEntry(e1.entry, payload2, masterPriv);
 *
 *   const result = verifyAuditChain({
 *     entries: [g, e1, e2],
 *     masterPubKeyHex: masterPriv.toPublicKey().toDER('hex'),
 *   });
 */

export {
  AUDIT_CHAIN_MAGIC,
  AUDIT_CHAIN_VERSION,
  AUDIT_CHAIN_DOMAIN_STR,
  ZERO_HASH,
  ENTRY_HASH_SIZE,
  CANONICAL_HASH_SIZE,
  type AuditChainEntry,
  type SignedAuditChainEntry,
  type LinkSegmentDeriver,
  type ChainVerifyResult,
} from './types.js';

export {
  linkSegment,
  computeCanonicalHash,
  computeEntryHash,
  genesisEntry,
  appendEntry,
  signEntry,
  genesisSignedEntry,
  appendSignedEntry,
} from './append.js';

export {
  verifyAuditChain,
  type VerifyAuditChainInput,
} from './verify.js';

```
