---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/action-dispatcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.401499+00:00
---

# packages/games/src/dungeon/action-dispatcher.ts

```ts
/**
 * Dungeon action dispatcher — registers handlers for the six public
 * dungeon actions on top of the `makeEngineTemplate` action surface.
 *
 * Actions:
 *   Move       — direction → walks the player + auto-attack on collide
 *   Attack     — direction → forced combat resolution
 *   Pickup     — index?    → adds the floor item to the inventory
 *   Use        — index     → potion/scroll/equip
 *   OpenDoor   — direction → opens door, consuming key if locked
 *   Descend    — none       → moves to next floor or wins
 *
 * The handlers are thin orchestrators: they consult the policy
 * evaluator, mutate the in-memory `DungeonBoard`, and return a
 * structured `ActionResult` the facade wraps + emits.
 *
 * The board-snapshot commit + terminal-event anchor + atom updates
 * are delegated back to the facade via the `Effects` interface so the
 * dispatcher itself stays IO-free.
 */

import { applyXpAndLevelUp, resolveCombat } from './combat-engine';
import { applyVisibility, type FovProvider } from './fov-system';
import {
  autoPickupTreasure,
  openDoorAt,
  pickupItem,
  useItem,
} from './inventory-system';
import type { DungeonPolicyEvaluator } from './movement-validator';
import {
  DIRECTION_OFFSETS,
  MAX_FLOORS,
  Tile,
  XP_PER_LEVEL,
  posKey,
  type ActionResult,
  type Direction,
  type DungeonBoard,
  type DungeonGameStatus,
  type Monster,
} from './types';

// ── Public action union ────────────────────────────────────────

export type DungeonAction =
  | { type: 'move'; direction: Direction }
  | { type: 'attack'; direction: Direction }
  | { type: 'pickup'; itemIndex?: number }
  | { type: 'use'; itemIndex: number }
  | { type: 'open-door'; direction: Direction }
  | { type: 'descend' };

// ── Dispatcher dependencies ────────────────────────────────────

export interface DispatcherDeps {
  /** Mutable runtime state surface — the engine instance. */
  ctx: DispatcherContext;
  /** Policy evaluator — wraps the WASM kernel. */
  policy: DungeonPolicyEvaluator;
}

export interface DispatcherContext {
  /** Current board snapshot — handlers mutate sub-fields. */
  board: DungeonBoard;
  /** Game status — handlers may flip to dead/victory. */
  status: DungeonGameStatus;
  /** Cell ids consumed by LINEAR/AFFINE destruction. */
  consumedCells: Set<string>;
  /** Visible tile keys ("x,y"). */
  visibleTiles: Set<string>;
  /** Explored tile keys ("x,y"). */
  exploredTiles: Set<string>;
  /** FOV provider for the current floor. */
  fov: FovProvider;
  /** Rebuild FOV when the floor or visibility might have changed. */
  recomputeFov: () => void;
  /** Generate + populate the next floor, return player start position. */
  generateNextFloor: (floorIndex: number) => void;
  /** Commit board snapshot + maybe anchor terminal event. */
  commit: (message: string) => ActionResult;
  /** Build a non-committing result (policy-rejected etc.). */
  result: (message: string) => ActionResult;
  /** Throws if status !== playing. */
  assertPlaying: () => void;
}

// ── Dispatch ──────────────────────────────────────────────────

/**
 * Synchronously route a `DungeonAction` to the right handler. We
 * keep it synchronous (matching the legacy `move/attack/...`
 * signature) — `makeEngineTemplate.dispatch` is async-aware and the
 * facade wraps this in an async outer if needed.
 */
export function dispatchDungeonAction(
  deps: DispatcherDeps,
  action: DungeonAction,
): ActionResult {
  switch (action.type) {
    case 'move':
      return handleMove(deps, action.direction);
    case 'attack':
      return handleAttack(deps, action.direction);
    case 'pickup':
      return handlePickup(deps, action.itemIndex);
    case 'use':
      return handleUse(deps, action.itemIndex);
    case 'open-door':
      return handleOpenDoor(deps, action.direction);
    case 'descend':
      return handleDescend(deps);
  }
}

// ── Move ──────────────────────────────────────────────────────

function handleMove(deps: DispatcherDeps, direction: Direction): ActionResult {
  const { ctx, policy } = deps;
  ctx.assertPlaying();
  const player = ctx.board.player;
  const [dx, dy] = DIRECTION_OFFSETS[direction];
  const tx = player.position.x + dx;
  const ty = player.position.y + dy;

  const floor = ctx.board.floors[ctx.board.floor];
  const monsterAtTarget = floor.monsters.find(
    (m) => m.hp > 0 && m.position.x === tx && m.position.y === ty,
  );
  if (monsterAtTarget) {
    return resolveAttack(deps, monsterAtTarget);
  }

  if (!policy.evaluate({ action: 'move', targetX: tx, targetY: ty, board: ctx.board })) {
    return ctx.result(`Can't move ${direction} -- blocked.`);
  }

  player.position = { x: tx, y: ty };
  ctx.board.turnNumber++;
  ctx.recomputeFov();

  let msg = `Moved ${direction}.`;
  const auto = autoPickupTreasure(ctx.board, player);
  if (auto.pickedUp) {
    for (const id of auto.consumedCellIds) ctx.consumedCells.add(id);
    msg += auto.message;
  }

  return ctx.commit(msg);
}

