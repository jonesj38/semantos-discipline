---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-loop/__tests__/betting-engine.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.804787+00:00
---

# archive/apps-poker-agent/src/game-loop/__tests__/betting-engine.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { executeAction, placeBet } from '../betting-engine';
import type { CardDescriptor, SimplePlayer, SimpleTable } from '../types';

const _empty: CardDescriptor[] = [];

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
    ..._empty.length ? {} : {},
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

describe('placeBet', () => {
  test('1. clamps to player.chips', () => {
    const r = placeBet(p({ chips: 30 }), 100);
    expect(r.actual).toBe(30);
    expect(r.player.chipsDelta).toBe(-30);
    expect(r.player.allIn).toBe(true);
    expect(r.table.potDelta).toBe(30);
  });
  test('2. zero amount produces zero deltas', () => {
    const r = placeBet(p(), 0);
    expect(r.actual).toBe(0);
    expect(r.player.allIn).toBeUndefined();
  });
  test('3. flags allIn when chips reach 0 exactly', () => {
    const r = placeBet(p({ chips: 25 }), 25);
    expect(r.player.allIn).toBe(true);
  });
});

describe('executeAction', () => {
  test('4. fold sets folded + hasActed', () => {
    const { player } = executeAction(p(), t(), { action: 'fold' }, 10);
    expect(player.folded).toBe(true);
    expect(player.hasActed).toBe(true);
  });
  test('5. check makes no chip movement', () => {
    const { player, table } = executeAction(p(), t(), { action: 'check' }, 10);
    expect(player.chipsDelta).toBe(0);
    expect(table.potDelta).toBe(0);
  });
  test('6. call wagers (currentBet - playerBet)', () => {
    const { player, table } = executeAction(
      p({ currentBet: 5 }),
      t({ currentBet: 25 }),
      { action: 'call' },
      10,
    );
    expect(player.chipsDelta).toBe(-20);
    expect(table.potDelta).toBe(20);
    expect(table.resetHasActedOnOthers).toBe(false);
  });
  test('7. bet sets newCurrentBet + minRaise + reset-others', () => {
    const { player, table } = executeAction(p(), t(), { action: 'bet', amount: 30 }, 10);
    expect(player.chipsDelta).toBe(-30);
    expect(table.newCurrentBet).toBe(30);
    expect(table.newMinRaise).toBe(30);
    expect(table.resetHasActedOnOthers).toBe(true);
  });
  test('8. raise computes total amount + min-raise bump', () => {
    const { player, table } = executeAction(
      p({ chips: 100, currentBet: 10 }),
      t({ currentBet: 30, minRaise: 20 }),
      { action: 'raise', amount: 60 },
      10,
    );
    expect(player.chipsDelta).toBe(-50);
    expect(table.newCurrentBet).toBe(60);
    expect(table.newMinRaise).toBe(30);
    expect(table.resetHasActedOnOthers).toBe(true);
  });
  test('9. all-in pushes the bar when over current', () => {
    const { player, table } = executeAction(
      p({ chips: 80 }),
      t({ currentBet: 30, minRaise: 20 }),
      { action: 'all-in' },
      10,
    );
    expect(player.chipsDelta).toBe(-80);
    expect(player.allIn).toBe(true);
    expect(table.newCurrentBet).toBe(80);
    expect(table.resetHasActedOnOthers).toBe(true);
  });
  test('10. all-in below currentBet does not reset others', () => {
    const { table } = executeAction(
      p({ chips: 10 }),
      t({ currentBet: 50 }),
      { action: 'all-in' },
      10,
    );
    expect(table.newCurrentBet).toBeUndefined();
    expect(table.resetHasActedOnOthers).toBe(false);
  });
  test('11. unknown action falls through to fold', () => {
    const { player } = executeAction(p(), t(), { action: 'wat' }, 10);
    expect(player.folded).toBe(true);
  });
});

```
