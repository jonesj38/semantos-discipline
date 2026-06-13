---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.817056+00:00
---

# core/scg-relations/src/types.ts

```ts
/**
 * SCG relation primitive — typed edges between sem_objects rows.
 *
 * A relation is itself a `sem_objects` row of `objectKind='scg.relation'`,
 * inheriting identity binding, patches, hashing, and versioning from the
 * existing substrate. No schema migration.
 *
 * Canonical kinds are the Phase-1 set declared in SCG §3.1. Phase-3
 * (RM-060) extends with `ESCROW_LOCKS` / `ESCROW_RELEASES`; Phase-5
 * (RM-080) extends with `MERGES`.
 */
import type { ObjectRow } from '@semantos/semantic-objects';

/** `objectKind` discriminator used on the `sem_objects` row. */
export const RELATION_OBJECT_KIND = 'scg.relation';

/**
 * Canonical relation kinds. String-literal union so the type system
 * enforces exhaustiveness in switches and pattern matches.
 *
 * Phase-1 (RM-010) shipped the 12 discourse/governance moves. RM-060
 * adds `ESCROW_LOCKS` / `ESCROW_RELEASES` (money-bearing). RM-080 adds
 * `MERGES` (branching). `FORKS` and `PAYS` were already in the Phase-1
 * set; RM-060 expands the payload shape for `PAYS` (amount / currency /
 * txAnchor), and RM-080 wires `forkSubgraph` / `mergeSubgraph` on top
 * of `FORKS` + `MERGES`.
 */
export type RelationKind =
  | 'REPLIES_TO'
  | 'SUPPORTS'
  | 'DISPUTES'
  | 'SUPERSEDES'
  | 'CITES'
  | 'FORKS'
  | 'REQUESTS_ACTION'
  | 'FULFILLS'
  | 'PAYS'
  | 'ATTESTS'
  | 'GRANTS_ACCESS'
  | 'APPROVES'
  // RM-060 — money-bearing kinds (Phase 3 economic primitives).
  | 'ESCROW_LOCKS'
  | 'ESCROW_RELEASES'
  // RM-080 — branching (Phase 5).
  | 'MERGES'
  // D-OJ-conv-entity-anchoring — anchors a conversation turn to the
  // job/site/customer entity it concerns. source = turn sem_objects.id,
  // target = entity (job/site/customer) sem_objects.id. See
  // `docs/design/ODDJOBZ-CONVERSATION-ARCHITECTURE.md` §7 + §11.
  | 'BELONGS_TO_ENTITY'
  // D-SCG-persona-projection — pub-sub group membership. source =
  // identity-anchored persona cell, target = type-path group cell.
  // Folded into PersonaProjection.groups by projectPersona.
  | 'SUBSCRIBES_TO';

/** Ordered list of all kinds; used by `relationLexicon`. */
export const ALL_RELATION_KINDS: ReadonlyArray<RelationKind> = [
  'REPLIES_TO',
  'SUPPORTS',
  'DISPUTES',
  'SUPERSEDES',
  'CITES',
  'FORKS',
  'REQUESTS_ACTION',
  'FULFILLS',
  'PAYS',
  'ATTESTS',
  'GRANTS_ACCESS',
  'APPROVES',
  'ESCROW_LOCKS',
  'ESCROW_RELEASES',
  'MERGES',
  'BELONGS_TO_ENTITY',
  'SUBSCRIBES_TO',
] as const;

/**
 * Payload shape for an `scg.relation` row. Mirrors what gets serialised
 * into `sem_objects.payload` (jsonb).
 *
 * Money-bearing kinds (`PAYS`, `ESCROW_LOCKS`, `ESCROW_RELEASES`) carry
 * `amount` / `currency` / `txAnchor` directly on the payload (RM-060).
 * The fields are optional so non-money kinds don't have to populate
 * them. `txAnchor` references an on-chain anchor cell (RM-042) when
 * the payment is anchored on BSV.
 */
export interface RelationPayload {
  kind: RelationKind;
  /** `sem_objects.id` of the source. */
  sourceId: string;
  /** `sem_objects.id` of the target. */
  targetId: string;
  /** Optional attestation signature from the active identity. Carried as
   *  hex; the verification port is bound separately (RM-022). */
  attestation?: string;
  /** RM-060 — money-bearing relation amount (smallest unit, e.g. satoshis
   *  for BSV, cents for AUD). Required for `PAYS` / `ESCROW_LOCKS` /
   *  `ESCROW_RELEASES`; ignored for other kinds. */
  amount?: number;
  /** RM-060 — ISO 4217-ish currency code (e.g. 'BSV', 'AUD'). */
  currency?: string;
  /** RM-060 — `sem_objects.id` of the on-chain anchor-attestation cell
   *  (see `@semantos/anchor-attestation`). Optional even on money kinds:
   *  a payment relation that's awaiting on-chain confirmation has the
   *  amount but no txAnchor yet. */
  txAnchor?: string;
  /** Free-form extension fields for kind-specific data not covered by the
   *  named slots above. */
  extra?: Record<string, unknown>;
}

/**
 * A relation row. Specialisation of `ObjectRow<P>` from semantic-objects.
 *
 * The `objectKind` field will always be `RELATION_OBJECT_KIND` for rows
 * returned by `createRelation` / `listRelations*`.
 */
export type RelationRow = ObjectRow<RelationPayload>;

/**
 * Derived view of a relation — not stored. Useful for graph projections
 * (RM-051 / RM-052) that don't care about the underlying patch stream.
 */
export interface RelationEdge {
  id: string;
  kind: RelationKind;
  sourceId: string;
  targetId: string;
  createdAt: Date;
  attestation: string | undefined;
}

/** Typeguard: is an `ObjectRow<unknown>` a relation row? */
export function isRelationRow(
  row: ObjectRow<unknown>,
): row is RelationRow {
  return row.objectKind === RELATION_OBJECT_KIND;
}

```
