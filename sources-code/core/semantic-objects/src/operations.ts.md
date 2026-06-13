---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/operations.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.936359+00:00
---

# core/semantic-objects/src/operations.ts

```ts
/**
 * Operations on the semantic-objects substrate.
 *
 * Every domain extension (calendar, OJT kernel, BRAP assessment, …)
 * composes mutations from these primitives:
 *
 *   createObject  — register a new aggregate
 *   appendPatch   — write a change event (optimistic-concurrency checked)
 *   listPatches   — read patches for an aggregate
 *   foldState     — reduce a patch stream to current state
 *   addParticipant / removeParticipant / listParticipants
 */
import { and, asc, desc, eq, gt, lt, isNull, sql } from 'drizzle-orm';
import {
  semObjects,
  semObjectPatches,
  semParticipants,
  type SemObjectPatch,
  type SemObject,
  type SemParticipant,
} from './schema.js';
import {
  ObjectNotFoundError,
  StaleStateHashError,
  type Database,
  type IdentityKind,
  type ObjectPatch,
  type ObjectRow,
  type ParticipantRole,
  type ParticipantRow,
} from './types.js';
import { computeNewStateHash } from './hash.js';

// ────────────────────────────────────────────────────────────
// ID generation
// ────────────────────────────────────────────────────────────

export function newObjectId(prefix = 'obj'): string {
  return `${prefix}_${randomSegment()}`;
}
export function newPatchId(): string {
  return `patch_${randomSegment()}`;
}
export function newParticipantId(): string {
  return `part_${randomSegment()}`;
}
function randomSegment(): string {
  const g = globalThis as { crypto?: { randomUUID?: () => string } };
  if (g.crypto?.randomUUID) return g.crypto.randomUUID().replace(/-/g, '');
  return `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

// ────────────────────────────────────────────────────────────
// createObject
// ────────────────────────────────────────────────────────────

export interface CreateObjectInput<P = unknown> {
  id?: string;
  objectKind: string;
  payload: P;
  parentId?: string;
  createdByCertId?: string;
}

export async function createObject<P>(
  db: Database,
  input: CreateObjectInput<P>,
): Promise<ObjectRow<P>> {
  const row = {
    id: input.id ?? newObjectId(input.objectKind),
    objectKind: input.objectKind,
    parentId: input.parentId ?? null,
    payload: input.payload as unknown as Record<string, unknown>,
    createdByCertId: input.createdByCertId ?? null,
    currentStateHash: null,
    currentVersion: 0,
  };
  const [inserted] = await db.insert(semObjects).values(row).returning();
  return toObjectRow<P>(inserted);
}

export async function getObject<P>(
  db: Database,
  objectId: string,
): Promise<ObjectRow<P> | null> {
  const rows = await db.select().from(semObjects).where(eq(semObjects.id, objectId)).limit(1);
  const r = rows[0];
  if (!r) return null;
  return toObjectRow<P>(r);
}

// ────────────────────────────────────────────────────────────
// appendPatch (with optimistic concurrency)
// ────────────────────────────────────────────────────────────

export interface AppendPatchInput<D = unknown> {
  objectId: string;
  kind: string;
  delta: D;
  /** If provided, enforced against the object's current_state_hash. */
  expectedPrevStateHash?: string | null;
  /** Who authored this patch (e.g. the hat id). */
  facetId?: string;
  facetCapabilities?: number[];
  lexicon?: string;
  authorObjectId?: string;
  /** Defaults to Date.now(). */
  timestamp?: number;
}

/**
 * Append a patch to an object's stream.
 *
 * Optimistic-concurrency model:
 *   1. Read the object's `current_state_hash`.
 *   2. If `expectedPrevStateHash` is provided and doesn't match, throw.
 *   3. Compute the new state hash deterministically.
 *   4. Write the patch with `prev_state_hash` = current, `new_state_hash` = new.
 *   5. Update the object's `current_state_hash` to the new hash.
 *      — Guarded: WHERE current_state_hash = prev AND current_version = v
 *        so two concurrent writers both snapshotting the same prev hash
 *        will have ONE update succeed and the OTHER update zero rows,
 *        at which point the loser re-reads and retries or reports conflict.
 *
 * If `expectedPrevStateHash` is omitted, the caller is saying "append
 * without concurrency check" — use carefully.
 */