// ── Attack ────────────────────────────────────────────────────

function handleAttack(
  deps: DispatcherDeps,
  direction: Direction,
): ActionResult {
  const { ctx, policy } = deps;
  ctx.assertPlaying();
  const player = ctx.board.player;
  const [dx, dy] = DIRECTION_OFFSETS[direction];
  const tx = player.position.x + dx;
  const ty = player.position.y + dy;

  const floor = ctx.board.floors[ctx.board.floor];
  const monster = floor.monsters.find(
    (m) => m.hp > 0 && m.position.x === tx && m.position.y === ty,
  );

  if (!policy.evaluate({ action: 'attack', targetX: tx, targetY: ty, board: ctx.board })) {
    if (!monster) return ctx.result('Nothing to attack there.');
    return ctx.result('Cannot attack -- no weapon equipped!');
  }

  return resolveAttack(deps, monster!);
}

function resolveAttack(deps: DispatcherDeps, monster: Monster): ActionResult {
  const { ctx } = deps;
  const player = ctx.board.player;
  const outcome = resolveCombat(player, monster);

  for (const id of outcome.consumedCellIds) ctx.consumedCells.add(id);

  if (outcome.monsterSlain) {
    applyXpAndLevelUp(player, outcome.xpGained, outcome.parts, XP_PER_LEVEL);
  } else if (outcome.playerDied) {
    ctx.status = 'dead';
  }

  ctx.board.turnNumber++;
  return ctx.commit(outcome.parts.join(' '));
}

// ── Pickup ────────────────────────────────────────────────────

function handlePickup(
  deps: DispatcherDeps,
  itemIndex?: number,
): ActionResult {
  const { ctx, policy } = deps;
  ctx.assertPlaying();
  const player = ctx.board.player;
  const floor = ctx.board.floors[ctx.board.floor];

  // Pre-check: is there anything here?
  const itemsHere = floor.items.filter((i) => {
    const p = i.position;
    return p.x === player.position.x && p.y === player.position.y;
  });
  if (itemsHere.length === 0) {
    return ctx.result('Nothing to pick up here.');
  }
  const targetItem =
    itemIndex !== undefined ? itemsHere[itemIndex] : itemsHere[0];
  if (!targetItem) return ctx.result('No item at that index.');

  if (
    !policy.evaluate({
      action: 'pickup',
      targetX: targetItem.position.x,
      targetY: targetItem.position.y,
      board: ctx.board,
    })
  ) {
    return ctx.result('Inventory is full!');
  }

  const { item, message } = pickupItem(ctx.board, player, itemIndex);
  if (!item) return ctx.result(message);

  ctx.board.turnNumber++;
  return ctx.commit(message);
}

