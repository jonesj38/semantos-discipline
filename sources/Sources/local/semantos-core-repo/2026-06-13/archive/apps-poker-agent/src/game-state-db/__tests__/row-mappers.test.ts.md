---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/__tests__/row-mappers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.802977+00:00
---

# archive/apps-poker-agent/src/game-state-db/__tests__/row-mappers.test.ts

```ts
/**
 * Standalone row-mapper tests. Per prompt-21 acceptance: "Row
 * mappers exported and tested standalone." No DB needed — fixture
 * a row literal, assert the mapped shape.
 */

import { describe, expect, test } from 'bun:test';
import {
  mapActionRow,
  mapAgentMemoryRow,
  mapCellTokenRefRow,
  mapHandRow,
  mapPlayerRow,
  mapSessionRow,
  mapStateSnapshotRow,
  parseCommunityCards,
} from '../row-mappers';

describe('mapSessionRow', () => {
  test('1. coerces every field to its declared type', () => {
    const out = mapSessionRow({
      game_id: 'g',
      small_blind: '5' as unknown as number,
      big_blind: 10,
      starting_chips: 1000,
      created_at: 1700000000000,
      status: 'active',
    });
    expect(out.small_blind).toBe(5);
    expect(out.status).toBe('active');
  });
});

describe('mapPlayerRow', () => {
  test('2. round-trips a typical row', () => {
    const out = mapPlayerRow({
      game_id: 'g',
      player_id: 'p0',
      agent_name: 'Shark',
      cert_id: 'c',
      wallet_pub_key: 'k',
      seat: 0,
      starting_chips: 1000,
    });
    expect(out.agent_name).toBe('Shark');
    expect(out.seat).toBe(0);
  });
});

describe('mapHandRow', () => {
  test('3. preserves null for ended_at + winner_id', () => {
    const out = mapHandRow({
      hand_id: 1,
      game_id: 'g',
      hand_number: 1,
      dealer_seat: 0,
      started_at: 1,
      ended_at: null,
      winner_id: null,
      pot_total: 0,
    });
    expect(out.ended_at).toBeNull();
    expect(out.winner_id).toBeNull();
  });

  test('4. coerces ended_at + winner_id when set', () => {
    const out = mapHandRow({
      hand_id: 1,
      game_id: 'g',
      hand_number: 1,
      dealer_seat: 0,
      started_at: 1,
      ended_at: 2,
      winner_id: 'p0',
      pot_total: 30,
    });
    expect(out.ended_at).toBe(2);
    expect(out.winner_id).toBe('p0');
  });
});

describe('mapActionRow + mapStateSnapshotRow + mapCellTokenRefRow + mapAgentMemoryRow', () => {
  test('5. all four shapes round-trip', () => {
    expect(
      mapActionRow({
        seq: 1,
        hand_id: 1,
        player_id: 'p',
        action_type: 'call',
        amount: 10,
        phase: 'preflop',
        chips_after: 90,
        pot_after: 30,
        timestamp: 0,
      }).seq,
    ).toBe(1);
    expect(
      mapStateSnapshotRow({
        seq: 1,
        hand_id: 1,
        phase: 'flop',
        pot: 50,
        community_cards: '["Ah"]',
        active_players: 2,
        current_bet: 0,
        timestamp: 0,
      }).community_cards,
    ).toBe('["Ah"]');
    expect(
      mapCellTokenRefRow({
        seq: 1,
        hand_id: 1,
        agent_name: 'A',
        txid: 't',
        cell_type: 'state-transition',
        description: 'd',
        timestamp: 0,
      }).cell_type,
    ).toBe('state-transition');
    expect(
      mapAgentMemoryRow({
        agent_name: 'A',
        key: 'k',
        value: 'v',
        updated_at: 0,
      }).key,
    ).toBe('k');
  });
});

describe('parseCommunityCards', () => {
  test('6. parses a JSON array', () => {
    expect(
      parseCommunityCards({
        community_cards: '["Ah","Kd"]',
      } as never),
    ).toEqual(['Ah', 'Kd']);
  });

  test('7. returns [] on malformed JSON', () => {
    expect(
      parseCommunityCards({ community_cards: 'not-json' } as never),
    ).toEqual([]);
  });

  test('8. returns [] on non-array JSON', () => {
    expect(
      parseCommunityCards({ community_cards: '"hello"' } as never),
    ).toEqual([]);
  });
});

```
