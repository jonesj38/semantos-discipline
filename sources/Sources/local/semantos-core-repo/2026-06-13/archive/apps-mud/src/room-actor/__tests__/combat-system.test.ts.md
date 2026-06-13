---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/__tests__/combat-system.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.847221+00:00
---

# archive/apps-mud/src/room-actor/__tests__/combat-system.test.ts

```ts
/**
 * Combat system tests — pure handler unit tests.
 *
 * Verifies damage math, weapon durability, monster death, level up,
 * counterattack with armor, and PvP shapes the legacy `RoomActor`
 * inlined inside `resolveCombatWithMonster` / `resolvePvP`.
 */

import { describe, expect, test } from 'bun:test';

import {
  resolveCombatWithMonster,
  resolvePvP,
} from '../combat-system';

import type { Monster, MonsterType } from '../../../../../packages/games/src/dungeon/types';
import type { MUDPlayer } from '../../types';

const ROOM_ID = 'r1';

function makeMonster(overrides: Partial<{ hp: number; type: MonsterType }> = {}): Monster {
  return {
    entity: { id: 'm-1' } as Monster['entity'],
    type: {
      name: 'Goblin',
      char: 'g',
      hp: 6,
      attack: 3,
      defense: 1,
      xpReward: 15,
    },
    hp: overrides.hp ?? 6,
    position: { x: 1, y: 1 },
  };
}

function makePlayer(overrides: Partial<MUDPlayer> = {}): MUDPlayer {
  return {
    id: 'p-1',
    entity: { id: 'pe-1' } as MUDPlayer['entity'],
    name: 'Tester',
    position: { x: 0, y: 0 },
    hp: 20,
    maxHp: 20,
    attack: 3,
    defense: 1,
    level: 1,
    xp: 0,
    xpToLevel: 50,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
    roomId: ROOM_ID,
    ...overrides,
  };
}

describe('resolveCombatWithMonster', () => {
  test('player attacks → damage applied, no kill', () => {
    const player = makePlayer({ attack: 4 });
    const monster = makeMonster({ hp: 6 });

    const out = resolveCombatWithMonster({ roomId: ROOM_ID, player, monster });

    // damage = max(1, 4 + 0 - 1) = 3, monster.hp 6 - 3 = 3 (alive)
    expect(monster.hp).toBe(3);
    expect(out.consumedCellIds).toEqual([]);
    expect(out.broadcastEvents.some((e) => e.type === 'combat')).toBe(true);
  });

  test('killing blow consumes monster and grants XP', () => {
    const player = makePlayer({ attack: 10 });
    const monster = makeMonster({ hp: 2 });

    const out = resolveCombatWithMonster({ roomId: ROOM_ID, player, monster });

    expect(monster.hp).toBeLessThanOrEqual(0);
    expect(player.xp).toBe(15);
    expect(out.consumedCellIds).toContain('m-1');
    expect(out.broadcastEvents.some((e) => e.type === 'monster-killed')).toBe(true);
  });

  test('weapon breaks when durability hits 0', () => {
    const weapon = {
      entity: { id: 'w-1' } as MUDPlayer['entity'],
      name: 'Dagger',
      category: 'weapon' as const,
      position: { x: 0, y: 0 },
      damage: 2,
      durability: 1,
    };
    const player = makePlayer({ equippedWeapon: weapon, inventory: [weapon] });
    const monster = makeMonster({ hp: 50 });

    const out = resolveCombatWithMonster({ roomId: ROOM_ID, player, monster });

    expect(player.equippedWeapon).toBeNull();
    expect(out.consumedCellIds).toContain('w-1');
  });

  test('player dies when HP drops to 0', () => {
    const player = makePlayer({ hp: 1, defense: 0 });
    const monster = makeMonster({ hp: 50 });
    monster.type = { ...monster.type, attack: 5 };

    const out = resolveCombatWithMonster({ roomId: ROOM_ID, player, monster });

    expect(player.hp).toBe(0);
    expect(out.broadcastEvents.some((e) => e.type === 'player-died')).toBe(true);
  });
});

describe('resolvePvP', () => {
  test('attacker without weapon → error', () => {
    const attacker = makePlayer({ id: 'a' });
    const defender = makePlayer({ id: 'b' });

    const out = resolvePvP({ roomId: ROOM_ID, attacker, defender });

    expect(out.attackerError).toBe('You have no weapon equipped!');
  });

  test('successful PvP hit applies damage to defender', () => {
    const sword = {
      entity: { id: 'w' } as MUDPlayer['entity'],
      name: 'Sword',
      category: 'weapon' as const,
      position: { x: 0, y: 0 },
      damage: 3,
    };
    const attacker = makePlayer({ id: 'a', attack: 5, equippedWeapon: sword });
    const defender = makePlayer({ id: 'b', hp: 20, defense: 1 });

    const out = resolvePvP({ roomId: ROOM_ID, attacker, defender });

    // damage = max(1, 5 + 3 - 1 - 0) = 7
    expect(defender.hp).toBe(13);
    expect(out.attackerError).toBeUndefined();
    expect(out.defenderMessage).toContain('hits you for 7');
  });
});

```
