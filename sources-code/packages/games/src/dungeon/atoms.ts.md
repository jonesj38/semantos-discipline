---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/atoms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.404556+00:00
---

# packages/games/src/dungeon/atoms.ts

```ts
/**
 * Dungeon engine atoms — observable state surface, scoped per engine
 * instance via `getDungeonAtoms(engineId)`.
 *
 * Three atoms per engine:
 *   boardStateAtom    — the live `DungeonBoard` snapshot.
 *   boardHistoryAtom  — chronological list of board cell ids (DAG).
 *   consumedCellsAtom — set of cell ids consumed by LINEAR/AFFINE
 *                       destruction (potions, keys, broken weapons,
 *                       slain monsters).
 *
 * The reducer / facade write into these atoms; renderers and tests
 * subscribe. Per-id scoping mirrors the `getChannelAtoms` pattern
 * established by prompt 15.
 */

import { atom, type Atom } from '@semantos/state';

import type { DungeonBoard, DungeonGameStatus } from './types';

export interface DungeonAtoms {
  /** Engine instance id this bundle is scoped to. */
  engineId: string;
  /** Live board snapshot. */
  boardStateAtom: Atom<DungeonBoard | null>;
  /** Ordered list of board cell ids (head = current). */
  boardHistoryAtom: Atom<string[]>;
  /** Cell ids consumed via LINEAR/AFFINE destruction. */
  consumedCellsAtom: Atom<Set<string>>;
  /** Game status. */
  statusAtom: Atom<DungeonGameStatus>;
}

const registry = new Map<string, DungeonAtoms>();

/**
 * Get (or create) the atom bundle for an engine id. Idempotent — repeat
 * calls return the same bundle so subscribers see the same instance.
 */
export function getDungeonAtoms(engineId: string): DungeonAtoms {
  const existing = registry.get(engineId);
  if (existing) return existing;

  const bundle: DungeonAtoms = {
    engineId,
    boardStateAtom: atom<DungeonBoard | null>(null),
    boardHistoryAtom: atom<string[]>([]),
    consumedCellsAtom: atom<Set<string>>(new Set()),
    statusAtom: atom<DungeonGameStatus>('playing'),
  };
  registry.set(engineId, bundle);
  return bundle;
}

/** Test helper — wipes the registry between cases. */
export function resetDungeonAtoms(): void {
  registry.clear();
}

/** Read-only listing of currently registered engine ids. */
export function listDungeonEngineIds(): string[] {
  return Array.from(registry.keys());
}

```
