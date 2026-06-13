---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/reply-audit.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.525550+00:00
---

# cartridges/oddjobz/brain/src/conversation/reply-audit.ts

```ts
/**
 * D-OJ-conv-reply-audit-log — durable AI-reply audit trail.
 *
 * §13.3 resolution: every outbound reply (auto-sent OR operator-
 * ratified) is logged as a `sem_objects` row of
 * `objectKind='oddjobz.conversation.reply_audit'`.
 *
 * SEPARATE objectKind from `oddjobz.conversation.turn`. The audit
 * row REFERENCES the turn (via `turnId`); it does NOT expand or
 * replace the turn shape. The turn payload stays clean.
 *
 * The audit payload records:
 *   - `turnId`          — the outbound turn's `sem_objects.id` this
 *                         audit covers (the reference anchor)
 *   - `promptVersionRef` — the `{promptId, version, contentHash}`
 *                          triple from `promptVersionRef('reply')`.
 *                          The EXACT prompt schema that generated the
 *                          reply. Allows replaying "why did the bot
 *                          say that on 2026-05-12?" and recovering the
 *                          precise prompt version.
 *   - `extractedIntent`  — the structured intent the extractor pulled
 *                          from the message (optional, absent until
 *                          D-OJ-conv-confidence-threshold lands).
 *   - `confidence`       — extraction confidence score [0,1] (optional
 *                          — absent until D-OJ-conv-confidence-
 *                          threshold lands; the field is present in the
 *                          type so consumers don't need schema bumps
 *                          when that deliverable ships).
 *   - `operatorDecision` — the operator's ratify/reject decision (absent
 *                          for auto-sent replies — those skip the
 *                          operator gate).
 *   - `cellChain`        — resulting SIR / IR / cell hash chain (absent
 *                          when not available at emit time; recorded
 *                          opportunistically).
 *   - `timestamp`        — unix-millis at emit time.
 *
 * WIRING DISCIPLINE (mirrors db.ts):
 *   - `makeReplyAuditSink(db)` is an injectable factory. The caller
 *     (brain reactor boundary in intake-handler.ts) passes the Database
 *     handle (obtained via `getDatabaseOrNull()`). No direct Database
 *     use in the intake child (project memory
 *     `semantos_brain_single_threaded_reactor`).
 *   - Best-effort + isolated: a sink failure MUST NOT break the reply
 *     (mirrors the try/catch discipline around `recordIntakeTurn` in
 *     intake-handler.ts).
 *   - Idempotency: unique-constraint violations on `turnId` are swallowed
 *     silently (a replayed audit must never double-insert).
 *   - The audit sink fires AFTER the outbound turn row lands (so
 *     `turnId` is a valid foreign key reference in sem_objects).
 *
 * NO AI CALLS: this module is pure persistence — it records the prompt
 * ref, it does NOT call the model. (Project memory:
 * `semantos_no_ai_in_substrate`.)
 */

import {
  createObject,
  type Database,
} from '@semantos/semantic-objects';
import type { PromptVersionRef } from './prompt-store.js';

// ────────────────────────────────────────────────────────────
// Object-kind discriminator
// ────────────────────────────────────────────────────────────

export const ODDJOBZ_REPLY_AUDIT_OBJECT_KIND =
  'oddjobz.conversation.reply_audit';

// ────────────────────────────────────────────────────────────
// Payload type
// ────────────────────────────────────────────────────────────

/** The operator's ratify-or-reject decision when applicable. Absent
 *  for auto-sent replies (those cleared the confidence threshold and
 *  were never queued for operator review). */
export type OperatorDecision = 'ratified' | 'rejected';

/** Structured extracted intent from the customer message. Optional
 *  until D-OJ-conv-confidence-threshold lands (that deliverable wires
 *  confidence scoring + the intent-extractor result through to the
 *  reply path). The shape is left open (`Record<string,unknown>`) so
 *  the reply-audit row can carry whatever the extractor produces
 *  without coupling the audit schema to the extractor's version. */
export type ExtractedIntent = Record<string, unknown>;

/** The `sem_objects` payload for `objectKind='oddjobz.conversation.reply_audit'`.
 *
 * Audit utility: when a reply turns out wrong, the operator queries
 * `WHERE payload->>'turnId' = '<turnId>'` (or via the turn's own
 * sem_objects.id FK) to recover:
 *   (a) the exact prompt schema version (promptVersionRef)
 *   (b) what the extractor saw (extractedIntent + confidence)
 *   (c) how the operator acted (operatorDecision, if applicable)
 *   (d) where the reply went in the cell chain (cellChain)
 * Then decides: revert the prompt / tighten the threshold / retrain
 * the extractor.
 */
export interface OddjobzReplyAuditPayload {
  /** The outbound `oddjobz.conversation.turn` sem_objects.id this
   *  audit covers. Foreign-key reference (the turn must exist first). */
  readonly turnId: string;

  /** The versioned prompt pin: `{promptId, version, contentHash}` from
   *  `promptVersionRef('reply')` — the EXACT prompt schema that
   *  generated the reply. Enables precise prompt archaeology. */
  readonly promptVersionRef: PromptVersionRef;

  /** The structured intent the extractor pulled from the customer
   *  message. Optional — absent until D-OJ-conv-confidence-threshold
   *  ships the extractor result through the reply path. */
  readonly extractedIntent?: ExtractedIntent;

  /** Extraction confidence score in [0, 1]. Optional — absent until
   *  D-OJ-conv-confidence-threshold wires confidence through to here. */
  readonly confidence?: number;

  /** Operator's ratify/reject decision. Absent for auto-sent replies
   *  (those skipped the operator gate). */
  readonly operatorDecision?: OperatorDecision;

  /** SIR / IR / cell hash chain produced by the reply path. Recorded
   *  opportunistically — absent when not available at emit time (e.g.
   *  the cell hasn't been minted yet, or the reply was a widget text
   *  reply without a cell chain). */
  readonly cellChain?: string;

  /** Unix-millis at audit emit time. */
  readonly timestamp: number;
}

// ────────────────────────────────────────────────────────────
// Sink type
// ────────────────────────────────────────────────────────────

/** The injectable reply-audit sink. Receives a fully-formed
 *  `OddjobzReplyAuditPayload` and persists it as a `sem_objects` row
 *  of `objectKind='oddjobz.conversation.reply_audit'`.
 *
 *  The caller is responsible for:
 *    (a) ensuring the outbound turn row already exists in sem_objects
 *        BEFORE calling this sink (so `turnId` is a valid reference);
 *    (b) treating a failure as best-effort (never let it break the
 *        reply — mirror the try/catch around `recordIntakeTurn` in
 *        intake-handler.ts). */
export type ReplyAuditSink = (
  payload: OddjobzReplyAuditPayload,
) => Promise<void> | void;

// ────────────────────────────────────────────────────────────
// Sink factory
// ────────────────────────────────────────────────────────────

/**
 * Create a `ReplyAuditSink` backed by a real Database.
 *
 * Persists each reply-audit payload as a `sem_objects` row using a
 * deterministic id derived from the `turnId` (so the audit row is
 * uniquely keyed to the turn it covers and can be looked up directly).
 *
 * Idempotency: if the audit row was already persisted (unique-constraint
 * violation on the `id` column), the error is swallowed silently. A
 * replayed audit must never double-insert.
 *
 * The `id` is `audit-${turnId}` — stable, greppable, and avoids
 * collisions with the turn row (which uses `turnId` bare). The
 * sem_objects table's `objectKind` discriminates them at query time:
 *   `WHERE objectKind = 'oddjobz.conversation.reply_audit'`
 *   `  AND payload->>'turnId' = '<turnId>'`
 * (or more tersely: `WHERE id = 'audit-<turnId>'`).
 */
export function makeReplyAuditSink(db: Database): ReplyAuditSink {
  return async (payload: OddjobzReplyAuditPayload): Promise<void> => {
    try {
      await createObject(db, {
        id: `audit-${payload.turnId}`,
        objectKind: ODDJOBZ_REPLY_AUDIT_OBJECT_KIND,
        payload,
        // The audit row is written by the brain reactor (not the
        // operator), so there's no actor cert to thread here.
        // The turn row itself carries actorCertId when cert-bound.
        createdByCertId: null,
      });
    } catch (err) {
      // Unique-constraint violation = idempotent replay; swallow silently.
      // Any other error bubbles up so the outer try/catch in
      // intake-handler.ts can log it (best-effort: the reply is never
      // blocked by an audit-sink failure — mirrors makeSemObjectSink).
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

```
