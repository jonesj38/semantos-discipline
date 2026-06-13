---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/event-emitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.527734+00:00
---

# packages/game-sdk/src/engine/event-emitter.ts

```ts
/**
 * Game-event-bus factory — `gameEventBus<E>()` returns a fresh
 * `EventBus<E>` per engine. Mirrors the prompt-19 `getGameEventBus`
 * shape but as a one-off factory rather than a per-game registry,
 * so each engine instance owns its own bus.
 */

import { eventBus, type EventBus } from '@semantos/state';

/** Fresh bus, typed to the consumer's event union. */
export function gameEventBus<E>(): EventBus<E> {
  return eventBus<E>();
}

```
