---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/components.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.528936+00:00
---

# packages/game-sdk/src/ecs/components.ts

```ts
/**
 * ECS Components — bitECS component definitions for the game-sdk.
 *
 * Design:
 *   - bitECS components are plain typed-array objects (SoA). Each property is
 *     a typed array indexed by entity ID (eid). This gives us cache-friendly
 *     iteration in the tier-1 "hot loop" working set.
 *
 *   - Non-numeric data (cell IDs, metadata blobs, the authoritative GameEntity
 *     itself) lives in sidecar Maps on the game world, keyed by eid. See
 *     world.ts for those.
 *
 *   - `CellBacked` is the bridge: every entity that has a corresponding cell
 *     in the tier-2 authority layer carries this tag. Systems that want to
 *     "promote" an entity back to a cell mark it with `Dirty`.
 *
 *   - `TradeIntent` is an example "command component" — a system emits it in
 *     the hot loop, then the trade-system detects it at tier-boundary time and
 *     delegates to `GameCellEngine.executeTrade`.
 *
 * Capacity:
 *   - The constant `DEFAULT_CAPACITY` is the max number of entities that can
 *     exist simultaneously in a single world. Typed arrays are pre-allocated
 *     at this size. Bump it for larger games at the cost of memory.
 */

/** Default maximum entity count per world (tune per game). */
export const DEFAULT_CAPACITY = 10_000;

// ── Bridge component ───────────────────────────────────────────────────────

/**
 * Marker for entities backed by a tier-2 cell. Carries a 32-bit handle into
 * the world's `entityById` sidecar Map (see world.ts), not the cell ID itself
 * — bitECS wants numeric fields only.
 *
 * The handle is a monotonically increasing counter assigned by the world
 * factory. `handle === 0` means "not yet assigned".
 */
export const CellBacked = {
  /** Sidecar handle into world.entityById (not a cell hash). */
  handle: new Uint32Array(DEFAULT_CAPACITY),
  /** Entity classification (mirrors GameEntityType). */
  entityType: new Uint8Array(DEFAULT_CAPACITY),
  /** Linearity class (1=LINEAR, 2=AFFINE, 3=RELEVANT, 4=DEBUG, 5=FUNGIBLE). */
  linearity: new Uint8Array(DEFAULT_CAPACITY),
  /** Cell timestamp (ms since epoch), truncated to u32. */
  timestamp: new Uint32Array(DEFAULT_CAPACITY),
};

/**
 * Tag component: entity has changed in the tier-1 working set and needs
 * promotion back to its cell at the next `syncToCell()` boundary. Systems in
 * the hot loop set this whenever they mutate gameplay state.
 *
 * Empty component (no data fields) — bitECS still tracks it for queries.
 */
export const Dirty = {};

// ── Hot gameplay components ────────────────────────────────────────────────

/** World-space position. Typical per-frame read by render/physics systems. */
export const Position = {
  x: new Float32Array(DEFAULT_CAPACITY),
  y: new Float32Array(DEFAULT_CAPACITY),
  z: new Float32Array(DEFAULT_CAPACITY),
};

/** Linear velocity. */
export const Velocity = {
  dx: new Float32Array(DEFAULT_CAPACITY),
  dy: new Float32Array(DEFAULT_CAPACITY),
  dz: new Float32Array(DEFAULT_CAPACITY),
};

/** Health / hitpoints. */
export const Health = {
  current: new Uint16Array(DEFAULT_CAPACITY),
  max: new Uint16Array(DEFAULT_CAPACITY),
};

/** Owner of this entity, encoded as the first 4 bytes of the 16-byte ownerId
 * hashed into a u32. The authoritative full ownerId lives on the GameEntity
 * in `world.entityById`. This is a cheap comparison key for queries like
 * "all entities owned by party A". */
export const Owner = {
  shortId: new Uint32Array(DEFAULT_CAPACITY),
};

/** Current state label encoded as a u16 hash. Maps to `entity.state` in
 * tier-2; the full string lives on the GameEntity. Systems that care only
 * about "is this entity in state X" can query on the hash directly. */
export const StateTag = {
  hash: new Uint16Array(DEFAULT_CAPACITY),
};

// ── Command components ─────────────────────────────────────────────────────

/**
 * Trade intent emitted in the hot loop by game logic. The trade-system
 * consumes these at tier-boundary time, validates the slots, and delegates to
 * `GameCellEngine.executeTrade`.
 *
 * Both parties are referenced by bitECS eid. The offered slot lists live in
 * the `tradeOffers` sidecar Map on the world (string arrays are not SoA-
 * friendly). A u32 `offerKey` links the component to that sidecar entry.
 */
export const TradeIntent = {
  partyA: new Uint32Array(DEFAULT_CAPACITY),
  partyB: new Uint32Array(DEFAULT_CAPACITY),
  offerKey: new Uint32Array(DEFAULT_CAPACITY),
  /** 0 = pending, 1 = accepted, 2 = rejected (filled in by trade-system). */
  status: new Uint8Array(DEFAULT_CAPACITY),
};

// ── State-tag hashing helper ───────────────────────────────────────────────

/**
 * Hash a state string into a u16 for cheap queries. This is a 16-bit FNV-1a
 * variant — collisions are possible but the authoritative state string lives
 * on the tier-2 GameEntity, so the hash is only an index, not a source of
 * truth.
 */
export function hashStateTag(name: string): number {
  let h = 0x811c; // 16-bit FNV offset
  for (let i = 0; i < name.length; i++) {
    h ^= name.charCodeAt(i);
    h = (h * 0x0101) & 0xffff;
  }
  return h;
}

/** Truncate a 16-byte ownerId to its first 4 bytes as a u32 for Owner.shortId. */
export function shortOwnerId(ownerId: Uint8Array): number {
  if (ownerId.length < 4) return 0;
  return (
    (ownerId[0] << 24) |
    (ownerId[1] << 16) |
    (ownerId[2] << 8) |
    ownerId[3]
  ) >>> 0;
}

```
