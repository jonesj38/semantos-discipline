---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/trade-events.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.498205+00:00
---

# packages/cdm/cdm/src/lifecycle/trade-events.ts

```ts
/**
 * CDM TradeEvent union — per-event payload typing + validators + the
 * canonical state-transition table.
 *
 * Each lifecycle event the reducer accepts is described here. The
 * reducer (`event-reducer.ts`) consumes this table; flow modules
 * (`novation.ts`, `termination.ts`, `increase.ts`, `decrease.ts`)
 * consume the per-event validators.
 *
 * Pure module — no IO, no `Date.now()`, no `Math.random()`.
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import type {
  CDMEventType,
  CDMLifecycleState,
  CDMProduct,
  EconomicEffect,
} from '../types';

// ── State Transition Table ─────────────────────────────────────

/**
 * Maps (currentState, eventType) → nextState.
 * If the event is not listed for a state, the transition is rejected.
 */
export const TRANSITION_TABLE: Record<
  CDMLifecycleState,
  Partial<Record<CDMEventType, CDMLifecycleState>>
> = {
  'proposed': {
    'execution': 'executed',
  },
  'executed': {
    'confirmation': 'confirmed',
    'novation': 'novated',
    'default': 'defaulted',
    'full-termination': 'terminated',
  },
  'confirmed': {
    'clearing': 'cleared',
    'novation': 'novated',
    'partial-termination': 'partially-terminated',
    'full-termination': 'terminated',
    'rate-reset': 'confirmed',
    'payment': 'confirmed',
    'margin-call': 'confirmed',
    'default': 'defaulted',
  },
  'cleared': {
    'settlement': 'settled',
    'novation': 'novated',
    'partial-termination': 'partially-terminated',
    'full-termination': 'terminated',
    'rate-reset': 'cleared',
    'payment': 'cleared',
    'margin-call': 'cleared',
    'default': 'defaulted',
  },
  'settled': {
    'full-termination': 'terminated',
  },
  'novated': {},
  'partially-terminated': {
    'partial-termination': 'partially-terminated',
    'full-termination': 'terminated',
    'rate-reset': 'partially-terminated',
    'payment': 'partially-terminated',
    'margin-call': 'partially-terminated',
    'default': 'defaulted',
  },
  'terminated': {},
  'defaulted': {
    'close-out-netting': 'close-out',
  },
  'close-out': {},
};

/** Terminal events that trigger anchor tx emission. */
export const TERMINAL_EVENTS: readonly CDMEventType[] = [
  'execution',
  'novation',
  'settlement',
  'full-termination',
  'close-out-netting',
];

// ── Per-Event Payload Types ────────────────────────────────────

/**
 * `TradeEvent` — discriminated union of every CDM lifecycle event the
 * reducer accepts.
 *
 * Kept structural (not Variant<>) so the existing public API
 * (`engine.executeEvent(product, eventType, ...)`) keeps working
 * unchanged: callers still pass `eventType` + a free-form payload.
 * The reducer wraps that into a `TradeEvent` internally.
 */
export type TradeEvent =
  | { type: 'execution'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'confirmation'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'clearing'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'settlement'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'novation'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'partial-termination'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'full-termination'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'rate-reset'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'payment'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'margin-call'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'default'; effectiveDate: string; payload: TradeEventPayload }
  | { type: 'close-out-netting'; effectiveDate: string; payload: TradeEventPayload };

/** Free-form payload — kept generic to preserve byte-identical public API. */
export type TradeEventPayload = Record<string, unknown>;

// ── Helpers ────────────────────────────────────────────────────

/** Look up `(state, eventType) → nextState` or `undefined` if rejected. */
export function nextStateFor(
  state: CDMLifecycleState,
  eventType: CDMEventType,
): CDMLifecycleState | undefined {
  return TRANSITION_TABLE[state]?.[eventType];
}

/** Whether a transition is allowed from the given state. */
export function canTransition(
  state: CDMLifecycleState,
  eventType: CDMEventType,
): boolean {
  return nextStateFor(state, eventType) !== undefined;
}

/** Valid event types for a given state, in declaration order. */
export function validEventsFor(state: CDMLifecycleState): CDMEventType[] {
  const valid = TRANSITION_TABLE[state];
  return valid ? (Object.keys(valid) as CDMEventType[]) : [];
}

/** Whether an event is "terminal" — terminal events emit an anchor tx. */
export function isTerminalEvent(eventType: CDMEventType): boolean {
  return TERMINAL_EVENTS.includes(eventType);
}

// ── Per-Event Validators ──────────────────────────────────────

/**
 * Validate a `TradeEvent` against the current product. Returns
 * `{ ok: true }` on success, `{ ok: false, error }` otherwise.
 *
 * Pure — no IO. Used by the reducer to short-circuit invalid events
 * before mutating state.
 */
export function validateTradeEvent(
  product: CDMProduct,
  event: TradeEvent,
): { ok: true } | { ok: false; error: string } {
  if (!canTransition(product.lifecycleState, event.type)) {
    return {
      ok: false,
      error:
        `Cannot apply '${event.type}' to product in state '${product.lifecycleState}'. ` +
        `Valid events: [${validEventsFor(product.lifecycleState).join(', ')}]`,
    };
  }
  // Per-event business rules. Empty for events whose only constraint
  // is the transition table; populated for those with extra rules.
  switch (event.type) {
    case 'partial-termination': {
      const change = event.payload?.notionalChange;
      if (typeof change === 'number' && change > 0) {
        return {
          ok: false,
          error: 'partial-termination expects a negative notionalChange',
        };
      }
      return { ok: true };
    }
    default:
      return { ok: true };
  }
}

/** Extract an `EconomicEffect` from a payload, or undefined if none. */
export function economicEffectFrom(
  payload: TradeEventPayload,
): EconomicEffect | undefined {
  if (payload.notionalChange !== undefined) {
    return { notionalChange: payload.notionalChange as number };
  }
  if (payload.rateReset !== undefined) {
    return {
      rateReset: payload.rateReset as { newRate: number; resetDate: string },
    };
  }
  return undefined;
}

```
