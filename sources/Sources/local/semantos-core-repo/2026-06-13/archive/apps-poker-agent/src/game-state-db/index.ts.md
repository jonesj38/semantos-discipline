---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.771536+00:00
---

# archive/apps-poker-agent/src/game-state-db/index.ts

```ts
/**
 * Game-state-db barrel — public surface for the prompt-21 split.
 */

export { GameStateDB } from './game-state-db-facade';

export {
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
} from './types';

export { SCHEMA_SQL, SCHEMA_VERSION, applySchema } from './schema';

export {
  mapActionRow,
  mapAgentMemoryRow,
  mapCellTokenRefRow,
  mapHandRow,
  mapPlayerRow,
  mapSessionRow,
  mapStateSnapshotRow,
  parseCommunityCards,
} from './row-mappers';

export { makeSeqCounter, type SeqCounter } from './seq-counter';

export {
  SessionStore,
  type PlayerInsert,
  type SessionConfig,
} from './session-store';

export { HandStore } from './hand-store';

export {
  ActionStore,
  type ActionInsert,
} from './action-store';

export {
  SnapshotStore,
  type SnapshotInsert,
} from './snapshot-store';

export {
  CellTokenRefStore,
  type CellTokenRefInsert,
} from './celltoken-ref-store';

export { MemoryStore } from './memory-store';

export { ContextBuilder } from './context-builder';

```
