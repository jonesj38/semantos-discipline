---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/identity-merge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.518088+00:00
---

# cartridges/oddjobz/brain/src/conversation/identity-merge.ts

```ts
/**
 * D-OJ-conv-identity-merge — operator-initiated participant identity merge.
 *
 * When the same customer appears twice (cleared cookie, new phone, new email),
 * they enter the system as a new participant. This module lets an operator
 * merge two participant identities into one.
 *
 * Design per §13.2 (ODDJOBZ-CONVERSATION-ARCHITECTURE.md):
 *
 *   1. Operator initiates an `identity.merge_request` intent:
 *        source = new/duplicate participant id
 *        target = canonical participant id
 *   2. The merge is gated on a challenge: the operator picks a fact from
 *      the would-be-merged party's job history and confirms it was answered
 *      correctly by the customer. The challenge is a natural-language fact,
 *      NOT a cryptographic proof. The intent carries:
 *        { challengeQuestion, challengeAnswer, operatorConfirmed }
 *      Wrong answer / unconfirmed → merge refused.
 *   3. On success: emit a `MERGES` SCG relation
 *        source = new participantId (the duplicate)
 *        target = canonical participantId
 *   4. Downstream queries chase `MERGES` chains transitively via
 *      `followMerges` (X→Y→Z returns union; canonical identity wins on conflict).
 *
 * Architecture constraints:
 *   - No AI calls (semantos_no_ai_in_substrate). The challenge is operator-
 *     confirmed natural language, not ML inference.
 *   - No sync-call back into the brain HTTP/REPL
 *     (semantos_brain_single_threaded_reactor). All DB access is injected.
 *   - `MERGES` is already in `RelationKind` (RM-080, core/scg-relations).
 *   - Participant ids are `sem_objects.id` values — the same id space used
 *     by all SCG sources/targets.
 *
 * ESM imports use .js extensions for relative paths.
 */

import {
  createRelation,
  listRelationsFrom,
} from '@semantos/scg-relations';
import type { Database } from '@semantos/semantic-objects';

// ────────────────────────────────────────────────────────────
// Public types
// ────────────────────────────────────────────────────────────

/**
 * The input to a participant identity merge operation.
 *
 * `sourceParticipantId` — the new/duplicate participant id (the one to be
 *   merged away; it MERGES→target after a successful merge).
 * `targetParticipantId` — the canonical participant id (the one to keep;
 *   queries follow MERGES chains to reach the canonical identity).
 * `challengeQuestion` — a natural-language fact the operator presents to
 *   the customer ("What was the address of your last job?"). Stored on the
 *   MERGES relation's `extra` field for the audit trail.
 * `challengeAnswer`   — the answer the customer provided (also stored for
 *   the audit trail; no hashing — this is operational data, not a secret).
 * `operatorConfirmed` — whether the operator confirmed the customer's
 *   challenge answer was correct. Must be `true` for the merge to proceed.
 */
export interface IdentityMergeRequest {
  readonly sourceParticipantId: string;
  readonly targetParticipantId: string;
  readonly challengeQuestion: string;
  readonly challengeAnswer: string;
  readonly operatorConfirmed: boolean;
}

/** Successful merge result: the newly-created MERGES relation id. */
export interface IdentityMergeSuccess {
  readonly ok: true;
  readonly relationId: string;
}

/**
 * Failure reasons:
 *   `challenge_not_confirmed` — `operatorConfirmed` was false; operator did
 *     not confirm the customer correctly answered the challenge question.
 *   `same_identity` — source and target ids are identical; merging an
 *     identity with itself is a no-op at best, a data error at worst.
 *   `already_merged` — a MERGES relation already exists from source→target
 *     (idempotency guard; avoids duplicate edges in the graph).
 */
export type IdentityMergeFailureReason =
  | 'challenge_not_confirmed'
  | 'same_identity'
  | 'already_merged';

export interface IdentityMergeFailure {
  readonly ok: false;
  readonly reason: IdentityMergeFailureReason;
}

export type IdentityMergeResult = IdentityMergeSuccess | IdentityMergeFailure;

// ────────────────────────────────────────────────────────────
// processIdentityMerge
// ────────────────────────────────────────────────────────────

/**
 * Validate and execute a participant identity merge.
 *
 * Validation order:
 *   1. `operatorConfirmed` must be `true`   → `challenge_not_confirmed`
 *   2. source !== target                    → `same_identity`
 *   3. no existing MERGES(source→target)    → `already_merged`
 *
 * On success: mints a `MERGES` relation
 *   source = sourceParticipantId (the duplicate)
 *   target = targetParticipantId (the canonical)
 *   extra  = { challengeQuestion, challengeAnswer } (audit trail)
 *
 * Returns `{ ok: true, relationId }` on success, or
 * `{ ok: false, reason }` on any validation failure.
 *
 * Pure from the caller's perspective except for the DB write — no AI
 * calls, no brain-HTTP calls (semantos_no_ai_in_substrate +
 * semantos_brain_single_threaded_reactor).
 */
export async function processIdentityMerge(
  db: Database,
  req: IdentityMergeRequest,
): Promise<IdentityMergeResult> {
  // Guard 1: operator must have confirmed the challenge answer.
  if (!req.operatorConfirmed) {
    return { ok: false, reason: 'challenge_not_confirmed' };
  }

  // Guard 2: source and target must be distinct participant ids.
  if (req.sourceParticipantId === req.targetParticipantId) {
    return { ok: false, reason: 'same_identity' };
  }

  // Guard 3: idempotency — check for an existing MERGES relation
  // from source to target. We list all MERGES from the source and
  // look for one whose target matches.
  const existingMerges = await listRelationsFrom(db, req.sourceParticipantId, {
    kind: 'MERGES',
  });
  const alreadyMerged = existingMerges.some(
    (rel) => rel.payload.targetId === req.targetParticipantId,
  );
  if (alreadyMerged) {
    return { ok: false, reason: 'already_merged' };
  }

  // All guards passed — mint the MERGES relation.
  const rel = await createRelation(db, {
    kind: 'MERGES',
    sourceId: req.sourceParticipantId,
    targetId: req.targetParticipantId,
    extra: {
      challengeQuestion: req.challengeQuestion,
      challengeAnswer: req.challengeAnswer,
    },
  });

  return { ok: true, relationId: rel.id };
}

// ────────────────────────────────────────────────────────────
// followMerges
// ────────────────────────────────────────────────────────────

/** Maximum BFS depth for `followMerges`. Guards against cycles and
 *  runaway chains. Ten hops is far beyond any realistic merge depth. */
const FOLLOW_MERGES_MAX_DEPTH = 10;

/**
 * Transitively follow MERGES relations from `participantId`, returning
 * the BFS-ordered list of all participant ids reachable via MERGES edges
 * (inclusive of the starting id).
 *
 * Shape:
 *   - First element is always `participantId` (the starting identity).
 *   - Subsequent elements are the ids reachable by following MERGES
 *     edges in BFS order (the canonical identity / chain tip is at the
 *     end of a linear chain: A→B→C returns [A, B, C]).
 *   - If there are NO MERGES from `participantId`, returns `[participantId]`
 *     (self — the identity has not been merged into anything else).
 *   - Unique: each id appears at most once (visited-set guards cycles).
 *
 * Depth-limited to `FOLLOW_MERGES_MAX_DEPTH` (10) to prevent infinite
 * loops from cycles in the graph (e.g. A→B and B→A). The visited-set
 * also guards cycles independently.
 *
 * No AI calls. No brain-HTTP calls. Pure DB reads.
 */
export async function followMerges(
  db: Database,
  participantId: string,
): Promise<string[]> {
  const visited = new Set<string>();
  const result: string[] = [];

  // BFS frontier — start with the given id.
  let frontier: string[] = [participantId];
  visited.add(participantId);
  result.push(participantId);

  for (let depth = 0; depth < FOLLOW_MERGES_MAX_DEPTH && frontier.length > 0; depth++) {
    const nextFrontier: string[] = [];

    for (const currentId of frontier) {
      const outgoing = await listRelationsFrom(db, currentId, { kind: 'MERGES' });

      for (const rel of outgoing) {
        const neighbourId = rel.payload.targetId;
        if (!visited.has(neighbourId)) {
          visited.add(neighbourId);
          result.push(neighbourId);
          nextFrontier.push(neighbourId);
        }
      }
    }

    frontier = nextFrontier;
  }

  return result;
}

```
