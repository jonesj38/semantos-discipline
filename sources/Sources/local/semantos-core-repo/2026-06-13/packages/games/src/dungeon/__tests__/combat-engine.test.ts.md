---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/__tests__/combat-engine.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.433027+00:00
---

# packages/games/src/dungeon/__tests__/combat-engine.test.ts

```ts
/**
 * Combat-engine tests — `resolveCombat` + `applyXpAndLevelUp` are
 * pure functions over `(player, monster)` so the tests don't need
 * the WASM kernel.
 */

import { describe, expect, test } from 'bun:test';

import { applyXpAndLevelUp, resolveCombat } from '../combat-engine';
import type { GameEntity } from '../../../../game-sdk/src/types';
import type { DungeonItem, DungeonPlayer, Monster } from '../types';
import { MONSTER_TYPES, XP_PER_LEVEL } from '../types';

function fakeEntity(id: string): GameEntity {
  return { id, cell: new Uint8Array() } as unknown as GameEntity;
}

function basePlayer(): DungeonPlayer {
  return {
    entity: fakeEntity('player'),
    position: { x: 0, y: 0 },
    hp: 30,
    maxHp: 30,
    attack: 2,
    defense: 0,
    level: 1,
    xp: 0,
    xpToLevel: XP_PER_LEVEL,
    gold: 0,
    inventory: [],
    equippedWeapon: null,
    equippedArmor: null,
  };
}

function makeMonster(typeKey: keyof typeof MONSTER_TYPES, hp?: number): Monster {
  const type = MONSTER_TYPES[typeKey];
  return {
    entity: fakeEntity(`monster-${typeKey}`),
    type,
    hp: hp ?? type.hp,
    position: { x: 1, y: 0 },
  };
}

describe('resolveCombat', () => {
  test('player damages monster with bare hands', () => {
    const player = basePlayer();
    const rat = makeMonster('rat');
    const out = resolveCombat(player, rat);
    expect(out.playerDamageDealt).toBeGreaterThanOrEqual(1);
    expect(rat.hp).toBeLessThanOrEqual(MONSTER_TYPES.rat.hp - 1);
  });

  test('weapon damage adds to attack', () => {
    const player = basePlayer();
    const dagger: DungeonItem = {
      entity: fakeEntity('dagger'),
      name: 'Dagger',
      category: 'weapon',
      position: { x: 0, y: 0 },
      damage: 5,
      durability: 5,
    };
    player.inventory.push(dagger);
    player.equippedWeapon = dagger;
    const rat = makeMonster('rat');
    const before = rat.hp;
    const out = resolveCombat(player, rat);
    expect(out.playerDamageDealt).toBe(player.attack + 5 - rat.type.defense);
    expect(before - rat.hp).toBe(out.playerDamageDealt);
  });

  test('weapon breaks when durability hits zero', () => {
    const player = basePlayer();
    const dagger: DungeonItem = {
      entity: fakeEntity('dagger'),
      name: 'Dagger',
      category: 'weapon',
      position: { x: 0, y: 0 },
      damage: 1,
      durability: 1,
    };
    player.inventory.push(dagger);
    player.equippedWeapon = dagger;
    const rat = makeMonster('rat', 100); // never dies
    const out = resolveCombat(player, rat);
    expect(player.equippedWeapon).toBeNull();
    expect(out.consumedCellIds).toContain('dagger');
    expect(out.itemsToRemove).toContain(dagger);
  });

  test('monster slain awards xp + lists cell consumed', () => {
    const player = basePlayer();
    const rat = makeMonster('rat', 1);
    const out = resolveCombat(player, rat);
    expect(out.monsterSlain).toBe(true);
    expect(out.xpGained).toBe(MONSTER_TYPES.rat.xpReward);
    expect(out.consumedCellIds).toContain('monster-rat');
    expect(out.playerDied).toBe(false);
  });

  test('monster counterattacks when surviving', () => {
    const player = basePlayer();
    const orc = makeMonster('orc', 100); // never dies in one hit
    const out = resolveCombat(player, orc);
    expect(out.monsterSlain).toBe(false);
    expect(out.monsterDamageDealt).toBeGreaterThanOrEqual(1);
    expect(player.hp).toBeLessThan(30);
  });

  test('player dies when hp ≤ 0 from counterattack', () => {
    const player = basePlayer();
    player.hp = 1;
    const orc = makeMonster('orc', 100);
    const out = resolveCombat(player, orc);
    expect(out.playerDied).toBe(true);
    expect(player.hp).toBe(0);
  });
});

describe('applyXpAndLevelUp', () => {
  test('applies xp up to threshold', () => {
    const player = basePlayer();
    const parts: string[] = [];
    applyXpAndLevelUp(player, 10, parts, XP_PER_LEVEL);
    expect(player.level).toBe(1);
    expect(player.xp).toBe(10);
    expect(parts).toHaveLength(0);
  });

  test('levels up when xp ≥ threshold', () => {
    const player = basePlayer();
    const parts: string[] = [];
    applyXpAndLevelUp(player, XP_PER_LEVEL, parts, XP_PER_LEVEL);
    expect(player.level).toBe(2);
    expect(player.maxHp).toBe(35);
    expect(player.attack).toBe(3);
    expect(player.defense).toBe(1);
    expect(parts.length).toBeGreaterThan(0);
  });

  test('cascades multiple level-ups when xp surplus is enormous', () => {
    const player = basePlayer();
    const parts: string[] = [];
    // XP_PER_LEVEL=50, level 2 needs another 100, level 3 needs 150
    applyXpAndLevelUp(player, 50 + 100 + 150 + 5, parts, XP_PER_LEVEL);
    expect(player.level).toBe(4);
    expect(player.xp).toBe(5);
    expect(parts.length).toBe(3);
  });
});

```
