---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/ecs/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.528369+00:00
---

# game-sdk ECS

bitECS integration for the Semantos game-sdk.

## Why two tiers

The cell-engine is the authority. Every game object is a 1024-byte cell with
a hash-chained header, enforced linearity, and a policy script. That's great
for correctness and auditability. It's terrible for a 60fps game loop, where
you want to iterate over a thousand moving entities without allocating a
single object.

bitECS is the hot-loop working set. Components are cache-friendly SoA typed
arrays indexed by entity ID. Queries are bitmask intersections over archetype
tables. You get O(1) component access, zero allocations per frame, and
`query()` calls that run in microseconds.

The game-sdk uses both. bitECS owns per-frame gameplay state. The cell-engine
owns authoritative state that must survive restarts, trade atomically, or
prove its history. The bridge is the only place they touch.

```
 hot loop                              tier boundary                durable
 ┌──────────────┐                                                ┌───────────┐
 │  bitECS      │  syncFromCell (spawn)                          │ cell      │
 │  Position    │ ◀──────────────────────────────────────────    │ storage   │
 │  Velocity    │                                                │ +         │
 │  Health      │  syncToCell (promote dirty)                    │ engine    │
 │  TradeIntent │ ────────────────────────────────────────────▶  │           │
 └──────────────┘                                                └───────────┘
```

## File layout

```
ecs/
├── components.ts       # bitECS component schemas + CellBacked bridge tag
├── world.ts            # createGameWorld + sidecar tables + dirty queue
├── bridge.ts           # syncFromCell / syncToCell
├── systems/
│   └── trade-system.ts # worked example: tier-crossing system
├── index.ts            # barrel
└── README.md           # this file
```

## Core concepts

### CellBacked is the bridge tag

Any bitECS entity that has a corresponding tier-2 cell carries the
`CellBacked` component. It stores:

- `handle` — a u32 index into `world.entityById`, where the authoritative
  `GameEntity` (cell + decoded view) lives.
- `entityType` — mirrors `GameEntityType`.
- `linearity` — mirrors `LINEARITY.*`.
- `timestamp` — cell header timestamp, truncated to u32.

The cell ID is a 32-byte hex string; bitECS wants numeric fields, so the
handle is a sidecar indirection. The authoritative `GameEntity` (cell bytes,
metadata, full timestamp) lives in `world.entityById: Map<handle, GameEntity>`.

### Dirty tag + dirty queue

When a hot-loop system mutates state that needs tier-2 promotion, it:

1. Adds the `Dirty` component to the entity (queryable by other systems).
2. Calls `markDirty(world, eid)` (fast-path enumerator for sync time).

The bridge's `syncToCell` drains the queue, calls `engine.updateEntity` for
each entity, and clears the `Dirty` tag on success.

### Sidecar tables

bitECS components are SoA numeric arrays. For state that doesn't fit that
model — the full `GameEntity` object, trade-offer slot lists — the world
carries sidecar Maps keyed by a u32 handle or key. The component stores the
handle; the sidecar stores the real data.

This is a common pattern for bitECS integrations with existing object graphs.
See `world.ts` for the handle/offer-key allocators.

## End-to-end walkthrough

Spawn a world:

```ts
import { GameCellEngine } from '@semantos/game-sdk';
import {
  createGameWorld,
  syncFromCell,
  syncToCell,
  Position,
  Velocity,
  Dirty,
  markDirty,
} from '@semantos/game-sdk/ecs';
import { addComponent } from 'bitecs';

const engine = await GameCellEngine.create();
const world = createGameWorld();
```

Create an entity in tier-2 and promote it into tier-1:

```ts
const sword = engine.createEntity({
  entityType: GameEntityType.ITEM,
  ownerId: playerId,
  linearity: LINEARITY.LINEAR,
  metadata: {
    name: 'Rusty Sword',
    position: { x: 10, y: 0, z: 5 },
    velocity: { dx: 0, dy: 0, dz: 0 },
  },
});

const eid = syncFromCell(world, sword);
```

Run a physics step in the hot loop — no cells touched:

```ts
function physicsSystem(world: GameWorld, dt: number) {
  const moving = query(world.ecs, [Position, Velocity]);
  for (const eid of moving) {
    Position.x[eid] += Velocity.dx[eid] * dt;
    Position.y[eid] += Velocity.dy[eid] * dt;
    Position.z[eid] += Velocity.dz[eid] * dt;
    if (hasMoved(eid)) {
      addComponent(world.ecs, eid, Dirty);
      markDirty(world, eid);
    }
  }
}
```

Periodically promote dirty entities back to tier-2:

```ts
// Every few seconds, or on save, or before a trade — not every frame.
const { promoted, failed } = syncToCell(world, engine);
```

## Tier-crossing system: trade

`systems/trade-system.ts` is the canonical example. The shape:

1. **Hot query**: `query(world.ecs, [TradeIntent])` — bitECS archetype scan.
2. **Cheap validation**: both parties must be `CellBacked`, both sidecar
   lookups must succeed, the offer-key must resolve.
3. **Tier crossing**: build a `TradeProposal`, call `engine.executeTrade`.
   The engine enforces linearity, rewrites ownerIds, and persists the swap.
4. **Writeback**: mark both parties dirty so the next `syncToCell` pass
   picks up any cell-level metadata changes (the trade itself is already
   committed to storage by `executeTrade`).
5. **Status**: set `TradeIntent.status` to `TRADE_ACCEPTED` or
   `TRADE_REJECTED` so UI systems can observe.

The system is ~80 lines and does no cell manipulation directly. It's an
adapter, not a reimplementation.

## What bitECS adds that cell-ops alone doesn't

- **Queries are archetype bitmasks**, not Map iterations. "Every entity with
  Position and Velocity but not Frozen" is a single bit operation over a
  couple of bitmasks, regardless of how many components exist.
- **Typed-array layout** means physics and render loops are
  cache-friendly. Your inner loop fits in L1.
- **Deterministic eids** (monotonic u32s) play nicely with networked
  rollback/lockstep systems without needing string hashing.
- **Observables** (`observe`) let you hook component add/remove for cheap
  derived state — e.g. rebuilding a spatial index only when Position
  changes.
- **Serialization** works out of the box for send-over-the-wire snapshots
  that skip the expensive tier-2 cell encoding.

What you don't get from bitECS: linearity, durability, audit trails,
verifiable trades, policy enforcement. Those live in tier-2, and that's
where they belong.

## Capacity tuning

`DEFAULT_CAPACITY = 10_000` is baked into the typed-array sizes in
`components.ts`. If your game needs more than 10k simultaneous entities,
bump it — the cost is ~10 bytes per component per extra entity slot, so
each +10k adds roughly 100 KB of RAM across the default component set.

For huge worlds, consider partitioning into multiple bitECS worlds (one per
zone) and only promoting to tier-2 when an entity crosses zones or is
persisted to storage.
