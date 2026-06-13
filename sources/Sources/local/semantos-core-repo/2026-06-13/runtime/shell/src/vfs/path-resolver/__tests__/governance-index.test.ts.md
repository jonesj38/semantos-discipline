---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/__tests__/governance-index.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.393852+00:00
---

# runtime/shell/src/vfs/path-resolver/__tests__/governance-index.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  getattrGovernance,
  readGovernance,
  readdirGovernance,
} from '../governance-index';
import type { LoomStore } from '@semantos/runtime-services';

interface FakeObj {
  id: string;
  visibility: string;
  payload: Record<string, unknown>;
  typeDefinition: { category?: string };
}

function makeStore(objs: FakeObj[]): LoomStore {
  const map = new Map(objs.map((o) => [o.id, o]));
  return {
    getState: () => ({ objects: map as unknown as Map<string, unknown> }),
  } as unknown as LoomStore;
}

describe('readdirGovernance', () => {
  test('1. root yields ballots + disputes', () => {
    expect(readdirGovernance(makeStore([]), [])).toEqual(['ballots', 'disputes']);
  });

  test('2. ballots/ filters by category substring', () => {
    const store = makeStore([
      { id: 'b1', visibility: 'draft', payload: {}, typeDefinition: { category: 'governance.ballot' } },
      { id: 'd1', visibility: 'draft', payload: {}, typeDefinition: { category: 'governance.dispute' } },
    ]);
    expect(readdirGovernance(store, ['ballots'])).toEqual(['b1.json']);
    expect(readdirGovernance(store, ['disputes'])).toEqual(['d1.json']);
  });

  test('3. unknown category returns null', () => {
    expect(readdirGovernance(makeStore([]), ['mystery'])).toBeNull();
  });

  test('4. deep paths return null', () => {
    expect(readdirGovernance(makeStore([]), ['ballots', 'extra'])).toBeNull();
  });
});

describe('readGovernance', () => {
  test('5. returns the object payload merged with id + visibility', () => {
    const store = makeStore([
      {
        id: 'b1',
        visibility: 'published',
        payload: { motion: 'do it' },
        typeDefinition: { category: 'governance.ballot' },
      },
    ]);
    const out = readGovernance(store, ['ballots', 'b1.json']);
    expect(out).not.toBeNull();
    const body = JSON.parse(out!.data.toString('utf-8'));
    expect(body).toEqual({ motion: 'do it', id: 'b1', visibility: 'published' });
  });

  test('6. non-.json file path returns null', () => {
    const store = makeStore([
      { id: 'b1', visibility: 'd', payload: {}, typeDefinition: { category: 'governance.ballot' } },
    ]);
    expect(readGovernance(store, ['ballots', 'b1'])).toBeNull();
  });

  test('7. unknown id returns null', () => {
    expect(readGovernance(makeStore([]), ['ballots', 'never.json'])).toBeNull();
  });
});

describe('getattrGovernance', () => {
  test('8. category folders are directories', () => {
    expect(getattrGovernance(makeStore([]), ['ballots'])).toEqual({
      type: 'directory',
      name: 'ballots',
      size: 0,
    });
    expect(getattrGovernance(makeStore([]), ['mystery'])).toBeNull();
  });

  test('9. file entry size matches readGovernance content', () => {
    const store = makeStore([
      { id: 'b1', visibility: 'd', payload: {}, typeDefinition: { category: 'governance.ballot' } },
    ]);
    const entry = getattrGovernance(store, ['ballots', 'b1.json']);
    expect(entry?.type).toBe('file');
    expect(entry?.size).toBe(readGovernance(store, ['ballots', 'b1.json'])!.size);
  });
});

```
