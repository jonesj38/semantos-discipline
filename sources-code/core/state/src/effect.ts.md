---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/effect.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.013189+00:00
---

# core/state/src/effect.ts

```ts
import {
  Computation,
  type ComputationFn,
  type Dispose,
} from "./internal.js";

/**
 * Run `fn` immediately, re-running it whenever any atom it `track`s
 * changes. Returns a `Dispose` to tear down the subscription.
 *
 * **Self-reentry constraint:** `fn` cannot `set` an atom it also
 * `get`s through the tracking getter — that would re-enter the same
 * `Computation` while it's still running, which throws "Cycle
 * detected". If you need to read state and write derived state on
 * change, use `subscribe(atom, fn)` from `./atom.js` instead — it
 * fires after the value has changed and does not track its own deps.
 *
 *   // OK — no writes inside the effect
 *   effect((get) => doSomething(get(atomA)));
 *
 *   // THROWS — set() re-enters the running computation
 *   effect((get) => set(atomA, get(atomA) + 1));
 *
 *   // Workaround — subscribe() doesn't track and is safe to set in
 *   subscribe(atomA, (next) => set(atomB, derive(next)));
 *
 * Worked-around examples in the codebase:
 *   apps/mud/src/room-actor/room-state-persister.ts (prompt 23) —
 *     uses a tick atom + side queue to lift writes out of the
 *     tracked computation.
 *   apps/mud/src/world-server/event-bus-bridge.ts (prompt 24) —
 *     uses subscribe callbacks throughout instead of effect.
 */
export function effect(fn: ComputationFn): Dispose {
  const comp = new Computation(fn);
  comp.run();
  return () => comp.dispose();
}

```
