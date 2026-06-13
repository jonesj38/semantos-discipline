---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.780228+00:00
---

# archive/apps-poker-agent/src/game-loop/atoms.ts

```ts
/**
 * Per-game atom bundle — `playersAtom`, `tableStateAtom`,
 * `currentHandAtom`. Subscribers (dashboards, replay tooling) bind
 * here instead of poking the GameLoop instance.
 */

import { atom, type Atom } from '@semantos/state';

import type { SimplePlayer, SimpleTable } from './types';

export interface GameAtoms {
  gameId: string;
  playersAtom: Atom<SimplePlayer[]>;
  tableStateAtom: Atom<SimpleTable>;
  currentHandAtom: Atom<number>;
}

const registry = new Map<string, GameAtoms>();

const initialTable: SimpleTable = {
  phase: 'complete',
  pot: 0,
  currentBet: 0,
  minRaise: 0,
  communityCards: [],
  dealerIndex: 0,
  activeIndex: 0,
  handNumber: 0,
};

/** Per-game atom bundle. Idempotent. */
export function getGameAtoms(gameId: string): GameAtoms {
  const existing = registry.get(gameId);
  if (existing) return existing;
  const bundle: GameAtoms = {
    gameId,
    playersAtom: atom<SimplePlayer[]>([]),
    tableStateAtom: atom<SimpleTable>({ ...initialTable, communityCards: [] }),
    currentHandAtom: atom<number>(0),
  };
  registry.set(gameId, bundle);
  return bundle;
}

/** Test/teardown helper. */
export function resetGameAtoms(): void {
  registry.clear();
}

```
