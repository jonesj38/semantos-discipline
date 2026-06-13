---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/conversation-graph/src/auto-emit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.007953+00:00
---

# core/conversation-graph/src/auto-emit.ts

```ts
/**
 * `autoEmitReplyRelation` — emit a `REPLIES_TO` SCG relation when a
 * turn quotes a prior turn (RM-031 / SCG §3.6).
 *
 * Extensions don't need to know about SCG to participate in the
 * conversation graph: they just report quotes via the `Turn.quotedTurnId`
 * field, and this helper threads the SCG relation into the substrate.
 *
 * Returns:
 *   - the created `RelationRow` when a relation was emitted
 *   - `null` when the turn did not quote anything (vacuously satisfied)
 *
 * Capability-check thunk is forwarded to `createRelation` — RM-022
 * wires production callers to `capabilityPort.check({ capability:
 * RELATION_MINT, … })`. Tests pass nothing and the operation succeeds.
 */
import {
  createRelation,
  type RelationRow,
} from '@semantos/scg-relations';
import type { Database } from '@semantos/semantic-objects';
import type { AutoEmitOptions, Turn } from './types.js';

export async function autoEmitReplyRelation(
  db: Database,
  turn: Turn,
  opts: AutoEmitOptions = {},
): Promise<RelationRow | null> {
  if (!turn.quotedTurnId) return null;

  return createRelation(db, {
    kind: 'REPLIES_TO',
    sourceId: turn.turnId,
    targetId: turn.quotedTurnId,
    ...(turn.authorCertId !== undefined ? { createdByCertId: turn.authorCertId } : {}),
    ...(opts.capabilityCheck !== undefined ? { capabilityCheck: opts.capabilityCheck } : {}),
  });
}

/**
 * Brain-side `REPLIES_TO` emitter (D-SCG-oddjobz-consumer-cutover).
 *
 * Returns a sink that an extension's turn-persist path injects (e.g.
 * Oddjobz's `RecordIntakeTurnDeps.replyRelationSink`). The extension
 * builds a minimal per-turn reply request — `{ turnId, quotedTurnId,
 * authorCertId }` — and the emitter maps it onto the substrate `Turn`
 * shape and calls `autoEmitReplyRelation(db, …)`.
 *
 * The split keeps the extension cartridge Database-free (no
 * `@semantos/semantic-objects` dependency, no `createRelation` import):
 * the cartridge constructs the request where conversation context lives
 * (the spawned intake child), while THIS emitter — wired into the brain
 * reactor where the `Database` handle lives — performs the actual write.
 * This honours the single-threaded-reactor discipline (project memory
 * `semantos_brain_single_threaded_reactor`): the intake child never
 * sync-calls back into the brain; only the brain-side emitter touches
 * the Database.
 *
 * PRODUCTION ACTIVATION GATED on the real Database-backed sem_objects
 * sink (`D-OJ-conv-sem-objects-sink-activation`): the turn's
 * `sem_objects.id` must exist before this emitter fires (the relation
 * source/target are `sem_objects.id`s). Until that activation lands,
 * the production turn-persist path leaves `replyRelationSink` absent
 * (dormant) — this emitter is exercised through an injected test
 * Database.
 *
 * The optional `capabilityCheck` is forwarded to every emit (RM-022
 * wires it to `capabilityPort.check({ capability: RELATION_MINT, … })`).
 */
export interface ReplyRelationRequest {
  /** The quoting turn's `sem_objects.id` (relation source). */
  readonly turnId: string;
  /** The quoted prior turn's `sem_objects.id` (relation target).
   *  When unset, the emit is vacuous (no relation, no error). */
  readonly quotedTurnId?: string;
  /** The quoting turn's author cert id, threaded onto the relation as
   *  `createdByCertId` when present. */
  readonly authorCertId?: string;
  /** The conversation aggregate id (carried through to the `Turn`
   *  shape; not currently persisted on the relation). */
  readonly conversationId?: string;
}

export type ReplyRelationEmitter = (
  req: ReplyRelationRequest,
) => Promise<RelationRow | null>;

export function makeReplyRelationEmitter(
  db: Database,
  opts: AutoEmitOptions = {},
): ReplyRelationEmitter {
  return (req: ReplyRelationRequest) => {
    const turn: Turn = {
      conversationId: req.conversationId ?? '',
      turnId: req.turnId,
      ...(req.quotedTurnId !== undefined ? { quotedTurnId: req.quotedTurnId } : {}),
      ...(req.authorCertId !== undefined ? { authorCertId: req.authorCertId } : {}),
    };
    return autoEmitReplyRelation(db, turn, opts);
  };
}

```
