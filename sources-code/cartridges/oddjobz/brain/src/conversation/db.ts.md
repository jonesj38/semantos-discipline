---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/db.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.527396+00:00
---

# cartridges/oddjobz/brain/src/conversation/db.ts

```ts
/**
 * D-OJ-conv-sem-objects-sink-activation — brain-side Postgres sink factory.
 *
 * This module provides `makeOddjobzSinks(db)` which returns the three
 * real Database-backed sink implementations for `recordIntakeTurn`:
 *
 *   1. `semObjectSink`      — writes each canonical turn as a
 *                             `sem_objects` row of objectKind
 *                             'oddjobz.conversation.turn' via
 *                             `createObject(db, ...)`. Uses the turn's
 *                             `turnId` as the row id (deterministic).
 *                             Idempotent: a unique-constraint violation
 *                             on the id is silently swallowed so a
 *                             replayed turn never double-inserts.
 *
 *   2. `relationSink`       — mints a `BELONGS_TO_ENTITY` relation when
 *                             the turn carries an `entityRef`. Enforces
 *                             target-must-exist (§7.2) by checking
 *                             whether the entity's sem_objects row
 *                             exists before calling `createRelation`;
 *                             logs + skips if it doesn't.
 *
 *   3. `replyRelationSink`  — mints a `REPLIES_TO` relation when the
 *                             turn carries a `quotedTurnId`. Bound via
 *                             `makeReplyRelationEmitter(db)` from
 *                             `@semantos/conversation-graph`.
 *
 * DIRECT POSTGRES — NO DEADLOCK:
 * This code runs at the brain-reactor boundary (inside the brain
 * process, NOT the spawned intake child). Opening a Postgres connection
 * here is ordinary external IO — it does NOT call back into the brain's
 * HTTP/REPL endpoints, so there is NO self-call-deadlock risk (the
 * 2026-05-18 outage `semantos_brain_single_threaded_reactor` was
 * specifically the intake CHILD sync-calling the brain's REPL; that
 * path is unchanged). The intake child still runs sans Database handle.
 *
 * LAZY SINGLETON:
 * `getDatabaseOrNull()` constructs the Database once on first call and
 * returns `null` if `DATABASE_URL` is unset. When null, the caller
 * simply omits the sinks (keeping the no-op dormant behaviour that
 * existed before this deliverable).
 */
import { drizzle } from 'drizzle-orm/postgres-js';
import { sql } from 'drizzle-orm';
import postgres from 'postgres';
import {
  createObject,
  getObject,
  type Database,
} from '@semantos/semantic-objects';
import { createRelation } from '@semantos/scg-relations';
import { makeReplyRelationEmitter } from '@semantos/conversation-graph';
import type {
  OddjobzConversationTurnPayload,
  BelongsToEntityRelation,
  RepliesToRelation,
  SemObjectTurnSink,
  SemObjectRelationSink,
  SemObjectReplyRelationSink,
  OutboundStateSink,
} from './conversation-turn-patch.js';
import type { OutboundState } from './outbound-state-machine.js';
import type { NlRelationRequest, NlRelationSink } from './nl-relation-resolver.js';

// ────────────────────────────────────────────────────────────
// Lazy-singleton DB handle
// ────────────────────────────────────────────────────────────

let _db: Database | null | undefined = undefined; // undefined = not-yet-tried

/**
 * Return the shared Database handle, constructing it from `DATABASE_URL`
 * on first call. Returns `null` when `DATABASE_URL` is unset (keeps the
 * dormant no-op behaviour for dev/test environments without a real DB).
 */
export function getDatabaseOrNull(): Database | null {
  if (_db !== undefined) return _db;

  const url = process.env.DATABASE_URL;
  if (!url) {
    _db = null;
    return null;
  }

  try {
    // `postgres()` is the postgres-js client; drizzle wraps it.
    // max:1 for the brain's single-threaded reactor — one connection
    // is all we need (all writes are sequential from the reactor thread).
    // connect_timeout:5 — fail fast if Postgres is unreachable (e.g.
    // DATABASE_URL is set but no Postgres process is running on the VPS).
    // Without this the first query hangs until the OS TCP timeout (~120s).
    const client = postgres(url, { max: 1, connect_timeout: 5 });
    _db = drizzle(client) as unknown as Database;
  } catch (err) {
    process.stderr.write(
      `[oddjobz-sinks] Failed to construct Database from DATABASE_URL: ${err instanceof Error ? err.message : String(err)}\n`,
    );
    _db = null;
  }

  return _db;
}

/** Exposed for tests that inject a pre-built Database (e.g. PGlite). */
export function setDatabaseForTest(db: Database | null): void {
  _db = db;
}

/** Reset the singleton (call in afterEach in tests). */
export function resetDatabaseSingleton(): void {
  _db = undefined;
}

// ────────────────────────────────────────────────────────────
// Object-kind discriminator
// ────────────────────────────────────────────────────────────

export const ODDJOBZ_TURN_OBJECT_KIND = 'oddjobz.conversation.turn';

// ────────────────────────────────────────────────────────────
// Sink implementations
// ────────────────────────────────────────────────────────────

/**
 * Create a `semObjectSink` backed by a real Database.
 *
 * Writes each canonical turn as a `sem_objects` row using the turn's
 * `turnId` as the row id (deterministic — so the BELONGS_TO_ENTITY and
 * REPLIES_TO relation sinks, which reference turnId as source/target,
 * resolve to real rows).
 *
 * Idempotency: if the turn was already persisted (unique constraint
 * violation on the `id` column), we swallow the error silently. A
 * replayed turn must never double-insert.
 */
export function makeSemObjectSink(db: Database): SemObjectTurnSink {
  return async (turn: OddjobzConversationTurnPayload): Promise<void> => {
    try {
      await createObject(db, {
        id: turn.turnId,
        objectKind: ODDJOBZ_TURN_OBJECT_KIND,
        payload: turn,
        createdByCertId: turn.actorCertId ?? null,
      });
    } catch (err) {
      // Unique-constraint violation = idempotent replay; swallow silently.
      // Any other error bubbles up so the outer try/catch in
      // recordIntakeTurn can log it (best-effort: the jsonl path already
      // landed, so the reply is never blocked).
      const msg = err instanceof Error ? err.message : String(err);
      if (
        msg.includes('duplicate key') ||
        msg.includes('unique constraint') ||
        msg.includes('UNIQUE constraint')
      ) {
        return; // idempotent — already persisted
      }
      throw err;
    }
  };
}

/**
 * Create a `relationSink` backed by a real Database.
 *
 * Mints a `BELONGS_TO_ENTITY` relation from the turn row to the entity
 * cell row. Enforces target-must-exist (§7.2): if the entity's
 * sem_objects row doesn't exist yet, the relation is skipped (logged to
 * stderr) rather than throwing — the turn row is already persisted, so
 * we should not regress it. The entity anchoring is best-effort; a
 * future deliverable that threads the entity cell hash back synchronously
 * will make this non-vacuous in production.
 */
export function makeRelationSink(db: Database): SemObjectRelationSink {
  return async (rel: BelongsToEntityRelation): Promise<void> => {
    // Target-must-exist check (§7.2).
    const entityRow = await getObject(db, rel.entityCellHash);
    if (!entityRow) {
      process.stderr.write(
        `[oddjobz-sinks] BELONGS_TO_ENTITY skipped: entity row not found ` +
          `(kind=${rel.entityKind} cellHash=${rel.entityCellHash} turnId=${rel.turnId})\n`,
      );
      return;
    }

    await createRelation(db, {
      kind: 'BELONGS_TO_ENTITY',
      sourceId: rel.turnId,
      targetId: rel.entityCellHash,
      // No capabilityCheck wired here — relation-mint capability is a
      // later deliverable (RM-022). createRelation defaults to no-op
      // capabilityCheck when omitted.
    });
  };
}

/**
 * Create a `replyRelationSink` backed by a real Database.
 *
 * Uses `makeReplyRelationEmitter(db)` from `@semantos/conversation-graph`
 * to map a `RepliesToRelation` request onto `autoEmitReplyRelation(db, …)`.
 * The emitter is vacuous (returns null, no error) when `quotedTurnId` is
 * absent — matching the upstream `buildReplyRelations` behaviour that
 * already filters to turns with a `quotedTurnId` before calling this sink.
 *
 * No capabilityCheck: RM-022 will wire it later; omitting it means
 * `createRelation` defaults to a no-op check (passes unconditionally),
 * which is the correct behaviour for Phase-1 activation.
 */
export function makeReplyRelationSink(db: Database): SemObjectReplyRelationSink {
  const emitter = makeReplyRelationEmitter(db);
  return async (rel: RepliesToRelation): Promise<void> => {
    await emitter({
      turnId: rel.turnId,
      quotedTurnId: rel.quotedTurnId,
      ...(rel.authorCertId !== undefined ? { authorCertId: rel.authorCertId } : {}),
    });
  };
}

/**
 * Create an `nlRelationSink` backed by a real Database.
 *
 * Mints a canonical SCG relation for each NL-phrase relation request
 * resolved by `resolveNlRelations`. The request carries fully-resolved
 * source/target `sem_objects.id` values; both turn rows must already
 * exist (the caller in `recordIntakeTurn` fires this AFTER the turn
 * rows land).
 *
 * Idempotency: unique-constraint violations are swallowed silently —
 * a replayed turn must never double-mint a relation.
 *
 * No capabilityCheck: RM-022 will wire it later; omitting it means
 * `createRelation` defaults to a no-op check (passes unconditionally),
 * which is the correct behaviour for Phase-1 activation. Mirrors the
 * makeRelationSink / makeReplyRelationSink discipline.
 */
export function makeNlRelationSink(db: Database): NlRelationSink {
  return async (req: NlRelationRequest): Promise<void> => {
    await createRelation(db, {
      kind: req.kind,
      sourceId: req.sourceId,
      targetId: req.targetId,
      // No capabilityCheck (RM-022 deferred — Phase-1 activation).
    });
  };
}

/**
 * Create an `outboundStateSink` backed by a real Database.
 *
 * Patches the `outboundState` field of a persisted turn's `payload` JSONB
 * in-place via a single UPDATE statement (Option A from the durability
 * benchmark in `outbound-durability-benchmark.ts`: 0.309ms median, within
 * the 2× simplicity threshold vs the sidecar-table Option C at 0.179ms).
 *
 * Called by `approveOutboundTurn` to drive state transitions:
 *   proposed → approved, approved → sent, sent → failed
 *
 * The UPDATE is not idempotent by default — re-applying the same state
 * is harmless (a no-op write) but is not specially guarded here because
 * the approval flow drives transitions deterministically.
 */
export function makeOutboundStateSink(db: Database): OutboundStateSink {
  // Uses the `sql` tagged template from drizzle-orm (imported at top of
  // file) so we can issue a raw JSONB-merge UPDATE that drizzle doesn't
  // model natively.
  //
  // SQL intent:
  //   UPDATE sem_objects
  //   SET payload = payload || '{"outboundState":"<state>"}'::jsonb
  //   WHERE id = <turnId>
  //
  // The `||` operator merges at the top level, replacing the existing
  // `outboundState` key. The state literal is a closed TypeScript union
  // (OutboundState), so it is safe to embed in the JSONB literal via
  // drizzle's parameterised `sql` template.

  return async (turnId: string, newState: OutboundState): Promise<void> => {
    await (db as any).execute(
      sql`UPDATE sem_objects SET payload = payload || ${JSON.stringify({ outboundState: newState })}::jsonb WHERE id = ${turnId}`,
    );
  };
}

// ────────────────────────────────────────────────────────────
// Composed factory
// ────────────────────────────────────────────────────────────

export interface OddjobzSinks {
  readonly semObjectSink: SemObjectTurnSink;
  readonly relationSink: SemObjectRelationSink;
  readonly replyRelationSink: SemObjectReplyRelationSink;
  readonly nlRelationSink: NlRelationSink;
  readonly outboundStateSink: OutboundStateSink;
}

/**
 * Build all Database-backed sinks from a real `Database` handle.
 *
 * The caller (brain reactor boundary) is responsible for providing `db`.
 * Use `getDatabaseOrNull()` to obtain it from `DATABASE_URL`, or inject
 * a test Database (PGlite) via `setDatabaseForTest`.
 */
export function makeOddjobzSinks(db: Database): OddjobzSinks {
  return {
    semObjectSink: makeSemObjectSink(db),
    relationSink: makeRelationSink(db),
    replyRelationSink: makeReplyRelationSink(db),
    nlRelationSink: makeNlRelationSink(db),
    outboundStateSink: makeOutboundStateSink(db),
  };
}

```
