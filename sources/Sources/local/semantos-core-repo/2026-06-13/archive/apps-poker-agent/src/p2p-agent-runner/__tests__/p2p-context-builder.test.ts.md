---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/__tests__/p2p-context-builder.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.810148+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/__tests__/p2p-context-builder.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildHandContext,
  getLegalActions,
} from '../p2p-context-builder';
import type { P2PAgentConfig, PlayerState, TableState } from '../types';

const config: P2PAgentConfig = {
  gameId: 'g',
  seat: 0,
  opponentIdentityKey: 'opp',
  smallBlind: 5,
  bigBlind: 10,
  startingChips: 100,
  maxHands: 0,
  verbose: false,
};

const player = (opts: Partial<PlayerState> = {}): PlayerState => ({
  name: 'me',
  chips: 100,
  currentBet: 0,
  folded: false,
  allIn: false,
  hasActed: false,
  holeCards: [],
  ...opts,
});

const tbl = (opts: Partial<TableState> = {}): TableState => ({
  phase: 'preflop',
  pot: 0,
  currentBet: 0,
  minRaise: 10,
  communityCards: [],
  dealerSeat: 0,
  handNumber: 1,
  ...opts,
});

describe('getLegalActions', () => {
  test('1. no toCall → check + bet', () => {
    const out = getLegalActions(player(), tbl(), config);
    expect(out).toEqual(['fold', 'check', 'bet (min 10)', 'all-in 100']);
  });
  test('2. with toCall → call + raise', () => {
    const out = getLegalActions(
      player({ currentBet: 0, chips: 100 }),
      tbl({ currentBet: 30 }),
      config,
    );
    expect(out).toContain('call 30');
    expect(out.some((a) => a.startsWith('raise'))).toBe(true);
  });
});

describe('buildHandContext', () => {
  test('3. populates myCards + opponent chips + legal actions', () => {
    const ctx = buildHandContext({
      me: player({ holeCards: [{ suit: 'hearts', rank: 14, label: 'Ah' }] }),
      opponent: player({ name: 'opp', chips: 50 }),
      table: tbl(),
      config,
    });
    expect(ctx.myCards).toEqual(['Ah']);
    expect(ctx.opponentChips).toBe(50);
    expect(ctx.legalActions.length).toBeGreaterThan(0);
  });
});

```