// ── Use ───────────────────────────────────────────────────────

function handleUse(deps: DispatcherDeps, itemIndex: number): ActionResult {
  const { ctx, policy } = deps;
  ctx.assertPlaying();
  const player = ctx.board.player;
  const item = player.inventory[itemIndex];
  if (!item) return ctx.result('No item at that index.');

  const isUsable =
    item.category === 'potion' ||
    item.category === 'scroll' ||
    item.category === 'weapon' ||
    item.category === 'armor';

  if (
    !policy.evaluate({
      action: 'use',
      targetX: player.position.x,
      targetY: player.position.y,
      board: ctx.board,
      extras: { hasItem: true, itemUsable: isUsable },
    })
  ) {
    return ctx.result(`Can't use ${item.name}.`);
  }

  const outcome = useItem(ctx.board, player, itemIndex);
  for (const id of outcome.consumedCellIds) ctx.consumedCells.add(id);

  if (outcome.revealFloor) {
    const floor = ctx.board.floors[ctx.board.floor];
    for (let y = 0; y < floor.height; y++) {
      for (let x = 0; x < floor.width; x++) {
        if (floor.tiles[y][x] !== Tile.WALL) {
          ctx.exploredTiles.add(`${x},${y}`);
        }
      }
    }
  }

  ctx.board.turnNumber++;
  return ctx.commit(outcome.message);
}

// ── Open door ────────────────────────────────────────────────

function handleOpenDoor(
  deps: DispatcherDeps,
  direction: Direction,
): ActionResult {
  const { ctx, policy } = deps;
  ctx.assertPlaying();
  const player = ctx.board.player;
  const [dx, dy] = DIRECTION_OFFSETS[direction];
  const tx = player.position.x + dx;
  const ty = player.position.y + dy;

  if (!policy.evaluate({ action: 'open', targetX: tx, targetY: ty, board: ctx.board })) {
    const floor = ctx.board.floors[ctx.board.floor];
    const tile = floor.tiles[ty]?.[tx];
    if (tile === Tile.DOOR_LOCKED) {
      return ctx.result('The door is locked. You need the right key.');
    }
    return ctx.result('No door to open there.');
  }

  const outcome = openDoorAt(ctx.board, player, tx, ty);
  for (const id of outcome.consumedCellIds) ctx.consumedCells.add(id);

  ctx.board.turnNumber++;
  ctx.recomputeFov();
  return ctx.commit(outcome.message);
}

// ── Descend ──────────────────────────────────────────────────

function handleDescend(deps: DispatcherDeps): ActionResult {
  const { ctx } = deps;
  ctx.assertPlaying();
  const floor = ctx.board.floors[ctx.board.floor];
  const player = ctx.board.player;
  const tile = floor.tiles[player.position.y][player.position.x];

  if (tile !== Tile.STAIRS_DOWN) {
    return ctx.result('No stairs here to descend.');
  }

  const nextFloorIdx = ctx.board.floor + 1;
  if (nextFloorIdx >= MAX_FLOORS) {
    ctx.status = 'victory';
    return ctx.commit(
      'You have conquered all 5 floors of the dungeon! Victory!',
    );
  }

  if (!ctx.board.floors[nextFloorIdx]) {
    ctx.generateNextFloor(nextFloorIdx);
  }

  ctx.board.floor = nextFloorIdx;
  ctx.board.turnNumber++;

  ctx.visibleTiles.clear();
  ctx.exploredTiles.clear();
  ctx.recomputeFov();

  return ctx.commit(`You descend to floor ${nextFloorIdx + 1}.`);
}

// ── Helpers re-exported for facade ─────────────────────────────

export { posKey };

```
