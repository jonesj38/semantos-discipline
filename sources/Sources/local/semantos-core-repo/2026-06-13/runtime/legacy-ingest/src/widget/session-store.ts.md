---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/widget/session-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.165124+00:00
---

# runtime/legacy-ingest/src/widget/session-store.ts

```ts
/**
 * Widget session store — persists ConversationSessions across HTTP requests.
 *
 * Default: in-memory. Callers that need durability across restarts can
 * supply a custom store via the SessionPersistence port (e.g. a SQLite or
 * KV-backed implementation). The in-memory default is fine for development
 * and for single-process deployments where session loss on restart is
 * acceptable.
 */

import type { ConversationSession } from '../conversation/types';

export interface SessionPersistence {
  get(sessionId: string): Promise<ConversationSession | null>;
  set(session: ConversationSession): Promise<void>;
  delete(sessionId: string): Promise<void>;
}

/** In-memory session store. Thread-safe for single-process Bun deployments. */
export class MemorySessionStore implements SessionPersistence {
  private readonly map = new Map<string, ConversationSession>();

  async get(sessionId: string): Promise<ConversationSession | null> {
    return this.map.get(sessionId) ?? null;
  }

  async set(session: ConversationSession): Promise<void> {
    this.map.set(session.sessionId, session);
  }

  async delete(sessionId: string): Promise<void> {
    this.map.delete(sessionId);
  }

  get size(): number {
    return this.map.size;
  }
}

```
