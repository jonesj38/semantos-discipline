---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/outbound-approval.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.516163+00:00
---

# cartridges/oddjobz/brain/src/conversation/outbound-approval.ts

```ts
/**
 * D-OJ-conv-ai-participant — outbound turn approval flow.
 *
 * Pure approval orchestration — no DB hardwired; everything injected.
 *
 * Implements the state machine transitions for operator-approved sending
 * of AI-produced outbound turns (§9 of ODDJOBZ-CONVERSATION-ARCHITECTURE.md):
 *
 *   proposed → approved → sent
 *                    ↓
 *                 failed  (surface adapter rejects)
 *
 * The confidence-gated auto-approval (D-OJ-conv-confidence-threshold, the
 * NEXT deliverable) plugs in HERE — it will call `approveOutboundTurn`
 * automatically when the confidence score clears the configured threshold,
 * bypassing the operator-review queue. That deliverable does NOT require
 * any structural changes to this module.
 *
 * Architecture constraints:
 *   - Single-threaded reactor / no self-calls (project memory
 *     `semantos_brain_single_threaded_reactor`): `stateSink` is the
 *     injected database-update primitive; it must NOT call back into the
 *     brain's HTTP/REPL endpoints.
 *   - No AI in substrate (`semantos_no_ai_in_substrate`): zero LLM calls.
 *   - Inject everything: `stateSink` and `surfaceSend` are deps, never
 *     hardwired.
 *   - Inbound turns have no `outboundState`; this module only operates
 *     on `direction: 'outbound'` turns.
 */

import type { OddjobzConversationTurnPayload, OutboundStateSink } from './conversation-turn-patch.js';

// ── Public interfaces ─────────────────────────────────────────────────────────

/** The context a single approval operation needs. */
export interface ApprovalContext {
  /** Operator cert id performing the approval. */
  readonly operatorCertId: string;
  /** The turn to approve. Must have `direction: 'outbound'` and
   *  `outboundState: 'proposed'`. */
  readonly turn: OddjobzConversationTurnPayload;
}

/** Injected dependencies for the approval flow.
 *
 *  Both deps are pure from the call site's perspective — all IO
 *  (DB write, surface adapter call) is behind these seams. */
export interface ApprovalDeps {
  /** Persist an `outboundState` transition on the turn's sem_objects row.
   *  Provided by `makeOutboundStateSink(db)` at the brain-reactor boundary. */
  readonly stateSink: OutboundStateSink;
  /** Fire the actual send through the surface adapter (Twilio, SMTP,
   *  IG API, etc.). Returns a structured result, never throws for
   *  delivery-level failures (failed sends return `{ state: 'failed' }`). */
  readonly surfaceSend: (turn: OddjobzConversationTurnPayload) => Promise<{
    state: 'delivered' | 'failed';
    surfaceMessageId?: string;
    error?: string;
  }>;
}

/** Result type returned by `approveOutboundTurn`. */
export type ApprovalResult =
  | { state: 'sent'; surfaceMessageId?: string }
  | { state: 'failed'; error?: string };

// ── ApprovalError ─────────────────────────────────────────────────────────────

/**
 * Thrown when `approveOutboundTurn` is called on a turn whose
 * `outboundState` is not `'proposed'`. Prevents invalid state
 * transitions (e.g. approving an already-approved or operator-drafted
 * turn).
 */
export class ApprovalError extends Error {
  override readonly name = 'ApprovalError';

  constructor(message: string) {
    super(message);
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

// ── Core approval function ────────────────────────────────────────────────────

/**
 * Approve a proposed outbound turn and fire the surface send.
 *
 * State machine transitions (§8.1, §9):
 *   1. Guard: `turn.outboundState` must be `'proposed'`; throw `ApprovalError` otherwise.
 *   2. Transition: `proposed → approved` via `deps.stateSink`.
 *   3. Send: call `deps.surfaceSend(turn)`.
 *   4a. On send success: transition `approved → sent` via `deps.stateSink`;
 *       return `{ state: 'sent', surfaceMessageId? }`.
 *   4b. On send failure: transition `approved → failed` via `deps.stateSink`;
 *       return `{ state: 'failed', error? }`.
 *
 * NOTE: `surfaceSend` is expected to resolve (not reject) for delivery-level
 * failures — it returns `{ state: 'failed', error }` in that case. A thrown
 * exception from `surfaceSend` is treated as a failure (same as `'failed'`
 * result) so the `approved` state is still advanced to `failed` and the
 * error is surfaced.
 *
 * @throws {ApprovalError} when `turn.outboundState !== 'proposed'`.
 */
export async function approveOutboundTurn(
  ctx: ApprovalContext,
  deps: ApprovalDeps,
): Promise<ApprovalResult> {
  const { turn } = ctx;

  // Guard: only 'proposed' turns can be approved.
  if (turn.outboundState !== 'proposed') {
    throw new ApprovalError(
      `approveOutboundTurn: expected outboundState 'proposed' but got '${turn.outboundState ?? '<absent>'}' for turn ${turn.turnId}`,
    );
  }

  // Transition 1: proposed → approved (persisted before send attempt).
  await deps.stateSink(turn.turnId, 'approved');

  // Attempt the send. Treat both structured failures and thrown exceptions
  // as the same 'failed' outcome — the turn's DB state must always be
  // advanced past 'approved' so it never gets stuck.
  let sendResult: { state: 'delivered' | 'failed'; surfaceMessageId?: string; error?: string };
  try {
    sendResult = await deps.surfaceSend(turn);
  } catch (err) {
    const error = err instanceof Error ? err.message : String(err);
    await deps.stateSink(turn.turnId, 'failed');
    return { state: 'failed', error };
  }

  if (sendResult.state === 'failed') {
    await deps.stateSink(turn.turnId, 'failed');
    return { state: 'failed', error: sendResult.error };
  }

  // sendResult.state === 'delivered' (the only other branch from the union).
  // We transition to 'sent' regardless — async delivery callbacks
  // (Twilio webhooks, SMTP DSNs, etc.) drive the 'sent → delivered'
  // transition later. This keeps the approval flow synchronous and avoids
  // racing against out-of-band delivery events.
  await deps.stateSink(turn.turnId, 'sent');
  return { state: 'sent', surfaceMessageId: sendResult.surfaceMessageId };
}

```
