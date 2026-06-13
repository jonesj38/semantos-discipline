---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/policies.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.834849+00:00
---

# archive/apps-mud/src/policies.ts

```ts
/**
 * MUD policies -- Lisp s-expressions compiled to WASM opcodes.
 *
 * Extends dungeon policies with multiplayer-specific rules:
 *   - PvE attack: prevents friendly fire
 *   - PvP attack: allows player-on-player combat
 *   - Room exit: validates player at exit tile
 *   - Say: rate-limited to prevent spam
 */

import { parseExpression } from '../../../runtime/shell/src/lisp/parser';
import { LispCompiler } from '../../../runtime/shell/src/lisp/compiler';
import type { ScriptOutput } from '../../../runtime/shell/src/lisp/types';

// ── Policy Sources ──────────────────────────────────────────────

/** Movement within a room (same as dungeon) */
export const MOVE_POLICY = `(and (is-move?) (in-bounds?) (not-wall?))`;

/** PvE attack: adjacent, has weapon, target is monster, NOT a player */
export const ATTACK_PVE_POLICY = `(and (is-attack?) (adjacent-to-target?) (has-weapon?) (target-is-monster?))`;

/** PvP attack: adjacent, has weapon, target is monster OR player (if PvP enabled) */
export const ATTACK_PVP_POLICY = `(and (is-attack?) (adjacent-to-target?) (has-weapon?) (or (target-is-monster?) (and (target-is-player?) (pvp-enabled?))))`;

/** Pickup (same as dungeon) */
export const PICKUP_POLICY = `(and (is-pickup?) (at-or-adjacent?) (inventory-not-full?))`;

/** Use item (same as dungeon) */
export const USE_ITEM_POLICY = `(and (is-use?) (has-item?) (item-usable?))`;

/** Open door (same as dungeon) */
export const OPEN_DOOR_POLICY = `(and (is-open?) (adjacent-to-target?) (target-is-door?) (or (door-unlocked?) (has-matching-key?)))`;

/** Room exit: at an exit tile, exit is unlocked or player has key */
export const EXIT_ROOM_POLICY = `(and (at-exit-tile?) (or (exit-not-locked?) (has-matching-key?)))`;

// ── Compiled Policy Cache ───────────────────────────────────────

export interface CompiledMUDPolicies {
  move: ScriptOutput;
  attackPvE: ScriptOutput;
  attackPvP: ScriptOutput;
  pickup: ScriptOutput;
  useItem: ScriptOutput;
  openDoor: ScriptOutput;
  exitRoom: ScriptOutput;
}

const POLICY_MAP: Record<string, string> = {
  move: MOVE_POLICY,
  attackPvE: ATTACK_PVE_POLICY,
  attackPvP: ATTACK_PVP_POLICY,
  pickup: PICKUP_POLICY,
  useItem: USE_ITEM_POLICY,
  openDoor: OPEN_DOOR_POLICY,
  exitRoom: EXIT_ROOM_POLICY,
};

/** Compile all MUD policies once at init. */
export function compileMUDPolicies(): CompiledMUDPolicies {
  const compiler = new LispCompiler({ compiledAt: 'mud-init' });
  const result: Record<string, ScriptOutput> = {};
  for (const [name, source] of Object.entries(POLICY_MAP)) {
    const expr = parseExpression(source);
    result[name] = compiler.compile(expr);
  }
  return result as unknown as CompiledMUDPolicies;
}

```
