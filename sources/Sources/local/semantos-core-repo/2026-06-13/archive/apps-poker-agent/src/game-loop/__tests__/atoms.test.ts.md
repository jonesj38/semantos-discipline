---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/atoms.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.806310+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/atoms.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { get } from '@semantos/state';
import { getGameAtoms, resetGameAtoms } from '../atoms';

afterEach(() => resetGameAtoms());

describe('getGameAtoms', () => {
  test('1. returns the same bundle for the same gameId', () => {
    expect(getGameAtoms('g1')).toBe(getGameAtoms('g1'));
  });

  test('2. distinct gameIds produce distinct bundles', () => {
    expect(getGameAtoms('a')).not.toBe(getGameAtoms('b'));
  });

  test('3. initial table state has phase=complete + handNumber=0', () => {
    const a = getGameAtoms('g');
    const t = get(a.tableStateAtom);
    expect(t.phase).toBe('complete');
    expect(t.handNumber).toBe(0);
    expect(t.communityCards).toEqual([]);
  });

  test('4. resetGameAtoms wipes the registry', () => {
    getGameAtoms('g');
    resetGameAtoms();
    const fresh = getGameAtoms('g');
    expect(get(fresh.currentHandAtom)).toBe(0);
  });
});

```
