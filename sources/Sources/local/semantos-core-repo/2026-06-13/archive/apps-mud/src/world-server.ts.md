---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.836220+00:00
---

# archive/apps-mud/src/world-server.ts

```ts
/**
 * @deprecated — moved under `apps/mud/src/world-server/`.
 *
 * Refactor 24 split the 633-LOC monolith into per-concern modules:
 *   - `world-server/world-generator.ts`     — pure room/monster/item layout
 *   - `world-server/room-actor-pool.ts`     — RoomActor registry
 *   - `world-server/player-session-store.ts`— session + room-binding maps
 *   - `world-server/cross-room-transfer.ts` — atomic exit/entry between actors
 *   - `world-server/event-bus-bridge.ts`    — per-player event routing
 *   - `world-server/player-join-flow.ts`    — entity creation + bind
 *   - `world-server/world-boot-flow.ts`     — generate + register + start
 *   - `world-server/world-persistence.ts`   — config + topology + session cells
 *   - `world-server/world-server-facade.ts` — public `WorldServer`
 *
 * This file remains as a re-export shim so existing imports
 * (`@semantos/mud/world-server`, `apps/mud/src/world-server.ts`) keep
 * working byte-identical. New code should import from
 * `@semantos/mud` (which re-exports `WorldServer`) directly.
 */

export { WorldServer } from './world-server/world-server-facade';

```
