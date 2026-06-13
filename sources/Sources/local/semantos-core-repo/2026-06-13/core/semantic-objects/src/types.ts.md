---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.935801+00:00
---

# core/semantic-objects/src/types.ts

```ts
/**
 * Public TS shapes for the semantic-objects substrate.
 *
 * Generic over domain payloads: every aggregate type parameterises
 * its own `Payload` (for sem_objects) and `Delta` (for patches).
 */
import type { PgDatabase } from 'drizzle-orm/pg-core';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export type Database = PgDatabase<any, any, any>;

/** Roles on the participant access list. */
export type ParticipantRole = 'admin' | 'writer' | 'reader';

/** Identity kinds the participant table understands. */
export type IdentityKind = 'cert' | 'phone' | 'email' | 'bca';

/** Linearity modes — matches semantos-core. */
export type Linearity = 'LINEAR' | 'AFFINE' | 'RELEVANT' | 'FUNGIBLE';

/**
 * A patch on an aggregate. Generic over the `delta` payload shape.
 */
export interface ObjectPatch<D = unknown> {
  id: string;
  objectId: string;
  kind: string;
  timestamp: number | null;
  delta: D;
  facetId: string | null;
  facetCapabilities: number[] | null;
  lexicon: string | null;
  prevStateHash: string | null;
  newStateHash: string;
  authorObjectId: string | null;
  linearity: Linearity;
  consumed: boolean;
  createdAt: Date;
}

/**
 * An aggregate row. Generic over the `payload` shape.
 */
export interface ObjectRow<P = unknown> {
  id: string;
  objectKind: string;
  parentId: string | null;
  payload: P;
  createdByCertId: string | null;
  currentStateHash: string | null;
  currentVersion: number;
  createdAt: Date;
  updatedAt: Date;
}

/**
 * A participant on an aggregate.
 */
export interface ParticipantRow {
  id: string;
  objectId: string;
  identityRef: string;
  identityKind: IdentityKind;
  participantRole: ParticipantRole;
  displayName: string | null;
  invitedBy: string | null;
  joinedAt: Date | null;
  leftAt: Date | null;
  createdAt: Date;
}

/** Error thrown when optimistic concurrency fails. */
export class StaleStateHashError extends Error {
  readonly code = 'STALE_STATE_HASH' as const;
  readonly expected: string | null;
  readonly actual: string | null;
  constructor(expected: string | null, actual: string | null) {
    super(`Stale state hash: expected=${expected}, actual=${actual}`);
    this.name = 'StaleStateHashError';
    this.expected = expected;
    this.actual = actual;
  }
}

/** Error thrown when an object is not found. */
export class ObjectNotFoundError extends Error {
  readonly code = 'OBJECT_NOT_FOUND' as const;
  readonly objectId: string;
  constructor(objectId: string) {
    super(`Semantic object not found: ${objectId}`);
    this.name = 'ObjectNotFoundError';
    this.objectId = objectId;
  }
}

```
