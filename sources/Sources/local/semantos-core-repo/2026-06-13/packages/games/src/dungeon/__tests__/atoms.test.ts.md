---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/atoms.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.433896+00:00
---

# packages/games/src/dungeon/__tests__/atoms.test.ts

```ts
/**
 * Dungeon-atom registry tests.
 */

import { afterEach, describe, expect, test } from 'bun:test';

import { get, set } from '@semantos/state';

import {
  getDungeonAtoms,
  listDungeonEngineIds,
  resetDungeonAtoms,
} from '../atoms';

afterEach(() => {
  resetDungeonAtoms();
});

describe('getDungeonAtoms', () => {
  test('returns the same bundle for the same id (idempotent)', () => {
    const a = getDungeonAtoms('e1');
    const b = getDungeonAtoms('e1');
    expect(a).toBe(b);
  });

  test('distinct ids get distinct bundles', () => {
    const a = getDungeonAtoms('e1');
    const b = getDungeonAtoms('e2');
    expect(a).not.toBe(b);
    expect(a.boardStateAtom).not.toBe(b.boardStateAtom);
  });

  test('initial atom values are sensible defaults', () => {
    const a = getDungeonAtoms('e1');
    expect(get(a.boardStateAtom)).toBeNull();
    expect(get(a.boardHistoryAtom)).toEqual([]);
    expect(get(a.consumedCellsAtom).size).toBe(0);
    expect(get(a.statusAtom)).toBe('playing');
  });

  test('atom writes flow through to subsequent reads', () => {
    const a = getDungeonAtoms('e1');
    set(a.statusAtom, 'dead');
    expect(get(a.statusAtom)).toBe('dead');
  });

  test('listDungeonEngineIds reflects registry contents', () => {
    getDungeonAtoms('alpha');
    getDungeonAtoms('beta');
    const ids = listDungeonEngineIds();
    expect(ids.sort()).toEqual(['alpha', 'beta']);
  });

  test('resetDungeonAtoms wipes the registry', () => {
    getDungeonAtoms('x');
    resetDungeonAtoms();
    expect(listDungeonEngineIds()).toHaveLength(0);
  });
});

```
