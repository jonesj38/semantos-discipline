---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/p2p-betting-engine.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.808697+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/p2p-betting-engine.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { executeAction, placeBet } from '../p2p-betting-engine';
import type { PlayerState, TableState } from '../types';

const me = (opts: Partial<PlayerState> = {}): PlayerState => ({
  name: 'me',
  chips: 100,
  currentBet: 0,
  folded: false,
  allIn: false,
  hasActed: false,
  holeCards: [],
  ...opts,
});

const opp = (opts: Partial<PlayerState> = {}): PlayerState => me({ name: 'opp', ...opts });

const table = (opts: Partial<TableState> = {}): TableState => ({
  phase: 'preflop',
  pot: 0,
  currentBet: 0,
  minRaise: 10,
  communityCards: [],
  dealerSeat: 0,
  handNumber: 1,
  ...opts,
});

describe('placeBet', () => {
  test('1. clamps to chips', () => {
    const p = me({ chips: 30 });
    const t = table();
    placeBet(p, t, 100);
    expect(p.chips).toBe(0);
    expect(p.allIn).toBe(true);
    expect(t.pot).toBe(30);
  });
});

describe('executeAction (mutating P2P engine)', () => {
  test('2. fold sets folded + hasActed', () => {
    const p = me();
    executeAction(p, opp(), table(), { action: 'fold' }, 10);
    expect(p.folded).toBe(true);
  });

  test('3. raise sets currentBet + min-raise + opponent re-act', () => {
    const p = me({ chips: 100, currentBet: 10 });
    const o = opp({ hasActed: true });
    const t = table({ currentBet: 30, minRaise: 20 });
    executeAction(p, o, t, { action: 'raise', amount: 60 }, 10);
    expect(p.chips).toBe(50);
    expect(t.currentBet).toBe(60);
    expect(o.hasActed).toBe(false);
  });

  test('4. call wagers (currentBet - playerBet)', () => {
    const p = me({ currentBet: 5 });
    const t = table({ currentBet: 25 });
    executeAction(p, opp(), t, { action: 'call' }, 10);
    expect(p.chips).toBe(80);
    expect(t.pot).toBe(20);
  });

  test('5. bet pushes bar + flips opponent hasActed', () => {
    const o = opp({ hasActed: true });
    const t = table();
    executeAction(me(), o, t, { action: 'bet', amount: 25 }, 10);
    expect(t.currentBet).toBe(25);
    expect(o.hasActed).toBe(false);
  });

  test('6. all-in below currentBet leaves opponent.hasActed alone', () => {
    const o = opp({ hasActed: true });
    const t = table({ currentBet: 50 });
    executeAction(me({ chips: 10 }), o, t, { action: 'all-in' }, 10);
    expect(o.hasActed).toBe(true);
  });

  test('7. unknown action is a no-op (matches legacy switch fallthrough)', () => {
    const p = me();
    executeAction(p, opp(), table(), { action: 'wat' }, 10);
    expect(p.folded).toBe(false);
    expect(p.hasActed).toBe(false);
  });
});

```
