---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-contracts/src/domain-flags.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.821207+00:00
---

# core/plexus-contracts/src/domain-flags.ts

```ts
/**
 * Domain flag namespace boundaries.
 *
 * Per Plexus Technical Requirements v1.3 §30 + Client Requirements v2.1
 * §2.2.2, the 4-byte (uint32) functional-domain space is a THREE-tier
 * partition:
 *   - 0x00000001–0x000000FF  Tier 1  Plexus reserved (well-known)
 *   - 0x00000100–0x0000FFFF  Tier 2  Extended Plexus
 *   - 0x00010000–0xFFFFFFFF  Tier 3  Operator / client sovereignty
 *
 * R-1 (audit 2026-05-16-domain-flag-vs-plexus-derivation §4a): this
 * module previously defined a divergent TWO-tier collapse
 * (`PLEXUS_RESERVED_MAX = 0x0000ffff`) that contradicted the canonical
 * `@semantos/protocol-types` `namespace.ts` (where `PLEXUS_RESERVED_MAX
 * = 0x000000ff`) AND the Zig kernel
 * (`constants.DOMAIN_FLAG_PLEXUS_RESERVED_MAX = 255`). Same symbol
 * name, two different values across sibling modules — a real defect.
 *
 * The single source of truth is now `namespace.ts`. This module
 * re-exports the canonical tier boundaries + predicates. `CLIENT_BASE`
 * is retained as a deprecated alias of `OPERATOR_BASE` for existing
 * plexus-contracts consumers; the legacy two-tier
 * `PLEXUS_RESERVED_MAX = 0xFFFF` meaning ("max Plexus-owned flag,
 * standard + extended") is now spelled `EXTENDED_PLEXUS_MAX`.
 */

export {
  /** Tier-1 inclusive max — Plexus reserved (single-byte). 0x000000ff. */
  PLEXUS_RESERVED_MAX,
  /** Tier-2 inclusive max — Extended Plexus. 0x0000ffff. (Was the
   *  legacy two-tier `PLEXUS_RESERVED_MAX`.) */
  EXTENDED_PLEXUS_MAX,
  /** Tier-3 inclusive min — operator/client sovereignty. 0x00010000. */
  OPERATOR_BASE,
  /** Inclusive max for any valid uint32 flag. */
  UINT32_MAX,
  isPlexusReserved,
  isExtendedPlexus,
  isOperatorSovereign,
  namespaceTier,
  isValidNamespaceFlag,
  type NamespaceTier,
} from '@semantos/protocol-types';

import { OPERATOR_BASE } from '@semantos/protocol-types';

/**
 * @deprecated Use `OPERATOR_BASE` from `@semantos/protocol-types`
 * (or re-exported here). Retained as a value-identical alias
 * (0x00010000) so existing plexus-contracts consumers keep working.
 */
export const CLIENT_BASE = OPERATOR_BASE;

/** Plexus standard domain flags. */
export const PlexusStandardFlags = {
  /** Derive keys for ECDH shared secrets (edge creation). */
  EDGE_CREATION: 0x01,
  /** Sign continuity/ancestry proofs. */
  ATTESTATION: 0x05,
  /** Payment channel funding/settlement. */
  METERING: 0x0a,
  /** Phase 2: Derive ZONE keys for group conversation encryption. */
  ZONE_KEY: 0x0b,
  /** Phase 2: Derive keys for MESSAGING edge channels (BRC-85/86). */
  MESSAGING: 0x0c,
  /** Phase 38: Execute whitelisted host handlers on behalf of the active hat. */
  HOST_EXEC: 0x0d,
} as const;

/** Client-defined domain flags for workbench capabilities. */
export const ClientDomainFlags = {
  VIEW: 0x00010001,
  CREATE: 0x00010002,
  EDIT: 0x00010003,
  DELETE: 0x00010004,
  PUBLISH: 0x00010005,
  GOVERN_VOTE: 0x00010006,
  GOVERN_PROPOSE: 0x00010007,
  STAKE: 0x00010008,
  TRANSFER: 0x00010009,
  ADMIN: 0x0001000a,
  /** Phase 38: Client-side gate for host.exec shell verb. Paired with
   *  PlexusStandardFlags.HOST_EXEC (0x0d) and host-ops.json capability id 11. */
  HOST_EXEC: 0x0001000b,
  /** RM-022 / SCG: authority to create an `scg.relation` row. Checked by
   *  `core/scg-relations/src/operations.ts::createRelation`. */
  RELATION_MINT: 0x0001000c,
  /** RM-022 / SCG: authority to revoke (soft-delete via patch) an
   *  `scg.relation` row. */
  RELATION_REVOKE: 0x0001000d,
} as const;

/**
 * Semantos protocol-level domain identifiers — selected by a cell header's
 * `domain_flag`, drive payload-schema lookup at the Plexus schema registry
 * (RM-012). These are SUBSTRATE-PROTOCOL schema identifiers, distinct from
 * per-extension capability flags.
 *
 * **SUBSTRATE_SCHEMA page `0x0001FE00`–`0x0001FEFF`** (audit
 * `docs/audits/2026-05-16-domain-flag-vs-plexus-derivation.md` B-1).
 * These were historically at `0x000101xx`, which collided head-on with
 * the oddjobz capability page (`cap.oddjobz.quote/dispatch/invoice` =
 * `0x00010101/02/03`). Resolution: the per-extension capability-page
 * convention (loom-shell 0x0001**00**, oddjobz 0x0001**01**, bsv-anchor
 * 0x0001**02**, tessera 0x0001**04** — `core/constants/constants.json`
 * `extensionPages`) is canonical and scales per cartridge; substrate
 * schema identifiers relocate to the dedicated high page `0x0001FE00`
 * so a schema-id can never alias a capability flag. Enforced by
 * `tests/gates/domain-flag-page-registry.test.ts`.
 *
 * Individual entries are applied to this constant by their owning RM:
 *   - SCHEMA_AUTHORITY → RM-012 (schema-registry meta-flag)
 *   - COMMERCE → RM-032 (commerce payload schema)
 *   - ANCHOR_ATTESTATION → RM-042
 *   - SCG_RELATION → RM-082
 *
 * Adding a slot here must register a schema in the same transaction
 * (Plexus Schema Registry §4.1) and stay within `0x0001FExx`.
 */
export const SemantosDomainFlags = {
  /** RM-032a: payload-schema for commerce-shaped cells (formerly the
   *  header's phase/dimension/parentHash/prevStateHash fields). Schema
   *  registered at `@semantos/plexus-schema-registry/schemas/commerce`.
   *  Relocated 0x00010101 → 0x0001FE01 (audit B-1). */
  COMMERCE: 0x0001fe01,
  /** RM-042: anchor-attestation cell type. The cell's payload encodes
   *  the on-chain binding tuple (targetCellId, txid, anchorHeight, vout,
   *  derivationIndex) under `anchorAttestationSchemaV2`. Anchoring a cell
   *  creates an AnchorAttestation cell pointing at it, instead of
   *  mutating the target cell's header. Schema v2 retired the v1
   *  `bumpHash` field (zombie — BRC-74 BUMP carries `blockHeight`
   *  natively, not a 24B Merkle-root variant); the dispatch wire value
   *  here is unchanged.
   *  Schema registered at `@semantos/plexus-schema-registry/schemas/anchor-attestation`.
   *  Relocated 0x00010102 → 0x0001FE02 (audit B-1). */
  ANCHOR_ATTESTATION: 0x0001fe02,
  /** RM-082: SCG typed-relation payload schema. Relations are
   *  `sem_objects` rows of `objectKind='scg.relation'`; their payload
   *  encodes `(kind, sourceId, targetId, attestation?, amount?, currency?, txAnchor?)`.
   *  Schema registered at `@semantos/plexus-schema-registry/schemas/scg-relation`.
   *  Relocated 0x00010103 → 0x0001FE03 (audit B-1). */
  SCG_RELATION: 0x0001fe03,
} as const;

```
