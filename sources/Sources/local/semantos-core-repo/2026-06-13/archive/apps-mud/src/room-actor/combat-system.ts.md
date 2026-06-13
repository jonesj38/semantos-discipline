---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/combat-system.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.840062+00:00
---

# archive/apps-mud/src/room-actor/combat-system.ts

```ts
/**
 * Combat system — pure-ish handlers for monster combat and PvP.
 *
 * Both handlers mutate the supplied `MUDPlayer` and `Monster` in place
 * and return a structured `CombatOutcome` that the facade reads to:
 *   - emit chat-style events to occupants
 *   - emit terminal events (`monster-killed`, `player-died`)
 *   - mark consumed cells (slain monsters, broken gear, dead players)
 *
 * The functions don't talk to atoms directly — that belongs to the
 * facade — so each handler stays independently unit-testable.
 */

import type { Monster } from '../../../../packages/games/src/dungeon/types';

import type { MUDPlayer, RoomEvent, RoomId } from '../types';
import { XP_PER_LEVEL } from '../types';

export interface CombatOutcome {
  /** Aggregated message to send back to the acting player. */
  message: string;
  /** Cell ids of entities consumed during the round (linear destruction). */
  consumedCellIds: string[];
  /** Broadcast events for room occupants (combat, monster-killed, player-died). */
  broadcastEvents: RoomEvent[];
}

export interface ResolveMonsterArgs {
  roomId: RoomId;
  player: MUDPlayer;
  monster: Monster;
}

/** Resolve one round of player-vs-monster combat. Mutates both fighters. */
export function resolveCombatWithMonster(
  args: ResolveMonsterArgs,
): CombatOutcome {
  const { roomId, player, monster } = args;
  const out: CombatOutcome = { message: '', consumedCellIds: [], broadcastEvents: [] };
  const parts: string[] = [];

  const weaponDmg = player.equippedWeapon?.damage ?? 0;
  const playerDamage = Math.max(1, player.attack + weaponDmg - monster.type.defense);
  monster.hp -= playerDamage;
  parts.push(`You hit ${monster.type.name} for ${playerDamage} damage.`);

  // Weapon durability — AFFINE degradation
  if (player.equippedWeapon?.durability !== undefined) {
    player.equippedWeapon.durability--;
    if (player.equippedWeapon.durability <= 0) {
      parts.push(`Your ${player.equippedWeapon.name} breaks!`);
      out.consumedCellIds.push(player.equippedWeapon.entity.id);
      const idx = player.inventory.indexOf(player.equippedWeapon);
      if (idx >= 0) player.inventory.splice(idx, 1);
      player.equippedWeapon = null;
    }
  }

  if (monster.hp <= 0) {
    parts.push(`${monster.type.name} is slain! (+${monster.type.xpReward} XP)`);
    out.consumedCellIds.push(monster.entity.id);
    player.xp += monster.type.xpReward;
    applyLevelUps(player, parts);
    out.broadcastEvents.push({
      type: 'monster-killed',
      roomId,
      playerId: player.id,
      message: `${player.name} slays ${monster.type.name}!`,
    });
  } else {
    // Monster counterattacks
    const armorDef = player.equippedArmor?.defense ?? 0;
    const monsterDamage = Math.max(1, monster.type.attack - player.defense - armorDef);
    player.hp -= monsterDamage;
    parts.push(`${monster.type.name} hits you for ${monsterDamage} damage.`);

    if (player.equippedArmor?.durability !== undefined) {
      player.equippedArmor.durability--;
      if (player.equippedArmor.durability <= 0) {
        parts.push(`Your ${player.equippedArmor.name} breaks!`);
        out.consumedCellIds.push(player.equippedArmor.entity.id);
        const idx = player.inventory.indexOf(player.equippedArmor);
        if (idx >= 0) player.inventory.splice(idx, 1);
        player.equippedArmor = null;
      }
    }

    if (player.hp <= 0) {
      player.hp = 0;
      parts.push('You have been slain!');
      out.broadcastEvents.push({
        type: 'player-died',
        roomId,
        playerId: player.id,
        message: `${player.name} has been slain by ${monster.type.name}!`,
      });
    }

    out.broadcastEvents.push({
      type: 'combat',
      roomId,
      playerId: player.id,
      message: `${player.name} fights ${monster.type.name}.`,
    });
  }

  out.message = parts.join(' ');
  return out;
}

export interface ResolvePvPArgs {
  roomId: RoomId;
  attacker: MUDPlayer;
  defender: MUDPlayer;
}

export interface PvPOutcome extends CombatOutcome {
  /** Attacker may need a precondition error sent back (no weapon). */
  attackerError?: string;
  /** Optional message to send to the defender (taking damage). */
  defenderMessage?: string;
}

/** Resolve one round of PvP combat. Mutates both players. */
export function resolvePvP(args: ResolvePvPArgs): PvPOutcome {
  const { roomId, attacker, defender } = args;
  const out: PvPOutcome = { message: '', consumedCellIds: [], broadcastEvents: [] };

  if (!attacker.equippedWeapon) {
    out.attackerError = 'You have no weapon equipped!';
    return out;
  }

  const weaponDmg = attacker.equippedWeapon.damage ?? 0;
  const armorDef = defender.equippedArmor?.defense ?? 0;
  const damage = Math.max(1, attacker.attack + weaponDmg - defender.defense - armorDef);
  defender.hp -= damage;

  const parts: string[] = [`You hit ${defender.name} for ${damage} damage.`];

  if (defender.hp <= 0) {
    defender.hp = 0;
    parts.push(`${defender.name} has been slain!`);
    out.broadcastEvents.push({
      type: 'player-died',
      roomId,
      playerId: defender.id,
      message: `${defender.name} has been slain by ${attacker.name}!`,
    });
  }

  out.defenderMessage = `${attacker.name} hits you for ${damage} damage! (HP: ${defender.hp}/${defender.maxHp})`;
  out.message = parts.join(' ');
  return out;
}

function applyLevelUps(player: MUDPlayer, parts: string[]): void {
  while (player.xp >= player.xpToLevel) {
    player.xp -= player.xpToLevel;
    player.level++;
    player.maxHp += 5;
    player.hp = player.maxHp;
    player.attack += 1;
    player.defense += 1;
    player.xpToLevel = player.level * XP_PER_LEVEL;
    parts.push(
      `Level up! Now level ${player.level}. (HP: ${player.maxHp}, ATK: ${player.attack}, DEF: ${player.defense})`,
    );
  }
}

```
