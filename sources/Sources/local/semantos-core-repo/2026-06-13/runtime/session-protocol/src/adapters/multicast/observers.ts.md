---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/observers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.068752+00:00
---

# runtime/session-protocol/src/adapters/multicast/observers.ts

```ts
/**
 * observers — small, isolated callback registries for the four
 * observer hooks the legacy `MulticastAdapter` exposed alongside the
 * `NetworkAdapter` interface:
 *
 *   - `onPeerOffline`       — peer evicted from the registry
 *   - `onAnyCell`           — every received MSG_CELL, regardless of topic
 *   - `onControlMessage`    — every MSG_CONTROL
 *   - `onDuplicatePath`     — path collision between two owners
 *
 * Each observer is independently `register/fire/clear`-able. Errors
 * raised inside a callback are isolated so one bad subscriber cannot
 * stall fan-out — matching legacy semantics in the original adapter.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — original observer plumbing
 */

export interface ObserverList<T> {
  add(cb: (value: T) => void): () => void;
  fire(value: T): void;
  size(): number;
  clear(): void;
}

export function createObserverList<T>(): ObserverList<T> {
  const cbs: Array<(value: T) => void> = [];
  return {
    add(cb): () => void {
      cbs.push(cb);
      return () => {
        const idx = cbs.indexOf(cb);
        if (idx >= 0) cbs.splice(idx, 1);
      };
    },
    fire(value: T): void {
      for (const cb of cbs) {
        try {
          cb(value);
        } catch {
          /* isolate observer errors — one bad cb must not stall fan-out */
        }
      }
    },
    size(): number {
      return cbs.length;
    },
    clear(): void {
      cbs.length = 0;
    },
  };
}

```
