---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/outbound-state-machine.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.536171+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/outbound-state-machine.test.ts

```ts
/**
 * D-OJ-conv-outbound-routing — pure unit tests for the outbound state machine.
 *
 * Tests:
 *   OSM-01..04 — valid forward transitions
 *   OSM-05..07 — terminal-state transitions (must all return null)
 *   OSM-08..12 — invalid / backward transitions (must return null)
 *   OSM-13     — all terminal states are correctly identified
 *   OSM-14     — resolveOutboundSurface defaults + pass-through
 *
 * No DB, no IO — pure state machine behaviour only.
 */

import { describe, expect, test } from 'bun:test';
import {
  transitionOutboundState,
  resolveOutboundSurface,
  VALID_TRANSITIONS,
  TERMINAL_OUTBOUND_STATES,
  OUTBOUND_INITIAL_STATE,
  type OutboundState,
  type OutboundEvent,
} from '../outbound-state-machine.js';

// ── OSM-01..04: valid forward transitions ─────────────────────────────────────

describe('transitionOutboundState — valid forward path', () => {
  test('OSM-01 drafted + submit → proposed', () => {
    expect(transitionOutboundState('drafted', 'submit')).toBe('proposed');
  });

  test('OSM-02 proposed + approve → approved', () => {
    expect(transitionOutboundState('proposed', 'approve')).toBe('approved');
  });

  test('OSM-03 approved + accept → sent', () => {
    expect(transitionOutboundState('approved', 'accept')).toBe('sent');
  });

  test('OSM-04a sent + deliver → delivered', () => {
    expect(transitionOutboundState('sent', 'deliver')).toBe('delivered');
  });

  test('OSM-04b sent + fail → failed', () => {
    expect(transitionOutboundState('sent', 'fail')).toBe('failed');
  });

  test('OSM-04c proposed + reject → rejected', () => {
    expect(transitionOutboundState('proposed', 'reject')).toBe('rejected');
  });

  test('OSM-05 drafted + compose → drafted (re-entry / revise before submit)', () => {
    expect(transitionOutboundState('drafted', 'compose')).toBe('drafted');
  });
});

// ── Full forward walk ─────────────────────────────────────────────────────────

describe('transitionOutboundState — full happy-path walk', () => {
  test('drafted → proposed → approved → sent → delivered', () => {
    let state: OutboundState = OUTBOUND_INITIAL_STATE;
    expect(state).toBe('drafted');

    state = transitionOutboundState(state, 'submit') as OutboundState;
    expect(state).toBe('proposed');

    state = transitionOutboundState(state, 'approve') as OutboundState;
    expect(state).toBe('approved');

    state = transitionOutboundState(state, 'accept') as OutboundState;
    expect(state).toBe('sent');

    state = transitionOutboundState(state, 'deliver') as OutboundState;
    expect(state).toBe('delivered');
  });

  test('drafted → proposed → rejected (terminal)', () => {
    let state: OutboundState = OUTBOUND_INITIAL_STATE;
    state = transitionOutboundState(state, 'submit') as OutboundState;
    state = transitionOutboundState(state, 'reject') as OutboundState;
    expect(state).toBe('rejected');
  });

  test('drafted → proposed → approved → sent → failed (terminal)', () => {
    let state: OutboundState = 'approved';
    state = transitionOutboundState(state, 'accept') as OutboundState;
    state = transitionOutboundState(state, 'fail') as OutboundState;
    expect(state).toBe('failed');
  });
});

// ── OSM-06..07: terminal-state transitions all return null ────────────────────

describe('transitionOutboundState — terminal states block all events', () => {
  const terminals: OutboundState[] = ['delivered', 'failed', 'rejected'];
  const allEvents: OutboundEvent[] = [
    'compose',
    'submit',
    'approve',
    'reject',
    'accept',
    'deliver',
    'fail',
  ];

  for (const terminal of terminals) {
    for (const event of allEvents) {
      test(`${terminal} + ${event} → null`, () => {
        expect(transitionOutboundState(terminal, event)).toBeNull();
      });
    }
  }
});

// ── OSM-08..12: invalid / backward transitions return null ────────────────────

describe('transitionOutboundState — invalid transitions', () => {
  test('drafted + approve → null (cannot approve without proposing)', () => {
    expect(transitionOutboundState('drafted', 'approve')).toBeNull();
  });

  test('drafted + accept → null (cannot accept without approval)', () => {
    expect(transitionOutboundState('drafted', 'accept')).toBeNull();
  });

  test('proposed + accept → null (must approve first)', () => {
    expect(transitionOutboundState('proposed', 'accept')).toBeNull();
  });

  test('proposed + deliver → null (cannot deliver without sending)', () => {
    expect(transitionOutboundState('proposed', 'deliver')).toBeNull();
  });

  test('approved + submit → null (already advanced past proposed)', () => {
    expect(transitionOutboundState('approved', 'submit')).toBeNull();
  });

  test('approved + deliver → null (must go through sent first)', () => {
    expect(transitionOutboundState('approved', 'deliver')).toBeNull();
  });

  test('approved + reject → null (rejection is only valid from proposed)', () => {
    expect(transitionOutboundState('approved', 'reject')).toBeNull();
  });

  test('sent + submit → null (backward transition)', () => {
    expect(transitionOutboundState('sent', 'submit')).toBeNull();
  });

  test('sent + approve → null (backward transition)', () => {
    expect(transitionOutboundState('sent', 'approve')).toBeNull();
  });

  test('sent + reject → null (cannot reject from sent)', () => {
    expect(transitionOutboundState('sent', 'reject')).toBeNull();
  });
});

// ── OSM-13: TERMINAL_OUTBOUND_STATES set is correct ──────────────────────────

describe('TERMINAL_OUTBOUND_STATES', () => {
  test('delivered is terminal', () => {
    expect(TERMINAL_OUTBOUND_STATES.has('delivered')).toBe(true);
  });

  test('failed is terminal', () => {
    expect(TERMINAL_OUTBOUND_STATES.has('failed')).toBe(true);
  });

  test('rejected is terminal', () => {
    expect(TERMINAL_OUTBOUND_STATES.has('rejected')).toBe(true);
  });

  test('non-terminal states are NOT in TERMINAL_OUTBOUND_STATES', () => {
    const nonTerminals: OutboundState[] = ['drafted', 'proposed', 'approved', 'sent'];
    for (const s of nonTerminals) {
      expect(TERMINAL_OUTBOUND_STATES.has(s)).toBe(false);
    }
  });

  test('VALID_TRANSITIONS for terminal states have no entries', () => {
    for (const terminal of TERMINAL_OUTBOUND_STATES) {
      const transitions = VALID_TRANSITIONS[terminal];
      expect(Object.keys(transitions).length).toBe(0);
    }
  });
});

// ── OSM-14: resolveOutboundSurface ───────────────────────────────────────────

describe('resolveOutboundSurface', () => {
  test('returns the provided inbound surface', () => {
    expect(resolveOutboundSurface('email')).toBe('email');
  });

  test('returns widget for sms (pass-through)', () => {
    expect(resolveOutboundSurface('sms')).toBe('sms');
  });

  test('returns widget for meta-inbox', () => {
    expect(resolveOutboundSurface('meta-inbox')).toBe('meta-inbox');
  });

  test('defaults to widget when no surface provided', () => {
    expect(resolveOutboundSurface(undefined)).toBe('widget');
  });

  test('defaults to widget when called with no args', () => {
    expect(resolveOutboundSurface()).toBe('widget');
  });

  test('returns voice when voice is latest inbound surface', () => {
    expect(resolveOutboundSurface('voice')).toBe('voice');
  });
});

// ── OUTBOUND_INITIAL_STATE ────────────────────────────────────────────────────

describe('OUTBOUND_INITIAL_STATE', () => {
  test('initial state is drafted', () => {
    expect(OUTBOUND_INITIAL_STATE).toBe('drafted');
  });
});

```
