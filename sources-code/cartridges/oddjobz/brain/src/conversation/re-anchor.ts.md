---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/re-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.520793+00:00
---

# cartridges/oddjobz/brain/src/conversation/re-anchor.ts

```ts
/**
 * D-OJ-conv-re-anchor — §13.4 re-anchoring semantics (SUPERSEDES pattern).
 *
 * When the operator re-anchors a conversation turn to a different entity
 * (job/site/customer/lead), the old anchor must be superseded and a new one
 * created. This preserves full audit history (append-only).
 *
 * Design per §13.4 (ODDJOBZ-CONVERSATION-ARCHITECTURE.md) — SUPERSEDES pattern:
 *
 *   1. Find the current active `BELONGS_TO_ENTITY` relation for the turn
 *      (the one not yet targeted by a `SUPERSEDES` relation).
 *   2. Mint a new `BELONGS_TO_ENTITY` relation
 *        source = turnId
 *        target = newEntityCellHash
 *   3. Mint a `SUPERSEDES` relation
 *        source = NEW relation's id
 *        target = OLD relation's id
 *
 * `getActiveAnchor` finds the live anchor by filtering out any
 * BELONGS_TO_ENTITY that is already a SUPERSEDES target.
 *
 * Architecture constraints:
 *   - No AI calls (semantos_no_ai_in_substrate).
 *   - No sync-call back into the brain HTTP/REPL
 *     (semantos_brain_single_threaded_reactor). All DB access is injected.
 *   - `BELONGS_TO_ENTITY` and `SUPERSEDES` are already in `RelationKind`
 *     (core/scg-relations/src/types.ts).
 *   - turnId IS the sem_objects.id (db.ts line 125-137).
 *   - entityCellHash = sem_objects.id of the entity cell (= relation's targetId).
 *
 * ESM imports use .js extensions for relative paths.
 */

import {
  createRelation,
  listRelationsFrom,
  listRelationsTo,
} from '@semantos/scg-relations';
import type { RelationRow } from '@semantos/scg-relations';
import { getObject } from '@semantos/semantic-objects';
import type { Database } from '@semantos/semantic-objects';

// ────────────────────────────────────────────────────────────
// Public types
// ────────────────────────────────────────────────────────────

/**
 * Input for a turn re-anchor operation.
 *
 * `turnId` — the sem_objects.id of the turn to re-anchor.
 * `newEntityCellHash` — the sem_objects.id of the new target entity cell.
 * `newEntityKind` — the kind of the new target entity (job/site/customer/lead).
 * `operatorCertId` — optional operator cert id for the audit trail.
 */
export interface ReAnchorRequest {
  readonly turnId: string;
  readonly newEntityCellHash: string;
  readonly newEntityKind: 'job' | 'site' | 'customer' | 'lead';
  readonly operatorCertId?: string;
}

/**
 * Failure reasons:
 *   `turn_not_found` — the turnId does not exist in sem_objects.
 *   `entity_not_found` — the newEntityCellHash does not exist in sem_objects.
 *   `no_existing_anchor` — the turn has no active BELONGS_TO_ENTITY relation
 *     to supersede; re-anchoring requires an existing anchor.
 *   `already_anchored_to_same_entity` — the current anchor already points to
 *     newEntityCellHash; no-op re-anchor is an error.
 *   `db_error` — an unexpected error occurred during the DB writes.
 */
export type ReAnchorFailureReason =
  | 'turn_not_found'
  | 'entity_not_found'
  | 'no_existing_anchor'
  | 'already_anchored_to_same_entity'
  | 'db_error';

export type ReAnchorResult =
  | { readonly ok: true; readonly newRelationId: string; readonly supersededRelationId: string }
  | { readonly ok: false; readonly reason: ReAnchorFailureReason };

// ────────────────────────────────────────────────────────────
// getActiveAnchor
// ────────────────────────────────────────────────────────────

/**
 * Find the active `BELONGS_TO_ENTITY` relation for a turn.
 *
 * "Active" means: a BELONGS_TO_ENTITY relation whose id is NOT the target
 * of any SUPERSEDES relation. When a re-anchor happens, the old anchor is
 * superseded (a SUPERSEDES relation source=newRel, target=oldRel is minted).
 * This function finds the one surviving anchor.
 *
 * Returns null if no BELONGS_TO_ENTITY relations exist for the turn, or
 * all of them have been superseded.
 *
 * No AI calls. No brain-HTTP calls. Pure DB reads.
 */
export async function getActiveAnchor(
  db: Database,
  turnId: string,
): Promise<RelationRow | null> {
  const anchors = await listRelationsFrom(db, turnId, { kind: 'BELONGS_TO_ENTITY' });

  for (const anchor of anchors) {
    // Check if this anchor has been superseded: look for a SUPERSEDES
    // relation whose targetId = anchor.id. If none, this anchor is active.
    const supersedingRels = await listRelationsTo(db, anchor.id, {
      kind: 'SUPERSEDES',
      limit: 1,
    });
    if (supersedingRels.length === 0) {
      return anchor;
    }
  }

  return null;
}

// ────────────────────────────────────────────────────────────
// reAnchorTurn
// ────────────────────────────────────────────────────────────

/**
 * Validate and execute a turn re-anchor using the SUPERSEDES pattern.
 *
 * Validation order:
 *   1. turn exists in sem_objects        → `turn_not_found`
 *   2. new entity exists in sem_objects  → `entity_not_found`
 *   3. active anchor exists              → `no_existing_anchor`
 *   4. anchor.targetId !== newEntityCellHash → `already_anchored_to_same_entity`
 *
 * On success:
 *   - Mints a new BELONGS_TO_ENTITY (source=turnId, target=newEntityCellHash)
 *   - Mints a SUPERSEDES (source=newRel.id, target=oldRel.id)
 *   - Returns `{ ok: true, newRelationId, supersededRelationId }`
 *
 * Steps 5-6 (the two createRelation calls) are wrapped in a try/catch →
 * `db_error` on any failure.
 *
 * No AI calls. No brain-HTTP calls. Pure DB writes after the guards.
 */
export async function reAnchorTurn(
  db: Database,
  req: ReAnchorRequest,
): Promise<ReAnchorResult> {
  // Guard 1: turn must exist.
  try {
    const turnObj = await getObject(db, req.turnId);
    if (turnObj === null) {
      return { ok: false, reason: 'turn_not_found' };
    }
  } catch {
    return { ok: false, reason: 'turn_not_found' };
  }

  // Guard 2: new entity must exist.
  try {
    const entityObj = await getObject(db, req.newEntityCellHash);
    if (entityObj === null) {
      return { ok: false, reason: 'entity_not_found' };
    }
  } catch {
    return { ok: false, reason: 'entity_not_found' };
  }

  // Guard 3: there must be an existing active anchor to supersede.
  const activeAnchor = await getActiveAnchor(db, req.turnId);
  if (activeAnchor === null) {
    return { ok: false, reason: 'no_existing_anchor' };
  }

  // Guard 4: must not be re-anchoring to the same entity.
  if (activeAnchor.payload.targetId === req.newEntityCellHash) {
    return { ok: false, reason: 'already_anchored_to_same_entity' };
  }

  // All guards passed — mint the new anchor and the SUPERSEDES relation.
  try {
    const newRel = await createRelation(db, {
      kind: 'BELONGS_TO_ENTITY',
      sourceId: req.turnId,
      targetId: req.newEntityCellHash,
      extra: { entityKind: req.newEntityKind },
      ...(req.operatorCertId !== undefined
        ? { createdByCertId: req.operatorCertId }
        : {}),
    });

    await createRelation(db, {
      kind: 'SUPERSEDES',
      sourceId: newRel.id,
      targetId: activeAnchor.id,
      ...(req.operatorCertId !== undefined
        ? { createdByCertId: req.operatorCertId }
        : {}),
    });

    return {
      ok: true,
      newRelationId: newRel.id,
      supersededRelationId: activeAnchor.id,
    };
  } catch {
    return { ok: false, reason: 'db_error' };
  }
}

```
