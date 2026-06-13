---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/phase-fsm.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.806018+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/phase-fsm.test.ts

```ts
/**
 * Phase FSM coverage — exercises every legal (phase, event) pair
 * + every illegal one. Pins the transition graph so the
 * orchestrator can rely on these answers.
 */

import { describe, expect, test } from 'bun:test';
import {
  PHASE_ORDER,
  nextEventFrom,
  phaseReducer,
  type PhaseEvent,
} from '../phase-fsm';
import type { Phase } from '../types';

describe('phaseReducer — betting-complete', () => {
  test('1. preflop → flop', () => {
    expect(phaseReducer('preflop', { type: 'betting-complete' })).toEqual({ next: 'flop' });
  });
  test('2. flop → turn', () => {
    expect(phaseReducer('flop', { type: 'betting-complete' })).toEqual({ next: 'turn' });
  });
  test('3. turn → river', () => {
    expect(phaseReducer('turn', { type: 'betting-complete' })).toEqual({ next: 'river' });
  });
  test('4. river → showdown', () => {
    expect(phaseReducer('river', { type: 'betting-complete' })).toEqual({ next: 'showdown' });
  });
  test('5. showdown rejects betting-complete', () => {
    const r = phaseReducer('showdown', { type: 'betting-complete' });
    expect(r.next).toBe('showdown');
    expect(r.error).toContain('cannot betting-complete');
  });
  test('6. complete rejects betting-complete', () => {
    expect(phaseReducer('complete', { type: 'betting-complete' }).error).toBeDefined();
  });
});

describe('phaseReducer — fold-out', () => {
  test('7. fold-out from any pre-complete phase ends the hand', () => {
    for (const p of ['preflop', 'flop', 'turn', 'river', 'showdown'] as Phase[]) {
      expect(phaseReducer(p, { type: 'fold-out' })).toEqual({ next: 'complete' });
    }
  });
  test('8. fold-out from complete is rejected', () => {
    const r = phaseReducer('complete', { type: 'fold-out' });
    expect(r.error).toContain('already complete');
  });
});

describe('phaseReducer — showdown-resolved', () => {
  test('9. showdown → complete', () => {
    expect(phaseReducer('showdown', { type: 'showdown-resolved' })).toEqual({ next: 'complete' });
  });
  test('10. resolve-from-non-showdown rejected', () => {
    for (const p of ['preflop', 'flop', 'turn', 'river', 'complete'] as Phase[]) {
      const r = phaseReducer(p, { type: 'showdown-resolved' });
      expect(r.error).toContain('cannot resolve showdown');
    }
  });
});

describe('PHASE_ORDER + nextEventFrom', () => {
  test('11. PHASE_ORDER lists every Phase in canonical order', () => {
    expect(PHASE_ORDER).toEqual([
      'preflop', 'flop', 'turn', 'river', 'showdown', 'complete',
    ]);
  });
  test('12. nextEventFrom(showdown) → showdown-resolved', () => {
    expect(nextEventFrom('showdown')).toEqual({ type: 'showdown-resolved' });
  });
  test('13. nextEventFrom(any-non-showdown) → betting-complete', () => {
    for (const p of ['preflop', 'flop', 'turn', 'river', 'complete'] as Phase[]) {
      const event: PhaseEvent = nextEventFrom(p);
      expect(event.type).toBe('betting-complete');
    }
  });
});

```
