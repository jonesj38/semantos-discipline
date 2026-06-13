---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/hand-context-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.804506+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/hand-context-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildHandContext,
  getLegalActions,
} from '../hand-context-builder';
import type { GameLoopConfig, SimplePlayer, SimpleTable } from '../types';

const config: GameLoopConfig = {
  gameId: 'g',
  smallBlind: 5,
  bigBlind: 10,
  startingChips: 100,
  maxHands: 0,
  anchorOnChain: false,
  actionDelay: 0,
  verbose: false,
  turbo: false,
  lean: false,
};

function p(opts: Partial<SimplePlayer> = {}): SimplePlayer {
  return {
    id: 'p',
    name: 'P',
    chips: 100,
    currentBet: 0,
    folded: false,
    allIn: false,
    hasActed: false,
    holeCards: [],
    ...opts,
  };
}

function t(opts: Partial<SimpleTable> = {}): SimpleTable {
  return {
    phase: 'preflop',
    pot: 0,
    currentBet: 0,
    minRaise: 10,
    communityCards: [],
    dealerIndex: 0,
    activeIndex: 0,
    handNumber: 1,
    ...opts,
  };
}

describe('getLegalActions', () => {
  test('1. no toCall → check + bet', () => {
    const out = getLegalActions(p(), t(), config);
    expect(out).toEqual(['fold', 'check', 'bet (min 10)', 'all-in 100']);
  });
  test('2. with toCall → call + raise', () => {
    const out = getLegalActions(
      p({ chips: 100, currentBet: 0 }),
      t({ currentBet: 30, minRaise: 20 }),
      config,
    );
    expect(out).toContain('call 30');
    expect(out).toContain('raise (min 50)');
  });
  test('3. raise only listed when player has stack to raise', () => {
    const out = getLegalActions(
      p({ chips: 5, currentBet: 0 }),
      t({ currentBet: 30 }),
      config,
    );
    expect(out.some((a) => a.startsWith('raise'))).toBe(false);
  });
});

describe('buildHandContext', () => {
  test('4. populates myCards + opponentChips + legalActions', () => {
    const ctx = buildHandContext({
      player: p({ holeCards: [{ suit: 'hearts', rank: 14, label: 'Ah' }] }),
      opponent: p({ name: 'O', chips: 50 }),
      table: t({ phase: 'preflop' }),
      config,
      agentName: 'Alice',
    });
    expect(ctx.myCards).toEqual(['Ah']);
    expect(ctx.opponentChips).toBe(50);
    expect(ctx.legalActions.length).toBeGreaterThan(0);
  });
});

```
