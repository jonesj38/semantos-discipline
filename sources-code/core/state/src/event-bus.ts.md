---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/event-bus.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.013455+00:00
---

# core/state/src/event-bus.ts

```ts
import type { Dispose } from "./internal.js";

export interface EventBus<E> {
  emit(event: E): void;
  on(fn: (event: E) => void): Dispose;
  once(fn: (event: E) => void): Dispose;
}

export function eventBus<E>(): EventBus<E> {
  const listeners = new Set<(event: E) => void>();
  return {
    emit(event) {
      for (const fn of Array.from(listeners)) fn(event);
    },
    on(fn) {
      listeners.add(fn);
      return () => {
        listeners.delete(fn);
      };
    },
    once(fn) {
      const wrapped = (event: E): void => {
        listeners.delete(wrapped);
        fn(event);
      };
      listeners.add(wrapped);
      return () => {
        listeners.delete(wrapped);
      };
    },
  };
}

```
