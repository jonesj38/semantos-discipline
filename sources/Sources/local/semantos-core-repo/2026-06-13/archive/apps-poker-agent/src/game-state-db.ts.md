---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.761206+00:00
---

# archive/apps-poker-agent/src/game-state-db.ts

```ts
/**
 * @deprecated — use the split modules under
 * `apps/poker-agent/src/game-state-db/` instead.
 *
 * This file is the legacy single-file SQLite wrapper. Prompt 21
 * split it into per-table stores + a thin facade:
 *
 *   - `schema.ts`               — SCHEMA_SQL, applySchema, SCHEMA_VERSION
 *   - `row-mappers.ts`          — pure mappers exported standalone
 *   - `seq-counter.ts`          — shared monotonic seq across actions
 *                                  / snapshots / celltoken_refs
 *   - `session-store.ts`        — game_sessions + players
 *   - `hand-store.ts`           — hands lifecycle
 *   - `action-store.ts`         — actions + getActionsSince
 *   - `snapshot-store.ts`       — state_snapshots + getSnapshotsSince
 *   - `celltoken-ref-store.ts`  — celltoken_refs + getCellTokens
 *   - `memory-store.ts`         — agent_memory KV
 *   - `context-builder.ts`      — getCurrentHandContext, getGameHistory
 *   - `game-state-db-facade.ts` — thin GameStateDB class
 *
 * Migration target imports:
 *
 *   import { GameStateDB } from './game-state-db/';
 */

export {
  GameStateDB,
  type ActionRow,
  type ActionSummary,
  type AgentMemoryRow,
  type CellTokenRefRow,
  type GameHistory,
  type GameSessionRow,
  type HandContext,
  type HandRow,
  type HandSummary,
  type PlayerRow,
  type StateSnapshotRow,
} from './game-state-db/index';

```
