---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/game-state-db/memory-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.773770+00:00
---

# archive/apps-poker-agent/src/game-state-db/memory-store.ts

```ts
/**
 * Per-agent KV memory store — owns `agent_memory`.
 *
 * This is the agent's scratchpad: opaque strings keyed by
 * (agentName, key) so reasoning state can persist across hands
 * without polluting the actions/snapshots tables.
 */

import type { DatabaseHandle } from './db-types';

export class MemoryStore {
  constructor(private readonly db: DatabaseHandle) {}

  setMemory(agentName: string, key: string, value: string): void {
    const now = Date.now();
    this.db
      .prepare(
        `INSERT INTO agent_memory (agent_name, key, value, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(agent_name, key) DO UPDATE SET value = ?, updated_at = ?`,
      )
      .run(agentName, key, value, now, value, now);
  }

  getMemory(agentName: string, key: string): string | null {
    const row = this.db
      .prepare('SELECT value FROM agent_memory WHERE agent_name = ? AND key = ?')
      .get(agentName, key) as { value: string } | null;
    return row?.value ?? null;
  }

  getAllMemory(agentName: string): Record<string, string> {
    const rows = this.db
      .prepare('SELECT key, value FROM agent_memory WHERE agent_name = ?')
      .all(agentName) as { key: string; value: string }[];
    return Object.fromEntries(rows.map((r) => [r.key, r.value]));
  }
}

```
