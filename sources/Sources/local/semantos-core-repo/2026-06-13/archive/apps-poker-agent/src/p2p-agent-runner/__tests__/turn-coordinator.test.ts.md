---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/turn-coordinator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.810723+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/turn-coordinator.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  awaitMyTurn,
  flipTurn,
  getTurn,
  resetTurnAtoms,
  setTurn,
} from '../turn-coordinator';

afterEach(() => resetTurnAtoms());

describe('turn-coordinator', () => {
  test('1. defaults to opponent', () => {
    expect(getTurn('g1')).toBe('opponent');
  });

  test('2. setTurn / getTurn round-trip', () => {
    setTurn('g1', 'mine');
    expect(getTurn('g1')).toBe('mine');
  });

  test('3. flipTurn alternates', () => {
    setTurn('g1', 'mine');
    expect(flipTurn('g1')).toBe('opponent');
    expect(flipTurn('g1')).toBe('mine');
  });

  test('4. distinct gameIds isolate state', () => {
    setTurn('g1', 'mine');
    setTurn('g2', 'opponent');
    expect(getTurn('g1')).toBe('mine');
    expect(getTurn('g2')).toBe('opponent');
  });

  test('5. awaitMyTurn resolves immediately when already mine', async () => {
    setTurn('g1', 'mine');
    let resolved = false;
    await awaitMyTurn('g1').then(() => {
      resolved = true;
    });
    expect(resolved).toBe(true);
  });

  test('6. awaitMyTurn blocks until flip', async () => {
    setTurn('g1', 'opponent');
    let resolved = false;
    const promise = awaitMyTurn('g1').then(() => {
      resolved = true;
    });
    expect(resolved).toBe(false);
    setTurn('g1', 'mine');
    await promise;
    expect(resolved).toBe(true);
  });

  test('7. resetTurnAtoms wipes the registry', () => {
    setTurn('g1', 'mine');
    resetTurnAtoms();
    expect(getTurn('g1')).toBe('opponent');
  });
});

```
