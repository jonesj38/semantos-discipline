---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/turn-coordinator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.789128+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/turn-coordinator.ts

```ts
/**
 * Turn coordinator — atom-backed `'mine' | 'opponent'` flag with
 * promise-based blocking.
 *
 * Replaces the inline `myTurn = true/false` in the legacy runner so
 * tests can drive turn handoff deterministically without going
 * through the transport.
 *
 * Per prompt-20 acceptance: "Turn coordination testable without a
 * real transport." The atom + the `awaitMyTurn(gameId)` promise
 * are the test surface.
 */

import { atom, get, set, subscribe, type Atom } from '@semantos/state';

export type Turn = 'mine' | 'opponent';

export interface TurnAtoms {
  gameId: string;
  turnAtom: Atom<Turn>;
}

const registry = new Map<string, TurnAtoms>();

export function getTurnAtoms(gameId: string): TurnAtoms {
  const existing = registry.get(gameId);
  if (existing) return existing;
  const bundle: TurnAtoms = {
    gameId,
    turnAtom: atom<Turn>('opponent'),
  };
  registry.set(gameId, bundle);
  return bundle;
}

export function resetTurnAtoms(): void {
  registry.clear();
}

export function setTurn(gameId: string, turn: Turn): void {
  set(getTurnAtoms(gameId).turnAtom, turn);
}

export function getTurn(gameId: string): Turn {
  return get(getTurnAtoms(gameId).turnAtom);
}

export function flipTurn(gameId: string): Turn {
  const next = getTurn(gameId) === 'mine' ? 'opponent' : 'mine';
  setTurn(gameId, next);
  return next;
}

/**
 * Resolve the next time the turn flips to `'mine'`. Resolves
 * immediately if it's already mine.
 */
export function awaitMyTurn(gameId: string): Promise<void> {
  const { turnAtom } = getTurnAtoms(gameId);
  if (get(turnAtom) === 'mine') return Promise.resolve();
  return new Promise<void>((resolve) => {
    const dispose = subscribe(turnAtom, (next) => {
      if (next === 'mine') {
        dispose();
        resolve();
      }
    });
  });
}

```
