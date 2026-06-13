---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/__tests__/seq-counter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.803843+00:00
---

# archive/apps-poker-agent/src/game-state-db/__tests__/seq-counter.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { Database } from 'bun:sqlite';
import { applySchema } from '../schema';
import { makeSeqCounter } from '../seq-counter';

function freshDb(): Database {
  const db = new Database(':memory:');
  applySchema(db);
  return db;
}

describe('makeSeqCounter', () => {
  test('1. starts at 0 on a fresh DB', () => {
    const counter = makeSeqCounter(freshDb());
    expect(counter.current()).toBe(0);
    expect(counter.next()).toBe(1);
    expect(counter.next()).toBe(2);
  });

  test('2. resumes from the highest persisted seq across all three tables', () => {
    const db = freshDb();
    db.prepare(
      `INSERT INTO actions (seq, hand_id, player_id, action_type, amount, phase, chips_after, pot_after, timestamp)
       VALUES (?, 1, 'p', 'fold', 0, 'preflop', 0, 0, 0)`,
    ).run(7);
    db.prepare(
      `INSERT INTO state_snapshots (seq, hand_id, phase, pot, community_cards, active_players, current_bet, timestamp)
       VALUES (?, 1, 'flop', 0, '[]', 2, 0, 0)`,
    ).run(15);
    db.prepare(
      `INSERT INTO celltoken_refs (seq, hand_id, agent_name, txid, cell_type, description, timestamp)
       VALUES (?, 1, 'A', 't', 'state-transition', 'd', 0)`,
    ).run(11);
    const counter = makeSeqCounter(db);
    expect(counter.current()).toBe(15);
    expect(counter.next()).toBe(16);
  });

  test('3. monotonic across many calls', () => {
    const counter = makeSeqCounter(freshDb());
    const seen: number[] = [];
    for (let i = 0; i < 100; i++) seen.push(counter.next());
    for (let i = 1; i < seen.length; i++) {
      expect(seen[i]).toBeGreaterThan(seen[i - 1]);
    }
  });
});

```
