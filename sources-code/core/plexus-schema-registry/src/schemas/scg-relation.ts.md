---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/schemas/scg-relation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.948764+00:00
---

# core/plexus-schema-registry/src/schemas/scg-relation.ts

```ts
/**
 * SCG relation domain schema — RM-082.
 *
 * Provides a stable byte-level projection of an `scg.relation` payload so
 * the relation can be committed via the schema registry the same way
 * commerce and anchor-attestation are. Today's relation rows live in
 * Postgres under `sem_objects.payload` (jsonb) and don't pass through
 * the 2-PDA cell header, but downstream RMs (relation receipts, on-chain
 * anchored relations) will reuse this exact schema to hash the canonical
 * relation into a `domainPayloadRoot`.
 *
 * Registered under `SemantosDomainFlags.SCG_RELATION = 0x0001FE03`
 * (relocated from 0x00010103 — audit B-1, SUBSTRATE_SCHEMA page).
 *
 * Field layout (113 bytes encoded):
 *   - kindByte    u8   @ 0    — RelationKind discriminator (see SCG_RELATION_KIND_BYTES)
 *   - sourceId    u256 @ 1    — 32B sem_objects.id of the source (hex-decoded)
 *   - targetId    u256 @ 33   — 32B sem_objects.id of the target
 *   - amount      u64  @ 65   — smallest-unit amount; 0 for non-money kinds
 *   - currency    u32  @ 73   — 4-byte ASCII currency tag (e.g. "sats", "USD ")
 *   - txAnchor    u256 @ 77   — 32B on-chain anchor; zeroed for unanchored
 *   - attestation bytes(4) @ 109 — first 4 bytes of the attestation digest
 *                                  (full attestation lives in the jsonb payload;
 *                                  the schema only commits to the prefix to
 *                                  keep the encoded width bounded).
 *
 * Future versions can append fields per Schema Registry §6.4 (new version
 * + new typeHash); changing an offset is a BREAKING change and requires a
 * new domainFlag.
 */
import type { DomainSchema } from '../types.js';

export const SCG_RELATION_DOMAIN_FLAG = 0x0001fe03;

export const scgRelationSchemaV1: DomainSchema = {
  domainFlag: SCG_RELATION_DOMAIN_FLAG,
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'kindByte', offset: 0, size: 1, type: 'u8' },
    { name: 'sourceId', offset: 1, size: 32, type: 'u256' },
    { name: 'targetId', offset: 33, size: 32, type: 'u256' },
    { name: 'amount', offset: 65, size: 8, type: 'u64' },
    { name: 'currency', offset: 73, size: 4, type: 'u32' },
    { name: 'txAnchor', offset: 77, size: 32, type: 'u256' },
    { name: 'attestation', offset: 109, size: 4, type: 'bytes' },
  ],
};

/**
 * Discriminator byte values for `RelationKind`. Order MUST match
 * `@semantos/scg-relations::ALL_RELATION_KINDS` (RM-010 + RM-060 + RM-080
 * additions appended). Adding a kind is non-breaking iff it is appended.
 *
 * Mirrored here rather than imported from `@semantos/scg-relations` to
 * keep the schema-registry's dependency surface narrow (the registry is
 * substrate-agnostic and cannot circularly depend on scg-relations).
 */
export const SCG_RELATION_KIND_BYTES = {
  REPLIES_TO: 0x01,
  SUPPORTS: 0x02,
  DISPUTES: 0x03,
  SUPERSEDES: 0x04,
  CITES: 0x05,
  FORKS: 0x06,
  REQUESTS_ACTION: 0x07,
  FULFILLS: 0x08,
  PAYS: 0x09,
  ATTESTS: 0x0a,
  GRANTS_ACCESS: 0x0b,
  APPROVES: 0x0c,
  // RM-060
  ESCROW_LOCKS: 0x0d,
  ESCROW_RELEASES: 0x0e,
  // RM-080
  MERGES: 0x0f,
  // D-SCG-persona-projection — pub-sub group membership.
  SUBSCRIBES_TO: 0x10,
} as const;

export type ScgRelationKindName = keyof typeof SCG_RELATION_KIND_BYTES;

/** Encoded scg-relation payload shape — what
 *  `encodePayload(scgRelationSchemaV1, ...)` expects. The index signature
 *  matches `encodePayload`'s `Record<string, unknown>` parameter so callers
 *  pass this shape directly without casting. */
export interface ScgRelationPayloadEncoded {
  /** Byte from `SCG_RELATION_KIND_BYTES`. */
  kindByte: number;
  /** 32B hex-decoded sem_objects.id. */
  sourceId: Uint8Array;
  /** 32B hex-decoded sem_objects.id. */
  targetId: Uint8Array;
  /** Smallest-unit amount; 0 for non-money kinds. */
  amount: number | bigint;
  /** 4-byte little-endian ASCII currency tag; 0 for non-money kinds. */
  currency: number;
  /** 32B anchor; zeroed when unanchored. */
  txAnchor: Uint8Array;
  /** 4-byte prefix of the attestation digest; zeroed when absent. */
  attestation: Uint8Array;
  [key: string]: unknown;
}

/**
 * Convenience builder — fills zeros for the optional fields.
 */
export function scgRelationPayload(input: {
  kind: ScgRelationKindName | number;
  sourceId: Uint8Array;
  targetId: Uint8Array;
  amount?: number | bigint;
  currency?: number;
  txAnchor?: Uint8Array;
  attestation?: Uint8Array;
}): ScgRelationPayloadEncoded {
  return {
    kindByte:
      typeof input.kind === 'string'
        ? SCG_RELATION_KIND_BYTES[input.kind]
        : input.kind,
    sourceId: input.sourceId,
    targetId: input.targetId,
    amount: input.amount ?? 0,
    currency: input.currency ?? 0,
    txAnchor: input.txAnchor ?? new Uint8Array(32),
    attestation: input.attestation ?? new Uint8Array(4),
  };
}

```
