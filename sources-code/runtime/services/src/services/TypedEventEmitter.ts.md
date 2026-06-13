---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/TypedEventEmitter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.092400+00:00
---

# runtime/services/src/services/TypedEventEmitter.ts

```ts
/**
 * Minimal typed event emitter — browser-safe, no Node.js dependencies.
 * Foundation for all stores (LoomStore, IdentityStore, ConfigStore, etc.).
 */

type EventMap = Record<string, unknown[]>;
type Handler<Args extends unknown[]> = (...args: Args) => void;

export class TypedEventEmitter<Events extends EventMap> {
  private listeners = new Map<keyof Events, Set<Handler<any>>>();

  on<K extends keyof Events>(event: K, handler: Handler<Events[K]>): () => void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(handler);
    return () => this.off(event, handler);
  }

  off<K extends keyof Events>(event: K, handler: Handler<Events[K]>): void {
    this.listeners.get(event)?.delete(handler);
  }

  protected emit<K extends keyof Events>(event: K, ...args: Events[K]): void {
    const set = this.listeners.get(event);
    if (set) {
      for (const handler of set) {
        handler(...args);
      }
    }
  }
}

```
