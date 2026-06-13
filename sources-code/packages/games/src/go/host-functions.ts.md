---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/go/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.412906+00:00
---

# packages/games/src/go/host-functions.ts

```ts
/**
 * Go host functions -- registered with HostFunctionRegistry.
 *
 * Every predicate is zero-arity: it reads from the frozen evaluation context
 * set via registry.setContext() before WASM policy evaluation.
 *
 * Context shape:
 * {
 *   intersection: number,            // target intersection (0 to size*size-1)
 *   color: string,                   // "black"|"white"
 *   board: (object|null)[],          // size*size array of {color}|null
 *   koPoint: number|null,            // forbidden ko recapture point
 *   size: number,                    // board dimension (9|13|19)
 * }
 */

import type { HostFunctionRegistry, HostFunctionContext } from '@semantos/cell-engine';

// -- Context Accessors ----------------------------------------------------

type Ctx = HostFunctionContext;
type BoardSlot = { color: string } | null;

function intersection(ctx: Ctx): number { return ctx.intersection as number; }
function color(ctx: Ctx): string { return ctx.color as string; }
function board(ctx: Ctx): BoardSlot[] { return ctx.board as BoardSlot[]; }
function koPoint(ctx: Ctx): number | null { return ctx.koPoint as number | null; }
function size(ctx: Ctx): number { return ctx.size as number; }

// -- Board Geometry -------------------------------------------------------

/** Get adjacent intersection indices (up, down, left, right). */
export function getAdjacentIntersections(idx: number, boardSize: number): number[] {
  const row = Math.floor(idx / boardSize);
  const col = idx % boardSize;
  const adj: number[] = [];
  if (row > 0) adj.push((row - 1) * boardSize + col);           // up
  if (row < boardSize - 1) adj.push((row + 1) * boardSize + col); // down
  if (col > 0) adj.push(row * boardSize + (col - 1));           // left
  if (col < boardSize - 1) adj.push(row * boardSize + (col + 1)); // right
  return adj;
}

/** Get the connected group of stones of the same color starting from an intersection. */
export function getGroup(
  start: number,
  stoneColor: string,
  boardSlots: BoardSlot[],
  boardSize: number,
): Set<number> {
  const group = new Set<number>();
  const stack = [start];

  while (stack.length > 0) {
    const idx = stack.pop()!;
    if (group.has(idx)) continue;
    const slot = boardSlots[idx];
    if (!slot || slot.color !== stoneColor) continue;
    group.add(idx);
    for (const adj of getAdjacentIntersections(idx, boardSize)) {
      if (!group.has(adj)) {
        stack.push(adj);
      }
    }
  }

  return group;
}

/** Get the liberties (empty adjacent intersections) of a group. */
export function getLiberties(
  group: Set<number>,
  boardSlots: BoardSlot[],
  boardSize: number,
): Set<number> {
  const liberties = new Set<number>();
  for (const idx of group) {
    for (const adj of getAdjacentIntersections(idx, boardSize)) {
      if (boardSlots[adj] === null) {
        liberties.add(adj);
      }
    }
  }
  return liberties;
}

// -- Registration ---------------------------------------------------------

export function registerGoHostFunctions(registry: HostFunctionRegistry): void {
  // Is the target intersection empty?
  registry.register('intersection-empty?', (ctx) => {
    const b = board(ctx);
    const idx = intersection(ctx);
    return b[idx] === null ? 1 : 0;
  });

  // Would placing a stone here NOT be suicide?
  // A move is not suicide if:
  //   1. The placed stone's group has at least one liberty after placement, OR
  //   2. The placement captures at least one opponent group (removing those stones first)
  registry.register('not-suicide?', (ctx) => {
    const b = board(ctx);
    const idx = intersection(ctx);
    const c = color(ctx);
    const s = size(ctx);
    const opponent = c === 'black' ? 'white' : 'black';

    // Simulate placement
    const simBoard = [...b];
    simBoard[idx] = { color: c };

    // Check if any adjacent opponent group would be captured
    let capturesOpponent = false;
    for (const adj of getAdjacentIntersections(idx, s)) {
      const slot = simBoard[adj];
      if (slot && slot.color === opponent) {
        const group = getGroup(adj, opponent, simBoard, s);
        const libs = getLiberties(group, simBoard, s);
        if (libs.size === 0) {
          capturesOpponent = true;
          // Remove captured stones from simulation
          for (const stone of group) {
            simBoard[stone] = null;
          }
        }
      }
    }

    // Check our group's liberties after captures are resolved
    const ourGroup = getGroup(idx, c, simBoard, s);
    const ourLiberties = getLiberties(ourGroup, simBoard, s);

    return (ourLiberties.size > 0 || capturesOpponent) ? 1 : 0;
  });

  // Does this move NOT violate the ko rule?
  registry.register('not-ko-violation?', (ctx) => {
    const ko = koPoint(ctx);
    const idx = intersection(ctx);
    return (ko === null || idx !== ko) ? 1 : 0;
  });
}

```
