---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/schema.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.936076+00:00
---

# core/semantic-objects/src/schema.ts

```ts
/**
 * @semantos/semantic-objects — canonical drizzle schema.
 *
 * Four tables form the universal patch substrate every semantos domain
 * extension writes into:
 *
 * - `sem_objects`          — the aggregate rows (schedule, conversation,
 *                            job, risk-assessment, hat, …). Each row owns
 *                            a patch stream. `current_state_hash` is the
 *                            tip of that stream.
 * - `sem_object_patches`   — append-only change events. Each patch has
 *                            `prev_state_hash` (optimistic concurrency)
 *                            and `new_state_hash` (becomes the next tip).
 * - `sem_object_states`    — optional snapshot rows. For objects with
 *                            expensive folds you can checkpoint a folded
 *                            state here and fold forward from it.
 * - `sem_participants`     — access list for multi-user + federation.
 *                            Each row says "this cert can participate in
 *                            this object at this role".
 *
 * Column shapes align with OJT's `src/lib/semantos-kernel/schema.core.ts`
 * so the two DBs can exchange patches via signed bundles.
 */
import {
  boolean,
  index,
  integer,
  jsonb,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  varchar,
  bigint,
  smallint,
} from 'drizzle-orm/pg-core';

/**
 * sem_objects — one row per aggregate.
 */
export const semObjects = pgTable(
  'sem_objects',
  {
    id: text('id').primaryKey(),
    objectKind: varchar('object_kind', { length: 64 }).notNull(),
    parentId: text('parent_id'),
    payload: jsonb('payload').notNull().default({}),
    createdByCertId: varchar('created_by_cert_id', { length: 64 }),
    currentStateHash: varchar('current_state_hash', { length: 64 }),
    currentVersion: integer('current_version').notNull().default(0),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => ({
    kindIdx: index('sem_objects_kind_idx').on(t.objectKind),
    parentIdx: index('sem_objects_parent_idx').on(t.parentId),
  }),
);

/**
 * sem_object_patches — append-only change log.
 *
 * Column names chosen to match OJT's pre-existing `sem_object_patches`
 * (with the OJT-PHASE-1 federation additions: timestamp, facet_id,
 * facet_capabilities, lexicon).
 */
export const semObjectPatches = pgTable(
  'sem_object_patches',
  {
    id: text('id').primaryKey(),
    objectId: text('object_id')
      .notNull()
      .references(() => semObjects.id, { onDelete: 'cascade' }),
    kind: varchar('kind', { length: 64 }).notNull(),
    /** Unix ms at author time. Nullable for legacy rows. */
    timestamp: bigint('timestamp', { mode: 'number' }),
    /** The canonical patch payload. Shape is domain-specific. */
    delta: jsonb('delta').notNull(),
    /** Optional: which hat authored. */
    facetId: text('facet_id'),
    /** Optional: bitflag capabilities claimed at authoring. */
    facetCapabilities: integer('facet_capabilities').array(),
    /** Optional: semantos-sir lexicon this patch belongs to. */
    lexicon: varchar('lexicon', { length: 100 }),
    prevStateHash: varchar('prev_state_hash', { length: 64 }),
    newStateHash: varchar('new_state_hash', { length: 64 }).notNull(),
    authorObjectId: text('author_object_id'),
    /** Linearity of the delta: LINEAR | AFFINE | RELEVANT | FUNGIBLE. */
    linearity: varchar('linearity', { length: 16 }).notNull().default('LINEAR'),
    consumed: boolean('consumed').notNull().default(true),
    consumedAt: timestamp('consumed_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => ({
    objectIdx: index('sem_object_patches_object_idx').on(t.objectId, t.createdAt),
    hashIdx: index('sem_object_patches_new_hash_idx').on(t.newStateHash),
    kindIdx: index('sem_object_patches_kind_idx').on(t.kind),
  }),
);

/**
 * sem_object_states — optional snapshot/checkpoint rows for objects with
 * expensive folds. Not used by every domain; present here so consumers
 * can opt in.
 */
export const semObjectStates = pgTable(
  'sem_object_states',
  {
    id: text('id').primaryKey(),
    objectId: text('object_id')
      .notNull()
      .references(() => semObjects.id, { onDelete: 'cascade' }),
    version: integer('version').notNull(),
    stateHash: varchar('state_hash', { length: 64 }).notNull(),
    prevStateHash: varchar('prev_state_hash', { length: 64 }),
    payload: jsonb('payload').notNull(),
    payloadSize: integer('payload_size'),
    createdBy: varchar('created_by', { length: 64 }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => ({
    versionIdx: uniqueIndex('sem_object_states_version_idx').on(t.objectId, t.version),
  }),
);

/**
 * sem_participants — access list. Who can read / write / admin an object.
 *
 * `identity_kind` values: 'cert' (BSV cert id), 'phone', 'email', 'bca'.
 * The bot's identity adapter resolves an incoming request to a cert id
 * and matches against the rows here.
 */
export const semParticipants = pgTable(
  'sem_participants',
  {
    id: text('id').primaryKey(),
    objectId: text('object_id')
      .notNull()
      .references(() => semObjects.id, { onDelete: 'cascade' }),
    identityRef: text('identity_ref').notNull(),
    identityKind: varchar('identity_kind', { length: 16 }).notNull().default('cert'),
    /** 'admin' | 'writer' | 'reader'. */
    participantRole: varchar('participant_role', { length: 16 }).notNull(),
    displayName: text('display_name'),
    invitedBy: text('invited_by'),
    joinedAt: timestamp('joined_at', { withTimezone: true }).defaultNow(),
    leftAt: timestamp('left_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => ({
    objectIdx: index('sem_participants_object_idx').on(t.objectId),
    identityIdx: index('sem_participants_identity_idx').on(t.identityRef, t.identityKind),
  }),
);

// ── Inferred types ───────────────────────────────────────────────────

export type SemObject = typeof semObjects.$inferSelect;
export type NewSemObject = typeof semObjects.$inferInsert;
export type SemObjectPatch = typeof semObjectPatches.$inferSelect;
export type NewSemObjectPatch = typeof semObjectPatches.$inferInsert;
export type SemObjectState = typeof semObjectStates.$inferSelect;
export type NewSemObjectState = typeof semObjectStates.$inferInsert;
export type SemParticipant = typeof semParticipants.$inferSelect;
export type NewSemParticipant = typeof semParticipants.$inferInsert;

// Unused-import silence
void smallint;

```
