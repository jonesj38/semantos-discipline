---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/outbound-state-machine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.524818+00:00
---

# cartridges/oddjobz/brain/src/conversation/outbound-state-machine.ts

```ts
/**
 * D-OJ-conv-outbound-routing — outbound state machine.
 *
 * Implements the state machine from §8.1 of
 * ODDJOBZ-CONVERSATION-ARCHITECTURE.md:
 *
 *   drafted → proposed → approved → sent → delivered | failed
 *                   ↓
 *               rejected (terminal)
 *
 * States:
 *   drafted   — operator or AI is composing.
 *   proposed  — AI produced a draft awaiting operator approval, OR
 *               operator produced a draft awaiting their own "send".
 *   approved  — operator approved; the intent pipeline mints an
 *               `outbound_send` intent.
 *   sent      — surface adapter accepted the send; awaiting confirmation.
 *   delivered — terminal: confirmed delivered by the surface adapter.
 *   failed    — terminal: delivery failed (reported by the adapter).
 *   rejected  — terminal: operator rejected the draft.
 *
 * Design constraints:
 *   - Pure TypeScript, no DB, no IO.
 *   - No AI calls (per `semantos_no_ai_in_substrate`).
 *   - `transitionOutboundState` returns null for invalid transitions
 *     (caller decides how to handle — throw or log).
 *   - `resolveOutboundSurface` is the surface-selection policy (§8.2):
 *     default to the last inbound surface; operator override stays with
 *     the caller.
 */

import type { ConversationSurface } from './conversation-turn-patch.js';

// ── State union ───────────────────────────────────────────────────────────────

/**
 * Outbound turn state machine states (§8.1).
 *
 * Terminal states: `delivered`, `failed`, `rejected`.
 * Non-terminal: `drafted`, `proposed`, `approved`, `sent`.
 */
export type OutboundState =
  | 'drafted'
  | 'proposed'
  | 'approved'
  | 'sent'
  | 'delivered'
  | 'failed'
  | 'rejected';

/** Terminal states — no further transitions are valid from these. */
export const TERMINAL_OUTBOUND_STATES: ReadonlySet<OutboundState> = new Set([
  'delivered',
  'failed',
  'rejected',
]);

// ── Event union ───────────────────────────────────────────────────────────────

/**
 * Events that drive the outbound state machine.
 *
 *   compose    — operator or AI starts composing; draft created.
 *   submit     — draft submitted for review / sent to "proposed".
 *   approve    — operator approved the proposal; intent pipeline fires.
 *   reject     — operator rejected the proposal (terminal).
 *   accept     — surface adapter accepted the send request.
 *   deliver    — surface adapter confirmed delivery (terminal).
 *   fail       — surface adapter reported failure (terminal).
 */
export type OutboundEvent =
  | 'compose'
  | 'submit'
  | 'approve'
  | 'reject'
  | 'accept'
  | 'deliver'
  | 'fail';

// ── Valid transitions ─────────────────────────────────────────────────────────

/**
 * Adjacency map for the outbound state machine (§8.1).
 *
 * `VALID_TRANSITIONS[currentState][event] = nextState`
 *
 * Reading the spec literally:
 *   drafted  → (submit)   → proposed
 *   proposed → (approve)  → approved
 *   proposed → (reject)   → rejected    (terminal)
 *   approved → (accept)   → sent
 *   sent     → (deliver)  → delivered   (terminal)
 *   sent     → (fail)     → failed      (terminal)
 *
 * `compose` is an initialising event (null → drafted); it is included
 * as an event on `drafted` as a no-op re-entry when the composer
 * revises the draft before submitting.
 *
 * Terminals have no outbound transitions.
 */
export const VALID_TRANSITIONS: Readonly<
  Record<OutboundState, Partial<Record<OutboundEvent, OutboundState>>>
> = {
  drafted: {
    compose: 'drafted', // re-entry: revising before submit
    submit: 'proposed',
  },
  proposed: {
    approve: 'approved',
    reject: 'rejected',
  },
  approved: {
    accept: 'sent',
  },
  sent: {
    deliver: 'delivered',
    fail: 'failed',
  },
  // Terminal states — no further transitions.
  delivered: {},
  failed: {},
  rejected: {},
};

// ── State transition function ─────────────────────────────────────────────────

/**
 * Apply `event` to `current` and return the next state, or `null` when
 * the transition is invalid.
 *
 * Returns `null` (not thrown) so the caller can choose how to surface the
 * error — e.g. log + skip for resilient sinks, throw for strict pipelines.
 *
 * Pure — no IO.
 */
export function transitionOutboundState(
  current: OutboundState,
  event: OutboundEvent,
): OutboundState | null {
  const transitions = VALID_TRANSITIONS[current];
  const next = transitions[event];
  return next ?? null;
}

// ── Initial state factory ─────────────────────────────────────────────────────

/**
 * The initial state for a new outbound turn: `drafted`.
 *
 * An outbound turn ALWAYS starts in `drafted` — either by the operator
 * composing a reply, or by the AI generating a candidate. The composer
 * then calls `submit` to transition to `proposed`.
 */
export const OUTBOUND_INITIAL_STATE: OutboundState = 'drafted';

// ── Surface resolution (§8.2) ─────────────────────────────────────────────────

/**
 * Resolve the outbound surface for a reply (§8.2).
 *
 * Default policy: use the same surface the customer used for their most
 * recent inbound message. This ensures replies go back over the channel
 * the customer is already on.
 *
 * When `latestInboundSurface` is absent (no inbound context available),
 * falls back to `'widget'` — the canonical default surface.
 *
 * Operator override (e.g. "customer always emails but operator wants to
 * SMS them") is NOT implemented here — it stays with the caller, which
 * passes the desired surface directly instead of using this function.
 *
 * Pure — no IO.
 */
export function resolveOutboundSurface(
  latestInboundSurface?: ConversationSurface,
): ConversationSurface {
  return latestInboundSurface ?? 'widget';
}

```