export async function appendPatch<D>(
  db: Database,
  input: AppendPatchInput<D>,
): Promise<ObjectPatch<D>> {
  const runWithTx = async (tx: Database): Promise<ObjectPatch<D>> => {
    const rows = await tx
      .select({
        currentStateHash: semObjects.currentStateHash,
        currentVersion: semObjects.currentVersion,
      })
      .from(semObjects)
      .where(eq(semObjects.id, input.objectId))
      .limit(1);
    const existing = rows[0];
    if (!existing) throw new ObjectNotFoundError(input.objectId);

    const prev = existing.currentStateHash ?? null;
    if (
      input.expectedPrevStateHash !== undefined &&
      input.expectedPrevStateHash !== prev
    ) {
      throw new StaleStateHashError(input.expectedPrevStateHash, prev);
    }

    const timestamp = input.timestamp ?? Date.now();
    const newHash = computeNewStateHash({
      prevStateHash: prev,
      kind: input.kind,
      delta: input.delta,
      timestamp,
    });

    const patchRow = {
      id: newPatchId(),
      objectId: input.objectId,
      kind: input.kind,
      timestamp,
      delta: input.delta as unknown as Record<string, unknown>,
      facetId: input.facetId ?? null,
      facetCapabilities: input.facetCapabilities ?? null,
      lexicon: input.lexicon ?? null,
      prevStateHash: prev,
      newStateHash: newHash,
      authorObjectId: input.authorObjectId ?? null,
      linearity: 'LINEAR' as const,
      consumed: true,
    };

    const [insertedPatch] = await tx.insert(semObjectPatches).values(patchRow).returning();

    // Guarded update — if anyone else advanced the object between our
    // read and this write, this affects 0 rows.
    const updated = await tx
      .update(semObjects)
      .set({
        currentStateHash: newHash,
        currentVersion: existing.currentVersion + 1,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(semObjects.id, input.objectId),
          eq(semObjects.currentVersion, existing.currentVersion),
          prev === null
            ? isNull(semObjects.currentStateHash)
            : eq(semObjects.currentStateHash, prev),
        ),
      )
      .returning({ id: semObjects.id });

    if (updated.length === 0) {
      // Contention race — someone else advanced after our read.
      throw new StaleStateHashError(prev, null);
    }

    return toObjectPatch<D>(insertedPatch);
  };

  if (typeof (db as unknown as { transaction?: unknown }).transaction === 'function') {
    return (
      db as unknown as {
        transaction: (fn: (tx: Database) => Promise<ObjectPatch<D>>) => Promise<ObjectPatch<D>>;
      }
    ).transaction(runWithTx);
  }
  return runWithTx(db);
}

// ────────────────────────────────────────────────────────────
// listObjectsByKind
// ────────────────────────────────────────────────────────────

export interface ListObjectsByKindFilter {
  /** Filter by objectKind. */
  objectKind: string;
  /** Optional JSON payload field equality filter.
   *  All provided entries must match (AND semantics). */
  payloadFilters?: ReadonlyArray<{ field: string; value: string }>;
  /** Maximum rows to return. */
  limit?: number;
  /** Order by createdAt. Defaults to 'asc'. */
  order?: 'asc' | 'desc';
}

/**
 * List all `sem_objects` rows of a given `objectKind`, with optional
 * JSON payload field filters.
 *
 * Payload filters use the Postgres `->>` text extraction operator
 * (`payload->>'field' = 'value'`), so only top-level scalar string
 * fields are filterable this way. Use `.payloadFilters` with
 * `{ field: 'conversationId', value: someId }` to scope a read to
 * a single conversation.
 *
 * Backed by the `sem_objects_kind_idx` index on `object_kind`.
 */
export async function listObjectsByKind<P = unknown>(
  db: Database,
  filter: ListObjectsByKindFilter,
): Promise<ObjectRow<P>[]> {
  const orderFn = (filter.order ?? 'asc') === 'desc' ? desc : asc;
  const conds = [eq(semObjects.objectKind, filter.objectKind)];
  if (filter.payloadFilters) {
    for (const { field, value } of filter.payloadFilters) {
      conds.push(sql`${semObjects.payload}->>${field} = ${value}` as ReturnType<typeof eq>);
    }
  }
  let q = db
    .select()
    .from(semObjects)
    .where(and(...conds))
    .orderBy(orderFn(semObjects.createdAt));
  if (filter.limit !== undefined) q = q.limit(filter.limit) as typeof q;
  const rows = await q;
  return rows.map((r) => toObjectRow<P>(r));
}

// ────────────────────────────────────────────────────────────
// listPatches + foldState
// ────────────────────────────────────────────────────────────

