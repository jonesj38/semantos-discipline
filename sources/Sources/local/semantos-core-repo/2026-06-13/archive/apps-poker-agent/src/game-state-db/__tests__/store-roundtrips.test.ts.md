---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/__tests__/store-roundtrips.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.803273+00:00
---

# archive/apps-poker-agent/src/game-state-db/__tests__/store-roundtrips.test.ts

```ts
/**
 * Per-store round-trip tests against a fresh in-memory DB. These
 * verify the SQL boundary independently of the facade.
 */

import { describe, expect, test } from 'bun:test';
import { Database } from 'bun:sqlite';
import { ActionStore } from '../action-store';
import { CellTokenRefStore } from '../celltoken-ref-store';
import { HandStore } from '../hand-store';
import { MemoryStore } from '../memory-store';
import { applySchema } from '../schema';
import { makeSeqCounter } from '../seq-counter';
import { SessionStore } from '../session-store';
import { SnapshotStore } from '../snapshot-store';

function fresh(): Database {
  const db = new Database(':memory:');
  applySchema(db);
  return db;
}

describe('SessionStore', () => {
  test('1. createSession + addPlayer commit + readable via raw query', () => {
    const db = fresh();
    const store = new SessionStore(db);
    store.createSession('g', { smallBlind: 5, bigBlind: 10, startingChips: 1000 });
    store.addPlayer('g', {
      playerId: 'p0',
      agentName: 'Shark',
      certId: 'c',
      walletPubKey: 'k',
      seat: 0,
      startingChips: 1000,
    });
    const row = db.prepare('SELECT * FROM players WHERE player_id = ?').get('p0') as { agent_name: string };
    expect(row.agent_name).toBe('Shark');
  });
});

describe('HandStore', () => {
  test('2. startHand returns hand_id; endHand updates winner', () => {
    const db = fresh();
    const sessions = new SessionStore(db);
    sessions.createSession('g', { smallBlind: 5, bigBlind: 10, startingChips: 1000 });
    const hand = new HandStore(db);
    const id = hand.startHand('g', 1, 0);
    expect(id).toBeGreaterThan(0);
    hand.endHand(id, 'p0', 30);
    const row = db.prepare('SELECT * FROM hands WHERE hand_id = ?').get(id) as {
      winner_id: string;
      pot_total: number;
    };
    expect(row.winner_id).toBe('p0');
    expect(row.pot_total).toBe(30);
  });
});

describe('ActionStore', () => {
  test('3. recordAction returns monotonic seq', () => {
    const db = fresh();
    const seq = makeSeqCounter(db);
    const store = new ActionStore(db, seq);
    const a = store.recordAction(1, {
      playerId: 'p0',
      actionType: 'fold',
      amount: 0,
      phase: 'preflop',
      chipsAfter: 1000,
      potAfter: 0,
    });
    const b = store.recordAction(1, {
      playerId: 'p0',
      actionType: 'call',
      amount: 10,
      phase: 'preflop',
      chipsAfter: 990,
      potAfter: 10,
    });
    expect(b).toBeGreaterThan(a);
  });

  test('4. getActionsSince filters by seq + optional handId', () => {
    const db = fresh();
    const seq = makeSeqCounter(db);
    const store = new ActionStore(db, seq);
    store.recordAction(1, { playerId: 'p', actionType: 'fold', amount: 0, phase: 'p', chipsAfter: 0, potAfter: 0 });
    const cutoff = seq.current();
    store.recordAction(1, { playerId: 'p', actionType: 'call', amount: 10, phase: 'p', chipsAfter: 0, potAfter: 0 });
    store.recordAction(2, { playerId: 'p', actionType: 'raise', amount: 30, phase: 'p', chipsAfter: 0, potAfter: 0 });
    expect(store.getActionsSince(cutoff).map((a) => a.action_type)).toEqual(['call', 'raise']);
    expect(store.getActionsSince(cutoff, 1).map((a) => a.action_type)).toEqual(['call']);
  });
});

describe('SnapshotStore + CellTokenRefStore + MemoryStore', () => {
  test('5. recordSnapshot persists JSON-encoded community_cards', () => {
    const db = fresh();
    const seq = makeSeqCounter(db);
    const store = new SnapshotStore(db, seq);
    store.recordSnapshot(1, {
      phase: 'flop',
      pot: 50,
      communityCards: ['Ah', 'Kd', 'Qc'],
      activePlayers: 2,
      currentBet: 0,
    });
    const out = store.getSnapshotsSince(0);
    expect(out).toHaveLength(1);
    expect(JSON.parse(out[0].community_cards)).toEqual(['Ah', 'Kd', 'Qc']);
  });

  test('6. CellTokenRefStore.recordCellToken + getCellTokens round-trip', () => {
    const db = fresh();
    const seq = makeSeqCounter(db);
    const store = new CellTokenRefStore(db, seq);
    store.recordCellToken(1, {
      agentName: 'A',
      txid: 'tx-a',
      cellType: 'state-transition',
      description: 'd',
    });
    const out = store.getCellTokens(1);
    expect(out.map((r) => r.txid)).toEqual(['tx-a']);
  });

  test('7. MemoryStore upserts on conflict', () => {
    const db = fresh();
    const store = new MemoryStore(db);
    store.setMemory('A', 'k', 'first');
    store.setMemory('A', 'k', 'second');
    expect(store.getMemory('A', 'k')).toBe('second');
    store.setMemory('A', 'other', 'val');
    expect(store.getAllMemory('A')).toEqual({ k: 'second', other: 'val' });
  });

  test('8. MemoryStore returns null for missing key', () => {
    const db = fresh();
    const store = new MemoryStore(db);
    expect(store.getMemory('A', 'no')).toBeNull();
  });
});

```
