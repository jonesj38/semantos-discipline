---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/aggregate-sir.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.526172+00:00
---

# cartridges/oddjobz/brain/src/conversation/aggregate-sir.ts

```ts
/**
 * D-OJ-conv-aggregate-sir — Conversation as a higher-order, SIR-aggregable
 * semantic object.
 *
 * A conversation thread is itself a semantic object: a deterministic fold
 * over all turns (in timestamp,turnId order) + their SCG relations that
 * produces a `ConversationAggregate` carrying:
 *
 *  (a) `entityRef`          — the job/site/customer the conversation
 *                             concerns (from turns' entityRef /
 *                             BELONGS_TO_ENTITY relation).
 *  (b) `participants`       — distinct participants (role + identity
 *                             binding) appearing in the thread.
 *  (c) `openIntents`        — intent-state summary: actions still open
 *                             (never ratified/fulfilled in the thread).
 *  (d) `stateMachineSnapshot` — outbound state-machine snapshot: what
 *                             the last action type was, whether an
 *                             estimate was presented, job closed, etc.
 *
 * DETERMINISM GUARANTEE (project memory `semantos_dx_priorities`):
 *   The pure fold (`aggregateConversation`) sorts inputs by
 *   (timestamp ASC, turnId ASC) before processing — so the same set of
 *   turns + relations always produces byte-identical output regardless of
 *   the order they were passed in.
 *
 *   A determinism vector test exercises this directly: compute the
 *   aggregate twice from the same inputs, and from a shuffled-then-
 *   canonically-reordered input, and assert equality.
 *
 * COMPUTE-ON-READ vs MATERIALIZED:
 *   This module uses COMPUTE-ON-READ only. The fold runs over the DB rows
 *   on every call to `loadConversationAggregate`. This is correct for
 *   Phase-1: conversation threads are short (typically < 200 turns) and
 *   the fold is O(n) with no IO inside the pure path. Materializing a
 *   snapshot row (objectKind='oddjobz.conversation.aggregate') would add
 *   write complexity and an invalidation problem with no measurable gain
 *   at this scale. A materialised projection can be added later (behind a
 *   feature flag, using appendPatch + foldState from semantic-objects) if
 *   benchmarks justify it. The CHOICE IS DOCUMENTED here so it's greppable.
 *
 * SIR EXPRESSION CHOICE:
 *   The summarised intent state (c) is expressed as plain typed descriptors
 *   (`OpenIntent[]`) rather than a full `SIRProgram`. Reason: the SIR
 *   compile step is a producer-side operation that requires a live lexicon
 *   + a complete intent context; folding over already-reduced turns gives us
 *   the intent RESULT (action type + parameters), not the SIR AST. Wrapping
 *   the folded action records in a SIR shell would be vacuous structure
 *   with no semantic gain. The `OpenIntent` shape carries the fields
 *   downstream consumers (state-machine router, operator UI) actually need.
 *   This is documented here per the spec's "use your judgement" instruction.
 *
 * NO LLM CALLS: all summarisation is a deterministic fold over already-
 *   reduced intent constraints on the turns. (Project memory:
 *   `semantos_no_ai_in_substrate`.)
 *
 * DIRECT POSTGRES — NO SELF-CALL DEADLOCK:
 *   `loadConversationAggregate` reads directly from Postgres. The read-only
 *   path doesn't call back into the brain's HTTP/REPL surface (project
 *   memory `semantos_brain_single_threaded_reactor`).
 */

import {
  listObjectsByKind,
  type Database,
} from '@semantos/semantic-objects';
import {
  listRelationsFrom,
  type RelationKind,
} from '@semantos/scg-relations';
import type {
  OddjobzConversationTurnPayload,
  ParticipantRole,
  IdentityHandle,
} from './conversation-turn-patch.js';
import { ODDJOBZ_TURN_OBJECT_KIND } from './db.js';

// ────────────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────────────

/**
 * Resolved participant identity binding — the unique participant
 * descriptor produced from a turn's identity fields.
 *
 * A participant is uniquely identified by whichever identity token
 * is present (in precedence order):
 *   1. `actorCertId` — cert-bound (L2).
 *   2. `identityHandle` — un-cert'd (L0/L1).
 *   3. `role` alone — fully-anonymous (neither present; one entry
 *      per anonymous role to avoid collapsing all anonymous externals).
 */
export interface ConversationParticipant {
  /** The participant's role (operator/ai/tenant/…). */
  readonly role: ParticipantRole;
  /** L2 cert binding (operator/ai/cert'd-sub). Absent for un-cert'd parties. */
  readonly actorCertId?: string;
  /** L0/L1 identity handle (un-cert'd parties). Absent for cert-bound parties. */
  readonly identityHandle?: IdentityHandle;
}

/**
 * A job/site/customer entity reference drawn from a turn's entityRef or a
 * BELONGS_TO_ENTITY relation resolved to an entity row.
 */
export interface ResolvedEntityRef {
  readonly kind: 'job' | 'site' | 'customer';
  readonly cellHash: string;
}

/**
 * An open (un-ratified) intent action extracted from the conversation turns.
 * "Open" means the action type was emitted by an outbound AI turn but was
 * NOT subsequently marked as ratified via an `operatorDecision='ratified'`
 * marker visible in the turn stream.
 *
 * NOTE: "ratified" in this context means an operator explicitly ratified
 * the reply (from the reply-audit path). Without that signal, all
 * emitted actions are considered open until closed by a 'job_closed'
 * action or until the conversation ends.
 */
export interface OpenIntent {
  /** The action type from the outbound turn's bodyParts oddjobz-intake-meta. */
  readonly actionType: string;
  /** The full action payload (for downstream routing/display). */
  readonly actionPayload: Record<string, unknown>;
  /** The turn id that emitted this action (for provenance). */
  readonly sourceTurnId: string;
  /** Unix-millis timestamp of the emitting turn. */
  readonly timestamp: number;
}

/**
 * The outbound state-machine snapshot — a deterministic projection of the
 * most recent actionable state from the outbound AI turns.
 *
 * This tracks the last observed state from the conversation's action stream,
 * not from a separate FSM — so "estimate_presented" means the last emitted
 * action type was 'present_estimate' (or similar).
 */
export interface StateMachineSnapshot {
  /** The most recent outbound action type (from the last outbound turn). */
  readonly lastActionType: string | null;
  /** Unix-millis of the last outbound action turn. */
  readonly lastActionTimestamp: number | null;
  /** True when an estimate/quote action has been presented (action type
   *  includes 'estimate', 'quote', 'present_estimate'). */
  readonly estimatePresented: boolean;
  /** True when a close action was emitted (action type includes 'close'). */
  readonly closed: boolean;
  /** True when the conversation includes a 'needs_site_visit' action type. */
  readonly needsSiteVisit: boolean;
}

/**
 * The conversation-level aggregate — the higher-order semantic descriptor
 * produced by folding all turns + their SCG relations.
 *
 * Deterministic: same ordered inputs → byte-identical aggregate.
 * Produced by `aggregateConversation`.
 */
export interface ConversationAggregate {
  /** The conversation id this aggregate describes. */
  readonly conversationId: string;

  /** (a) The job/site/customer the conversation concerns.
   *  Resolved from: the first turn that carries a non-empty entityRef
   *  (canonical source), or the first BELONGS_TO_ENTITY relation's
   *  target (fallback). Null when no entity is anchored. */
  readonly entityRef: ResolvedEntityRef | null;

  /** (b) Distinct participants in the thread. Each distinct identity
   *  binding (cert / handle / role-anon) appears exactly once.
   *  Sorted deterministically: by (role ASC, actorCertId ASC, handle
   *  kind+value ASC) so the array is stable across fold calls. */
  readonly participants: ReadonlyArray<ConversationParticipant>;

  /** (c) Summarised intent state — open (un-ratified) actions.
   *  Sorted by timestamp ASC (oldest first). Empty when all actions
   *  are ratified or the conversation carries no outbound actions. */
  readonly openIntents: ReadonlyArray<OpenIntent>;

  /** (d) Outbound state-machine snapshot. */
  readonly stateMachineSnapshot: StateMachineSnapshot;

  /** Total number of turns processed. */
  readonly turnCount: number;

  /** Timestamp of the earliest turn (or null when no turns). */
  readonly firstTurnAt: number | null;

  /** Timestamp of the most recent turn (or null when no turns). */
  readonly lastTurnAt: number | null;
}

// ────────────────────────────────────────────────────────────
// Turn sorting key
// ────────────────────────────────────────────────────────────

/**
 * Canonical turn sort key: (timestamp ASC, turnId ASC).
 * Applied before the fold so inputs are always processed in
 * the same deterministic order.
 */
function canonicalTurnOrder(
  a: OddjobzConversationTurnPayload,
  b: OddjobzConversationTurnPayload,
): number {
  if (a.timestamp !== b.timestamp) return a.timestamp - b.timestamp;
  return a.turnId < b.turnId ? -1 : a.turnId > b.turnId ? 1 : 0;
}

// ────────────────────────────────────────────────────────────
// Participant identity key
// ────────────────────────────────────────────────────────────

/**
 * A stable string key uniquely identifying a participant for deduplication.
 * Precedence: certId → handle (kind:value) → role (anonymous fallback).
 *
 * Note: when role is the only discriminator, all anonymous participants
 * with the same role are collapsed into one entry. This is intentional —
 * without an identity signal we cannot distinguish them.
 */
function participantKey(turn: OddjobzConversationTurnPayload): string {
  if (turn.actorCertId) return `cert:${turn.actorCertId}`;
  if (turn.identityHandle) {
    return `handle:${turn.identityHandle.kind}:${turn.identityHandle.value}`;
  }
  return `anon:${turn.participantRole}`;
}

// ────────────────────────────────────────────────────────────
// Entity ref extraction
// ────────────────────────────────────────────────────────────

/**
 * Extract an entity ref from turns (from the turn payload itself).
 * Returns the first non-null entityRef found, in canonical turn order.
 */
function extractEntityRefFromTurns(
  turns: ReadonlyArray<OddjobzConversationTurnPayload>,
): ResolvedEntityRef | null {
  for (const t of turns) {
    if (t.entityRef) {
      return { kind: t.entityRef.kind, cellHash: t.entityRef.cellHash };
    }
  }
  return null;
}

// ────────────────────────────────────────────────────────────
// Intent state fold
// ────────────────────────────────────────────────────────────

/**
 * Determine whether an action type string implies "estimate/quote presented".
 * Deterministic pure function over the action type string.
 */
function isEstimateAction(actionType: string): boolean {
  const lower = actionType.toLowerCase();
  return (
    lower.includes('estimate') ||
    lower.includes('quote') ||
    lower.includes('present_estimate') ||
    lower.includes('send_estimate')
  );
}

/**
 * Determine whether an action type string implies "job closed".
 */
function isCloseAction(actionType: string): boolean {
  return actionType.toLowerCase().includes('close');
}

/**
 * Determine whether an action type string implies "needs site visit".
 */
function isSiteVisitAction(actionType: string): boolean {
  const lower = actionType.toLowerCase();
  return lower.includes('site_visit') || lower.includes('needs_site_visit');
}

// ────────────────────────────────────────────────────────────
// Participant comparator (for deterministic sort)
// ────────────────────────────────────────────────────────────

function compareParticipants(
  a: ConversationParticipant,
  b: ConversationParticipant,
): number {
  if (a.role !== b.role) return a.role < b.role ? -1 : 1;
  const aKey = a.actorCertId ?? a.identityHandle
    ? `${a.actorCertId ?? ''}:${a.identityHandle?.kind ?? ''}:${a.identityHandle?.value ?? ''}`
    : '';
  const bKey = b.actorCertId ?? b.identityHandle
    ? `${b.actorCertId ?? ''}:${b.identityHandle?.kind ?? ''}:${b.identityHandle?.value ?? ''}`
    : '';
  return aKey < bKey ? -1 : aKey > bKey ? 1 : 0;
}

// ────────────────────────────────────────────────────────────
// BelongsToEntity relation shape (minimal, for the aggregate)
// ────────────────────────────────────────────────────────────

export interface BelongsToEntityEdge {
  readonly sourceId: string;  // turn sem_objects.id
  readonly targetId: string;  // entity cell hash
}

// ────────────────────────────────────────────────────────────
// Pure aggregate fold (deterministic, no IO)
// ────────────────────────────────────────────────────────────

/**
 * Aggregate a conversation's turn stream + entity relations into a
 * `ConversationAggregate`.
 *
 * PURE + DETERMINISTIC: no IO. Sorts turns by (timestamp, turnId) before
 * folding so the output is invariant to input order. Same inputs →
 * byte-identical aggregate.
 *
 * @param conversationId   The conversation id (for the aggregate header).
 * @param turns            All turns for this conversation (any order).
 * @param entityEdges      BELONGS_TO_ENTITY edges from the SCG relation
 *                         table for turns in this conversation. Used as
 *                         fallback for entityRef when the turn payload
 *                         doesn't carry one.
 * @param ratifiedTurnIds  Set of outbound turn ids that have been
 *                         operator-ratified (from reply-audit rows with
 *                         `operatorDecision='ratified'`). These are used
 *                         to close open intents.
 */
export function aggregateConversation(
  conversationId: string,
  turns: ReadonlyArray<OddjobzConversationTurnPayload>,
  entityEdges: ReadonlyArray<BelongsToEntityEdge>,
  ratifiedTurnIds: ReadonlySet<string>,
): ConversationAggregate {
  // ── Sort turns canonically (determinism guarantee) ──────────
  const sorted = [...turns].sort(canonicalTurnOrder);

  // ── (a) Entity ref — from turns first, then relation edges ──
  let entityRef = extractEntityRefFromTurns(sorted);

  // Fallback: find an entity ref from BELONGS_TO_ENTITY edges. We need
  // to map targetId back to an entity kind — we can only do this when
  // the turn's entityRef provides the kind, or when the edge target is
  // present in the turns with a known entityRef. For the fallback we
  // look for a turn that references the same entity cell hash.
  if (!entityRef && entityEdges.length > 0) {
    // Try to resolve the entity kind from any turn that carries the
    // matching cellHash (turns may not all carry entityRef — only those
    // where entity anchoring was available at persist time).
    const edgeTarget = entityEdges[0]!.targetId;
    // Look for a matching turn entityRef cellHash (across all turns)
    for (const t of sorted) {
      if (t.entityRef && t.entityRef.cellHash === edgeTarget) {
        entityRef = { kind: t.entityRef.kind, cellHash: edgeTarget };
        break;
      }
    }
    // If still null, we know the cell hash but not the kind — we can
    // only record what we know. Omit kind resolution; stay null.
    // (A future deliverable threading entity kind onto the relation
    // payload would resolve this edge case.)
  }

  // ── (b) Participants — unique identity bindings ─────────────
  const seenKeys = new Set<string>();
  const participantList: ConversationParticipant[] = [];
  for (const t of sorted) {
    const key = participantKey(t);
    if (!seenKeys.has(key)) {
      seenKeys.add(key);
      const p: ConversationParticipant = {
        role: t.participantRole,
        ...(t.actorCertId ? { actorCertId: t.actorCertId } : {}),
        ...(t.identityHandle ? { identityHandle: t.identityHandle } : {}),
      };
      participantList.push(p);
    }
  }
  // Deterministic participant sort
  participantList.sort(compareParticipants);

  // ── (c) Open intents — outbound action tracking ─────────────
  // "Open" = emitted by an outbound AI turn and NOT ratified.
  // Ratified = turn id appears in `ratifiedTurnIds` (from reply-audit rows).
  const openIntents: OpenIntent[] = [];
  let closedByAction = false;

  for (const t of sorted) {
    if (t.direction !== 'outbound') continue;

    // Extract action from oddjobz-intake-meta bodyPart
    const intakeMeta = t.bodyParts?.find((bp) => bp.kind === 'oddjobz-intake-meta');
    if (!intakeMeta) continue;
    const meta = intakeMeta.payload as { action?: { type: string; [k: string]: unknown } };
    if (!meta?.action?.type) continue;

    const actionType = meta.action.type;
    const actionPayload = meta.action as Record<string, unknown>;

    // Ratified turns close their intent
    if (ratifiedTurnIds.has(t.turnId)) continue;

    // Close actions close the entire conversation — no further open intents
    if (isCloseAction(actionType)) {
      closedByAction = true;
      continue;
    }

    openIntents.push({
      actionType,
      actionPayload,
      sourceTurnId: t.turnId,
      timestamp: t.timestamp,
    });
  }

  // If the conversation was closed, clear all open intents
  const finalOpenIntents = closedByAction ? [] : openIntents;

  // ── (d) State-machine snapshot ───────────────────────────────
  // Walk outbound turns in reverse (latest first) to find last action.
  const outboundInOrder = sorted.filter((t) => t.direction === 'outbound');
  let lastActionType: string | null = null;
  let lastActionTimestamp: number | null = null;
  let estimatePresented = false;
  let closed = false;
  let needsSiteVisit = false;

  for (const t of outboundInOrder) {
    const intakeMeta = t.bodyParts?.find((bp) => bp.kind === 'oddjobz-intake-meta');
    if (!intakeMeta) continue;
    const meta = intakeMeta.payload as { action?: { type: string } };
    if (!meta?.action?.type) continue;
    const at = meta.action.type;

    // Track the LAST (most recent) action
    // Since sorted is oldest-first, each iteration overwrites — ending
    // on the latest outbound action.
    lastActionType = at;
    lastActionTimestamp = t.timestamp;

    if (isEstimateAction(at)) estimatePresented = true;
    if (isCloseAction(at)) closed = true;
    if (isSiteVisitAction(at)) needsSiteVisit = true;
  }

  // ── Turn count + time bounds ─────────────────────────────────
  const turnCount = sorted.length;
  const firstTurnAt = sorted.length > 0 ? sorted[0]!.timestamp : null;
  const lastTurnAt = sorted.length > 0 ? sorted[sorted.length - 1]!.timestamp : null;

  return {
    conversationId,
    entityRef,
    participants: participantList,
    openIntents: finalOpenIntents,
    stateMachineSnapshot: {
      lastActionType,
      lastActionTimestamp,
      estimatePresented,
      closed,
      needsSiteVisit,
    },
    turnCount,
    firstTurnAt,
    lastTurnAt,
  };
}

// ────────────────────────────────────────────────────────────
// DB-backed loader
// ────────────────────────────────────────────────────────────

/**
 * Load a conversation aggregate from the database.
 *
 * Reads all `oddjobz.conversation.turn` rows for the given
 * `conversationId`, plus their `BELONGS_TO_ENTITY` SCG relations,
 * then calls `aggregateConversation` (pure fold). Returns `null` when
 * no turns exist for the conversation.
 *
 * Ratified turn ids are resolved by scanning `oddjobz.conversation.reply_audit`
 * rows for the conversation's turn ids that carry
 * `operatorDecision='ratified'`. When the reply-audit kind is absent
 * from the DB (older DB / tests that don't persist audits), this
 * gracefully returns an empty set.
 *
 * COMPUTE-ON-READ: no materialised aggregate row is written. See the
 * module doc for the design rationale.
 *
 * DIRECT POSTGRES: reads directly from Postgres — no self-call into
 * the brain's HTTP/REPL surface. Safe at the brain-reactor boundary.
 */
export async function loadConversationAggregate(
  db: Database,
  conversationId: string,
): Promise<ConversationAggregate | null> {
  // 1. Load all turn rows for this conversation
  const turnRows = await listObjectsByKind<OddjobzConversationTurnPayload>(db, {
    objectKind: ODDJOBZ_TURN_OBJECT_KIND,
    payloadFilters: [{ field: 'conversationId', value: conversationId }],
  });

  if (turnRows.length === 0) return null;

  const turns = turnRows.map((r) => r.payload);
  const turnIds = new Set(turns.map((t) => t.turnId));

  // 2. Load BELONGS_TO_ENTITY edges for all turns in this conversation
  //    (batch: one query per turn is too expensive; we query per turn
  //    for now — turn counts are small in Phase-1). This is safe because
  //    conversation threads are short (< 200 turns typically).
  const entityEdges: BelongsToEntityEdge[] = [];
  const seenEdgeTargets = new Set<string>();
  for (const turnId of turnIds) {
    const rels = await listRelationsFrom(db, turnId, { kind: 'BELONGS_TO_ENTITY' });
    for (const rel of rels) {
      if (!seenEdgeTargets.has(rel.payload.targetId)) {
        seenEdgeTargets.add(rel.payload.targetId);
        entityEdges.push({
          sourceId: rel.payload.sourceId,
          targetId: rel.payload.targetId,
        });
      }
    }
  }

  // 3. Load ratified turn ids from reply-audit rows
  //    reply-audit objectKind = 'oddjobz.conversation.reply_audit'
  //    payload shape: { turnId, operatorDecision?, ... }
  const REPLY_AUDIT_KIND = 'oddjobz.conversation.reply_audit';
  const ratifiedTurnIds = new Set<string>();
  try {
    // We can only filter reply-audit rows by the turn ids we have;
    // there's no conversationId on the audit payload. Load all audits
    // and filter to those whose turnId is in our turn set.
    // For Phase-1 this is acceptable (audit row count = at most 1 per
    // outbound turn). A future optimisation adds conversationId to
    // audit payloads and filters via payloadFilters.
    const auditRows = await listObjectsByKind<{
      turnId: string;
      operatorDecision?: 'ratified' | 'rejected';
    }>(db, { objectKind: REPLY_AUDIT_KIND });
    for (const row of auditRows) {
      if (
        turnIds.has(row.payload.turnId) &&
        row.payload.operatorDecision === 'ratified'
      ) {
        ratifiedTurnIds.add(row.payload.turnId);
      }
    }
  } catch {
    // reply-audit rows may not exist in all test DBs — graceful degradation.
  }

  // 4. Run the pure fold
  return aggregateConversation(conversationId, turns, entityEdges, ratifiedTurnIds);
}

```
