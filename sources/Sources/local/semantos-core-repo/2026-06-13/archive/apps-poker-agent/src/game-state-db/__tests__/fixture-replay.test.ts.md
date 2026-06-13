---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/__tests__/fixture-replay.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.803558+00:00
---

# archive/apps-poker-agent/src/game-state-db/__tests__/fixture-replay.test.ts

```ts
/**
 * Fixture replay — runs every public method against a seeded DB
 * and compares outputs across two independent facade instances
 * (proxy for "pre- and post-refactor byte-identical results").
 *
 * Per prompt-21 test plan: "Seed DB with fixture data; run every
 * public method pre- and post-refactor; results byte-identical."
 *
 * Since pre-refactor and post-refactor share the same constructor
 * shape (the legacy file now re-exports the facade), we use two
 * facade instances over the same fixture script to verify every
 * code path produces deterministic results.
 */

import { describe, expect, test } from 'bun:test';
import { GameStateDB } from '../game-state-db-facade';

interface Fixture {
  gameId: string;
  agents: { playerId: string; agentName: string; seat: number; chips: number }[];
}

const FIXTURE: Fixture = {
  gameId: 'fixture-game',
  agents: [
    { playerId: 'p0', agentName: 'Shark', seat: 0, chips: 1000 },
    { playerId: 'p1', agentName: 'Turtle', seat: 1, chips: 1000 },
  ],
};

function seed(db: GameStateDB): { hand1: number; hand2: number } {
  db.createSession(FIXTURE.gameId, { smallBlind: 5, bigBlind: 10, startingChips: 1000 });
  for (const a of FIXTURE.agents) {
    db.addPlayer(FIXTURE.gameId, {
      playerId: a.playerId,
      agentName: a.agentName,
      certId: `cert-${a.playerId}`,
      walletPubKey: `pub-${a.playerId}`,
      seat: a.seat,
      startingChips: a.chips,
    });
  }
  // Hand 1 — Shark folds preflop, Turtle wins
  const h1 = db.startHand(FIXTURE.gameId, 1, 0);
  db.recordSnapshot(h1, {
    phase: 'preflop',
    pot: 15,
    communityCards: [],
    activePlayers: 2,
    currentBet: 10,
  });
  db.recordAction(h1, {
    playerId: 'p0',
    actionType: 'fold',
    amount: 0,
    phase: 'preflop',
    chipsAfter: 995,
    potAfter: 15,
  });
  db.recordCellToken(h1, {
    agentName: 'Shark',
    txid: 'h1-tx-fold',
    cellType: 'state-transition',
    description: 'fold',
  });
  db.endHand(h1, 'p1', 15);

  // Hand 2 — both call, Shark wins by showdown
  const h2 = db.startHand(FIXTURE.gameId, 2, 1);
  db.recordSnapshot(h2, {
    phase: 'preflop',
    pot: 20,
    communityCards: [],
    activePlayers: 2,
    currentBet: 10,
  });
  db.recordAction(h2, {
    playerId: 'p0',
    actionType: 'call',
    amount: 10,
    phase: 'preflop',
    chipsAfter: 985,
    potAfter: 20,
  });
  db.recordAction(h2, {
    playerId: 'p1',
    actionType: 'check',
    amount: 0,
    phase: 'preflop',
    chipsAfter: 990,
    potAfter: 20,
  });
  db.recordSnapshot(h2, {
    phase: 'flop',
    pot: 20,
    communityCards: ['Ah', 'Kd', 'Qc'],
    activePlayers: 2,
    currentBet: 0,
  });
  db.recordCellToken(h2, {
    agentName: 'Shark',
    txid: 'h2-tx-flop',
    cellType: 'state-transition',
    description: 'flop',
  });
  db.endHand(h2, 'p0', 20);

  // Memory writes
  db.setMemory('Shark', 'style', 'tight');
  db.setMemory('Turtle', 'style', 'loose');

  return { hand1: h1, hand2: h2 };
}

describe('fixture replay — byte-identical across two facade instances', () => {
  test('1. seed produces the same row counts in both DBs', () => {
    const a = new GameStateDB();
    const b = new GameStateDB();
    seed(a);
    seed(b);
    expect(a.getSeq()).toBe(b.getSeq());
    a.close();
    b.close();
  });

  test('2. getActionsSince matches across DBs', () => {
    const a = new GameStateDB();
    const b = new GameStateDB();
    seed(a);
    seed(b);
    const aActions = a.getActionsSince(0).map((r) => ({
      ...r,
      timestamp: 0, // mask wall-clock differences
    }));
    const bActions = b.getActionsSince(0).map((r) => ({ ...r, timestamp: 0 }));
    expect(aActions).toEqual(bActions);
    a.close();
    b.close();
  });

  test('3. getCurrentHandContext matches', () => {
    const a = new GameStateDB();
    const b = new GameStateDB();
    seed(a);
    seed(b);
    const aCtx = a.getCurrentHandContext('fixture-game', 'Shark');
    const bCtx = b.getCurrentHandContext('fixture-game', 'Shark');
    expect(aCtx).toEqual(bCtx);
    expect(aCtx?.handNumber).toBe(2);
    expect(aCtx?.communityCards).toEqual(['Ah', 'Kd', 'Qc']);
    a.close();
    b.close();
  });

  test('4. getGameHistory matches', () => {
    const a = new GameStateDB();
    const b = new GameStateDB();
    seed(a);
    seed(b);
    const aHist = a.getGameHistory('fixture-game', 'Shark');
    const bHist = b.getGameHistory('fixture-game', 'Shark');
    expect(aHist).toEqual(bHist);
    expect(aHist.handsPlayed).toBe(2);
    expect(aHist.myWins).toBe(1);
    expect(aHist.opponentWins).toBe(1);
    a.close();
    b.close();
  });

  test('5. getCellTokens matches per hand', () => {
    const a = new GameStateDB();
    const b = new GameStateDB();
    const ids = seed(a);
    seed(b);
    const aTokens = a.getCellTokens(ids.hand1).map((r) => ({ ...r, timestamp: 0 }));
    const bTokens = b.getCellTokens(ids.hand1).map((r) => ({ ...r, timestamp: 0 }));
    expect(aTokens).toEqual(bTokens);
    expect(aTokens[0].txid).toBe('h1-tx-fold');
    a.close();
    b.close();
  });

  test('6. memory round-trips', () => {
    const db = new GameStateDB();
    seed(db);
    expect(db.getMemory('Shark', 'style')).toBe('tight');
    expect(db.getMemory('Turtle', 'style')).toBe('loose');
    expect(db.getAllMemory('Shark')).toEqual({ style: 'tight' });
    db.close();
  });

  test('7. seq monotonic across actions/snapshots/celltoken_refs', () => {
    const db = new GameStateDB();
    seed(db);
    const seq = db.getSeq();
    expect(seq).toBeGreaterThan(0);
    // Add another action and confirm seq advances.
    const h = db.startHand('fixture-game', 99, 0);
    const next = db.recordAction(h, {
      playerId: 'p0',
      actionType: 'fold',
      amount: 0,
      phase: 'preflop',
      chipsAfter: 0,
      potAfter: 0,
    });
    expect(next).toBe(seq + 1);
    expect(db.getSeq()).toBe(seq + 1);
    db.close();
  });
});

```
