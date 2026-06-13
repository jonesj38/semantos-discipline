---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.809100+00:00
---

# @semantos/state

Shared atomic-state primitives used across the semantos-core monolith decomposition.

Zero runtime dependencies, TypeScript strict, ESM only. Synchronous reads and writes — no Promises inside the primitives. Everything below is importable from the package root:

```ts
import {
  atom, get, set, subscribe,
  derived,
  effect,
  port,
  registry,
  eventBus,
  slice,
} from "@semantos/state";
```

## Primitives at a glance

| Primitive | Purpose |
|-----------|---------|
| `atom` | Reactive cell holding a single value. |
| `derived` | Read-only atom computed from other atoms, memoized, re-fires when deps change. |
| `effect` | Side-effectful computation that re-runs on dep change, with optional teardown. |
| `port` | Bindable dependency slot — errors clearly when used before boot. |
| `registry` | Keyed handler table with required-key lookup. |
| `eventBus` | Fire-and-forget pub/sub — no history, no replay. |
| `slice` | Sugar over `atom`: pairs a reducer with a state atom and a `dispatch`. |

## Examples

### `atom`
```ts
import { atom, get, set, subscribe } from "@semantos/state";

const count = atom(0);
const dispose = subscribe(count, (v) => console.log("count →", v));
set(count, 1);          // logs: count → 1
set(count, 1);          // no-op: Object.is equality
console.log(get(count)); // 1
dispose();
```

### `derived`
```ts
import { atom, derived, get, set } from "@semantos/state";

const price = atom(10);
const qty = atom(3);
const total = derived((read) => read(price) * read(qty));

console.log(get(total)); // 30
set(qty, 5);
console.log(get(total)); // 50
```

### `effect`
```ts
import { atom, effect, set } from "@semantos/state";

const url = atom("/api/v1/status");
const dispose = effect((read) => {
  const controller = new AbortController();
  fetch(read(url), { signal: controller.signal }).catch(() => {});
  return () => controller.abort(); // teardown before next run or on dispose
});

set(url, "/api/v2/status"); // aborts previous fetch, starts a new one
dispose();                  // aborts and stops re-running
```

### `port`
```ts
import { port, PortUnboundError } from "@semantos/state";

interface Clock { now(): number }

export const clockPort = port<Clock>("Clock");

// app boot:
clockPort.bind({ now: () => Date.now() });

// anywhere else:
const t = clockPort.get().now();

// tests:
clockPort.unbind();
try { clockPort.get(); } catch (e) {
  // e instanceof PortUnboundError — message tells you to call bind() at boot
}
```

### `slice`
```ts
import { get, slice, subscribe } from "@semantos/state";

type Action = { type: "inc" } | { type: "dec" } | { type: "set"; value: number };
const counter = slice<number, Action>({
  initial: 0,
  reducer: (state, a) => {
    switch (a.type) {
      case "inc": return state + 1;
      case "dec": return state - 1;
      case "set": return a.value;
    }
  },
});

subscribe(counter.stateAtom, (v) => console.log("state →", v));
counter.dispatch({ type: "inc" });
counter.dispatch({ type: "set", value: 10 });
console.log(get(counter.stateAtom)); // 10
```

## Design notes

- **Synchronous.** `set` triggers subscribers and re-runs dependent computations inline. No microtask batching.
- **Dynamic dep tracking.** `derived` and `effect` track only atoms read during the latest run — branches that don't execute don't subscribe.
- **Cycle detection.** A `derived`/`effect` that transitively writes one of its own deps throws `Cycle detected …` rather than recursing.
- **Eager derives.** A `derived` subscribes to its deps at construction. If nothing downstream consumes it, upstream atoms still retain it — hold a reference only as long as you need it.
- **Port ergonomics.** `port.get()` throws `PortUnboundError` with the port name and a hint to call `bind()` at app boot. `unbind()` is for tests.
- **Registry ergonomics.** `registry.require(key)` throws `RegistryMissingKeyError` listing known keys. `registry.get(key)` returns `undefined` for unknown keys.
