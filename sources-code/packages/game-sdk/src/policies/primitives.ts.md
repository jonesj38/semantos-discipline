---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/policies/primitives.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.530151+00:00
---

# packages/game-sdk/src/policies/primitives.ts

```ts
/**
 * Game-domain constraint primitives.
 *
 * These define the vocabulary of game-specific constraints that can
 * be used in policy expressions. Each primitive maps to a host function
 * call that the cell engine dispatches via OP_LOADFIELD.
 *
 * At runtime, the cell engine calls back to the host (game engine)
 * to evaluate these predicates against actual game state.
 *
 * This file documents the primitives — their names, semantics, and
 * expected host function signatures. The actual host implementations
 * live in the game engine bindings (Godot/Unity).
 */

// ── Primitive Registry ──────────────────────────────────────────

export interface GamePrimitive {
  /** Name as used in Lisp policy expressions (e.g. "square-empty?") */
  name: string;
  /** Human-readable description */
  description: string;
  /** Expected parameter types */
  params: Array<{ name: string; type: 'number' | 'string' | 'boolean' }>;
  /** Return type */
  returns: 'boolean' | 'number';
  /** Category for documentation grouping */
  category: 'board' | 'entity' | 'inventory' | 'temporal';
}

// ── Board / Spatial Primitives ──────────────────────────────────

export const BOARD_PRIMITIVES: GamePrimitive[] = [
  {
    name: 'square-empty?',
    description: 'Returns true if the board square at (row, col) is unoccupied',
    params: [
      { name: 'row', type: 'number' },
      { name: 'col', type: 'number' },
    ],
    returns: 'boolean',
    category: 'board',
  },
  {
    name: 'path-clear?',
    description: 'Returns true if all squares between (r1,c1) and (r2,c2) are unoccupied',
    params: [
      { name: 'fromRow', type: 'number' },
      { name: 'fromCol', type: 'number' },
      { name: 'toRow', type: 'number' },
      { name: 'toCol', type: 'number' },
    ],
    returns: 'boolean',
    category: 'board',
  },
  {
    name: 'adjacent?',
    description: 'Returns true if two board positions are adjacent (including diagonals)',
    params: [
      { name: 'r1', type: 'number' },
      { name: 'c1', type: 'number' },
      { name: 'r2', type: 'number' },
      { name: 'c2', type: 'number' },
    ],
    returns: 'boolean',
    category: 'board',
  },
];

// ── Entity Primitives ───────────────────────────────────────────

export const ENTITY_PRIMITIVES: GamePrimitive[] = [
  {
    name: 'has-tag?',
    description: 'Returns true if the entity has the given metadata tag',
    params: [{ name: 'tag', type: 'string' }],
    returns: 'boolean',
    category: 'entity',
  },
  {
    name: 'rarity-eq?',
    description: 'Returns true if the entity rarity matches the given value',
    params: [{ name: 'rarity', type: 'string' }],
    returns: 'boolean',
    category: 'entity',
  },
  {
    name: 'level-gte?',
    description: 'Returns true if the entity level is >= the given threshold',
    params: [{ name: 'minLevel', type: 'number' }],
    returns: 'boolean',
    category: 'entity',
  },
];

// ── Inventory Primitives ────────────────────────────────────────

export const INVENTORY_PRIMITIVES: GamePrimitive[] = [
  {
    name: 'inventory-full?',
    description: 'Returns true if the inventory has no empty slots',
    params: [{ name: 'maxSlots', type: 'number' }],
    returns: 'boolean',
    category: 'inventory',
  },
  {
    name: 'inventory-contains?',
    description: 'Returns true if the inventory contains an entity of the given type',
    params: [{ name: 'entityType', type: 'number' }],
    returns: 'boolean',
    category: 'inventory',
  },
];

// ── All Primitives ──────────────────────────────────────────────

export const ALL_PRIMITIVES: GamePrimitive[] = [
  ...BOARD_PRIMITIVES,
  ...ENTITY_PRIMITIVES,
  ...INVENTORY_PRIMITIVES,
];

```
