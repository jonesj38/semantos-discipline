---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/phase-fsm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.779098+00:00
---

# archive/apps-poker-agent/src/game-loop/phase-fsm.ts

```ts
/**
 * Pure phase reducer — `(phase, event) → nextPhase`.
 *
 * The legacy GameLoop's `playHand()` walked the four pre-showdown
 * betting rounds (preflop / flop / turn / river) followed by a
 * showdown / completion step. This module pins the transition
 * graph as a pure FSM so it can be tested for every (phase, event)
 * pair without spinning up the orchestrator.
 *
 * Events:
 *   - `betting-complete` → next betting round (or showdown)
 *   - `fold-out`         → straight to `complete`
 *   - `showdown-resolved` → `complete`
 *
 * Unknown transitions return the same phase + an `error` so the
 * caller can decide whether to throw.
 */

import type { Phase } from './types';

export type PhaseEvent =
  | { type: 'betting-complete' }
  | { type: 'fold-out' }
  | { type: 'showdown-resolved' };

export interface PhaseTransitionResult {
  next: Phase;
  /** Populated when the transition is not legal. */
  error?: string;
}

const NEXT_BETTING: Record<Phase, Phase | undefined> = {
  preflop: 'flop',
  flop: 'turn',
  turn: 'river',
  river: 'showdown',
  showdown: undefined, // showdown finishes via 'showdown-resolved'
  complete: undefined,
};

export function phaseReducer(phase: Phase, event: PhaseEvent): PhaseTransitionResult {
  switch (event.type) {
    case 'betting-complete': {
      const next = NEXT_BETTING[phase];
      if (!next) {
        return { next: phase, error: `cannot betting-complete from ${phase}` };
      }
      return { next };
    }
    case 'fold-out':
      // Folding ends the hand from any pre-complete phase.
      if (phase === 'complete') {
        return { next: phase, error: 'already complete' };
      }
      return { next: 'complete' };
    case 'showdown-resolved':
      if (phase !== 'showdown') {
        return { next: phase, error: `cannot resolve showdown from ${phase}` };
      }
      return { next: 'complete' };
  }
}

/** Phases in canonical play order. */
export const PHASE_ORDER: readonly Phase[] = [
  'preflop',
  'flop',
  'turn',
  'river',
  'showdown',
  'complete',
];

/** Convenience: the event you'd normally fire from `phase`. */
export function nextEventFrom(phase: Phase): PhaseEvent {
  return phase === 'showdown' ? { type: 'showdown-resolved' } : { type: 'betting-complete' };
}

```
