---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/combat-engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.406239+00:00
---

# packages/games/src/dungeon/combat-engine.ts

```ts
/**
 * Combat engine — attack resolution, damage calc, durability decay.
 *
 * The legacy engine inlined `attackMonster` next to the move handler.
 * The split exposes `resolveCombat()` as a pure function from the
 * `(player, monster)` pair onto a structured outcome the action
 * dispatcher applies. Returned outcome lists every cell that became
 * consumed (broken weapon, slain monster, broken armor) so the caller
 * can update the `consumedCellsAtom` and the LINEAR/AFFINE accounting.
 */

import type {
  DungeonItem,
  DungeonPlayer,
  Monster,
} from './types';

export interface CombatOutcome {
  /** Damage dealt to the monster this round. */
  playerDamageDealt: number;
  /** Damage dealt to the player by the counter-attack (0 if killed first). */
  monsterDamageDealt: number;
  /** Monster died this round. */
  monsterSlain: boolean;
  /** Player died this round. */
  playerDied: boolean;
  /** Cell ids consumed (slain monster, broken weapon/armor). */
  consumedCellIds: string[];
  /** Item references that should be removed from the player's inventory. */
  itemsToRemove: DungeonItem[];
  /** XP gained this round (always 0 unless `monsterSlain`). */
  xpGained: number;
  /** Human-readable narration fragments — caller joins them. */
  parts: string[];
}

/**
 * Resolve one round of combat between the player and a monster.
 * Mutates `player.hp`, `monster.hp`, weapon/armor durability, and
 * the player's `equippedWeapon` / `equippedArmor` slots in-place.
 *
 * Returns a structured outcome describing every cell-level
 * consequence so the caller can fold the result into atoms / events.
 */
export function resolveCombat(
  player: DungeonPlayer,
  monster: Monster,
): CombatOutcome {
  const consumedCellIds: string[] = [];
  const itemsToRemove: DungeonItem[] = [];
  const parts: string[] = [];

  const weaponDmg = player.equippedWeapon?.damage ?? 0;
  const playerDamageDealt = Math.max(
    1,
    player.attack + weaponDmg - monster.type.defense,
  );
  monster.hp -= playerDamageDealt;
  parts.push(`You hit ${monster.type.name} for ${playerDamageDealt} damage.`);

  // Weapon durability (AFFINE degradation)
  if (player.equippedWeapon?.durability !== undefined) {
    player.equippedWeapon.durability--;
    if (player.equippedWeapon.durability <= 0) {
      const broken = player.equippedWeapon;
      parts.push(`Your ${broken.name} breaks!`);
      consumedCellIds.push(broken.entity.id);
      itemsToRemove.push(broken);
      const idx = player.inventory.indexOf(broken);
      if (idx >= 0) player.inventory.splice(idx, 1);
      player.equippedWeapon = null;
    }
  }

  let monsterSlain = false;
  let monsterDamageDealt = 0;
  let playerDied = false;
  let xpGained = 0;

  if (monster.hp <= 0) {
    monsterSlain = true;
    parts.push(`${monster.type.name} is slain! (+${monster.type.xpReward} XP)`);
    consumedCellIds.push(monster.entity.id);
    xpGained = monster.type.xpReward;
  } else {
    // Monster counterattacks
    const armorDef = player.equippedArmor?.defense ?? 0;
    monsterDamageDealt = Math.max(
      1,
      monster.type.attack - player.defense - armorDef,
    );
    player.hp -= monsterDamageDealt;
    parts.push(
      `${monster.type.name} hits you for ${monsterDamageDealt} damage.`,
    );

    // Armor durability (AFFINE degradation)
    if (player.equippedArmor?.durability !== undefined) {
      player.equippedArmor.durability--;
      if (player.equippedArmor.durability <= 0) {
        const broken = player.equippedArmor;
        parts.push(`Your ${broken.name} breaks!`);
        consumedCellIds.push(broken.entity.id);
        itemsToRemove.push(broken);
        const idx = player.inventory.indexOf(broken);
        if (idx >= 0) player.inventory.splice(idx, 1);
        player.equippedArmor = null;
      }
    }

    if (player.hp <= 0) {
      player.hp = 0;
      playerDied = true;
      parts.push('You have been slain. Game over.');
    }
  }

  return {
    playerDamageDealt,
    monsterDamageDealt,
    monsterSlain,
    playerDied,
    consumedCellIds,
    itemsToRemove,
    xpGained,
    parts,
  };
}

/**
 * Apply XP and walk the player up any level thresholds. Pure-ish:
 * mutates the player's stats and appends narration to `parts`.
 */
export function applyXpAndLevelUp(
  player: DungeonPlayer,
  xpGained: number,
  parts: string[],
  xpPerLevel: number,
): void {
  player.xp += xpGained;
  while (player.xp >= player.xpToLevel) {
    player.xp -= player.xpToLevel;
    player.level++;
    player.maxHp += 5;
    player.hp = player.maxHp;
    player.attack += 1;
    player.defense += 1;
    player.xpToLevel = player.level * xpPerLevel;
    parts.push(
      `Level up! You are now level ${player.level}. (HP: ${player.maxHp}, ATK: ${player.attack}, DEF: ${player.defense})`,
    );
  }
}

```