export interface ListPatchesFilters {
  objectId: string;
  since?: Date;
  until?: Date;
  limit?: number;
  /** Defaults to asc (oldest-first) — correct for folds. */
  order?: 'asc' | 'desc';
}

export async function listPatches<D>(
  db: Database,
  f: ListPatchesFilters,
): Promise<ObjectPatch<D>[]> {
  const conds = [eq(semObjectPatches.objectId, f.objectId)];
  if (f.since) conds.push(gt(semObjectPatches.createdAt, f.since));
  if (f.until) conds.push(lt(semObjectPatches.createdAt, f.until));
  const orderFn = (f.order ?? 'asc') === 'desc' ? desc : asc;
  let q = db
    .select()
    .from(semObjectPatches)
    .where(and(...conds))
    .orderBy(orderFn(semObjectPatches.createdAt));
  if (f.limit !== undefined) q = q.limit(f.limit) as typeof q;
  const rows = await q;
  return rows.map((r) => toObjectPatch<D>(r));
}

/**
 * Generic state reducer. Folds a patch stream via the provided reducer.
 * Pure: no IO. Pair with `listPatches` + in-memory fold when you want
 * current state.
 */
export function foldState<S, D>(input: {
  patches: ObjectPatch<D>[];
  initial: S;
  reducer: (state: S, patch: ObjectPatch<D>) => S;
}): S {
  let state = input.initial;
  for (const p of input.patches) state = input.reducer(state, p);
  return state;
}

// ────────────────────────────────────────────────────────────
// Participants
// ────────────────────────────────────────────────────────────

export interface AddParticipantInput {
  objectId: string;
  identityRef: string;
  identityKind?: IdentityKind;
  participantRole: ParticipantRole;
  displayName?: string;
  invitedBy?: string;
}

export async function addParticipant(
  db: Database,
  input: AddParticipantInput,
): Promise<ParticipantRow> {
  const row = {
    id: newParticipantId(),
    objectId: input.objectId,
    identityRef: input.identityRef,
    identityKind: input.identityKind ?? ('cert' as const),
    participantRole: input.participantRole,
    displayName: input.displayName ?? null,
    invitedBy: input.invitedBy ?? null,
  };
  const [inserted] = await db.insert(semParticipants).values(row).returning();
  return toParticipantRow(inserted);
}

export async function removeParticipant(
  db: Database,
  participantId: string,
): Promise<void> {
  await db
    .update(semParticipants)
    .set({ leftAt: new Date() })
    .where(eq(semParticipants.id, participantId));
}

export async function listParticipants(
  db: Database,
  objectId: string,
  opts: { includeLeft?: boolean } = {},
): Promise<ParticipantRow[]> {
  const conds = [eq(semParticipants.objectId, objectId)];
  if (!opts.includeLeft) conds.push(isNull(semParticipants.leftAt));
  const rows = await db.select().from(semParticipants).where(and(...conds));
  return rows.map(toParticipantRow);
}

// ────────────────────────────────────────────────────────────
// Row → domain mappers
// ────────────────────────────────────────────────────────────

function toObjectRow<P>(r: SemObject): ObjectRow<P> {
  return {
    id: r.id,
    objectKind: r.objectKind,
    parentId: r.parentId,
    payload: (r.payload ?? {}) as unknown as P,
    createdByCertId: r.createdByCertId,
    currentStateHash: r.currentStateHash,
    currentVersion: r.currentVersion,
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
  };
}

function toObjectPatch<D>(r: SemObjectPatch): ObjectPatch<D> {
  return {
    id: r.id,
    objectId: r.objectId,
    kind: r.kind,
    timestamp: r.timestamp,
    delta: r.delta as D,
    facetId: r.facetId,
    facetCapabilities: r.facetCapabilities,
    lexicon: r.lexicon,
    prevStateHash: r.prevStateHash,
    newStateHash: r.newStateHash,
    authorObjectId: r.authorObjectId,
    linearity: r.linearity as ObjectPatch<D>['linearity'],
    consumed: r.consumed,
    createdAt: r.createdAt,
  };
}

function toParticipantRow(r: SemParticipant): ParticipantRow {
  return {
    id: r.id,
    objectId: r.objectId,
    identityRef: r.identityRef,
    identityKind: r.identityKind as IdentityKind,
    participantRole: r.participantRole as ParticipantRole,
    displayName: r.displayName,
    invitedBy: r.invitedBy,
    joinedAt: r.joinedAt,
    leftAt: r.leftAt,
    createdAt: r.createdAt,
  };
}

```
