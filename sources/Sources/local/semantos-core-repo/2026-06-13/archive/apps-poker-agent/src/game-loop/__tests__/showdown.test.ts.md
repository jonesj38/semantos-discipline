---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/showdown.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.805076+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/showdown.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { simpleShowdown, totalsByName } from '../showdown';
import type { CardDescriptor, SimplePlayer } from '../types';

const c = (rank: number): CardDescriptor => ({ suit: 'hearts', rank: rank as any, label: '' });

function player(name: string, opts: Partial<SimplePlayer> = {}): SimplePlayer {
  return {
    id: name,
    name,
    chips: 0,
    currentBet: 0,
    folded: false,
    allIn: false,
    hasActed: false,
    holeCards: [],
    ...opts,
  };
}

describe('simpleShowdown (legacy rank-sum scorer — pinned for byte parity)', () => {
  test('1. higher rank-sum wins', () => {
    const winner = simpleShowdown(
      [
        player('A', { holeCards: [c(14), c(13)] }),
        player('B', { holeCards: [c(2), c(3)] }),
      ],
      [c(10)],
    );
    expect(winner.name).toBe('A');
  });

  test('2. tie favours player 0 (legacy `>=` behaviour)', () => {
    const winner = simpleShowdown(
      [
        player('A', { holeCards: [c(7), c(7)] }),
        player('B', { holeCards: [c(7), c(7)] }),
      ],
      [],
    );
    expect(winner.name).toBe('A');
  });

  test('3. folded players score -1 → opponent wins', () => {
    const winner = simpleShowdown(
      [
        player('A', { folded: true, holeCards: [c(14), c(14)] }),
        player('B', { holeCards: [c(2), c(3)] }),
      ],
      [],
    );
    expect(winner.name).toBe('B');
  });
});

describe('totalsByName', () => {
  test('4. projects {name, chips} pairs', () => {
    expect(
      totalsByName([
        player('A', { chips: 100 }),
        player('B', { chips: 50 }),
      ]),
    ).toEqual([
      { name: 'A', chips: 100 },
      { name: 'B', chips: 50 },
    ]);
  });
});

```
