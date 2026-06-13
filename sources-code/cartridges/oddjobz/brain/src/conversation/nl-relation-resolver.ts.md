---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/nl-relation-resolver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.519001+00:00
---

# cartridges/oddjobz/brain/src/conversation/nl-relation-resolver.ts

```ts
/**
 * D-OJ-conv-per-turn-compression — NL-phrase relation resolver.
 *
 * Closes the binding gap left open by RM-030 (the 10th reducer pass):
 * the relation pass emits a `SIRConstraint { kind: 'relation', relationKind }`
 * but defers `sourceId` / `targetId` resolution. This module is the
 * resolver that runs ONE LAYER ABOVE the reducer, at the
 * `recordIntakeTurn` call site where conversation-context state is
 * available.
 *
 * RESOLUTION STRATEGY:
 *   source = current inbound turn's `sem_objects.id` (turnId).
 *            The NL phrase lives in the customer's message (inbound
 *            turn), so that turn is the source of the relation.
 *   target = resolved in priority order:
 *     1. The inbound turn's `quotedTurnId` — when the surface provided
 *        an explicit structural quote (D-ODDJOBZ-quote-affordance), that
 *        is the best available target.
 *     2. The outbound turn's `turnId` from the PRIOR interaction in the
 *        same call — i.e. when `recordIntakeTurn` has both the inbound
 *        and outbound turns from THIS call, "the previous turn" in context
 *        is the outbound AI reply from the SAME pair (the turn the customer
 *        is reacting to).
 *     3. SKIP — if neither is available, we cannot fabricate a target.
 *        Log and move on. No throw. No fabricated row.
 *
 * NOTE on REPLIES_TO: the 10th pass also detects REPLIES_TO phrases
 * ("reply to that", "in response to"). REPLIES_TO is already handled via
 * the structural `quotedTurnId` → `buildReplyRelations` → `replyRelationSink`
 * path. To avoid double-minting, this resolver SKIPS REPLIES_TO — it is
 * intentionally excluded from the NL-phrase path. The structural
 * `quotedTurnId` path is authoritative for REPLIES_TO.
 *
 * NOTE on BELONGS_TO_ENTITY: not a reducer-detected kind; excluded.
 * NOTE on REFERENCES_OBJECT: intentionally deferred pending §13.10
 * (unresolved design question). Not wired here.
 *
 * DETERMINISM: given the same inbound turn + prior-turn context,
 * the resolver always emits the same set of relations (same input →
 * same output, no RNG, no clock). Snapshot/replay safe.
 *
 * BEST-EFFORT + ISOLATED: resolver+mint failures are caught by the
 * outer try/catch in `recordIntakeTurn` and NEVER regress turn
 * persistence or the reply path.
 *
 * NO LLM CALLS: pure deterministic resolution over already-reduced
 * intent constraints. (Project memory: `semantos_no_ai_in_substrate`.)
 */

import type { SIRConstraint } from '@semantos/semantos-sir';
import type { RelationKind } from '@semantos/scg-relations';
import type { OddjobzConversationTurnPayload } from './conversation-turn-patch.js';

// ── Excluded kinds ─────────────────────────────────────────────
//
// REPLIES_TO — already handled via structural quotedTurnId path.
// BELONGS_TO_ENTITY — not a reducer-detected kind; entity-anchoring
//   has its own injected sink.
// REFERENCES_OBJECT — deferred pending §13.10 design resolution.
//   Leave a one-line comment at the wiring site so it's greppable.

const EXCLUDED_NL_KINDS = new Set<RelationKind>([
  'REPLIES_TO',        // handled by structural quotedTurnId / replyRelationSink
  'BELONGS_TO_ENTITY', // entity-anchoring; separate sink
  // REFERENCES_OBJECT is deferred pending §13.10 (not in RelationKind yet)
]);

// ── Types ──────────────────────────────────────────────────────

/**
 * A resolved NL-phrase relation ready to mint. Source and target are
 * `sem_objects.id` values — both turn rows must already exist.
 *
 * Source = the inbound turn expressing the relation.
 * Target = the turn/object the phrase refers to.
 */
export interface NlRelationRequest {
  readonly kind: RelationKind;
  /** `sem_objects.id` of the inbound turn expressing the relation. */
  readonly sourceId: string;
  /** `sem_objects.id` of the prior turn/object the phrase targets. */
  readonly targetId: string;
  /** For audit tracing only — not persisted on the relation row. */
  readonly conversationId: string;
}

/**
 * The injected NL-relation sink. Receives a fully-resolved
 * `NlRelationRequest` and mints the SCG relation (via `createRelation`
 * from `@semantos/scg-relations`) AFTER the turn rows exist.
 *
 * Best-effort + isolated: a failure MUST NOT break the reply (mirrors
 * the BELONGS_TO_ENTITY / REPLIES_TO sink isolation in
 * `conversation-turn-patch.ts`).
 */
export type NlRelationSink = (
  req: NlRelationRequest,
) => Promise<void> | void;

// ── Core resolver ──────────────────────────────────────────────

/**
 * Extract relation SIRConstraints from the intent that are eligible
 * for NL-phrase minting. Filters out excluded kinds.
 *
 * Pure — no IO.
 */
export function extractRelationConstraints(
  constraints: ReadonlyArray<SIRConstraint>,
): Array<{ relationKind: RelationKind }> {
  const results: Array<{ relationKind: RelationKind }> = [];
  for (const c of constraints) {
    if (c.kind !== 'relation') continue;
    if (EXCLUDED_NL_KINDS.has(c.relationKind)) continue;
    results.push({ relationKind: c.relationKind });
  }
  return results;
}

/**
 * Resolve NL-phrase relation requests from a completed turn pair.
 *
 * @param constraints - The SIRConstraints from the reduced intent.
 * @param inbound     - The inbound canonical turn (the customer message).
 * @param outbound    - The outbound canonical turn (the AI reply) from
 *                      THIS same interaction — used as the implicit
 *                      "prior turn" target when no explicit quote exists.
 *
 * Returns an array of resolved `NlRelationRequest`s ready to mint.
 * Returns an empty array when:
 *   - No eligible relation constraints are detected.
 *   - No resolvable target is available (not thrown — caller skips).
 *
 * Pure — no IO. Deterministic.
 */
export function resolveNlRelations(
  constraints: ReadonlyArray<SIRConstraint>,
  inbound: OddjobzConversationTurnPayload,
  outbound: OddjobzConversationTurnPayload,
): NlRelationRequest[] {
  const eligible = extractRelationConstraints(constraints);
  if (eligible.length === 0) return [];

  // Resolve target — priority order (see module doc):
  //   1. inbound.quotedTurnId (structural explicit quote from surface)
  //   2. outbound.turnId (the AI reply the customer is reacting to, from THIS interaction)
  //   3. SKIP (no fabricated target)
  //
  // In the context of an intake interaction:
  //   - The customer's message often reacts TO the last AI reply.
  //   - The "last AI reply" within THIS call is the outbound turn from
  //     the SAME recordIntakeTurn invocation.
  //   - When the surface provides an explicit inReplyToTurnId, that is
  //     mapped to inbound.quotedTurnId by buildCanonicalTurns; we prefer
  //     it as the most specific reference.
  const targetId: string | undefined =
    inbound.quotedTurnId ?? outbound.turnId;

  // outbound.turnId is always defined (it's the new outbound turn's id),
  // so this will never be undefined in practice. The ?? above is purely
  // for type safety — if somehow neither resolves, we skip.
  if (!targetId) return [];

  const sourceId = inbound.turnId;

  return eligible.map(({ relationKind }) => ({
    kind: relationKind,
    sourceId,
    targetId,
    conversationId: inbound.conversationId,
  }));
}

```
