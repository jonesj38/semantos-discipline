---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.012372+00:00
---

# core/state/src/index.ts

```ts
export { atom, get, set, subscribe, type Atom } from "./atom.js";
export { derived } from "./derived.js";
export { effect } from "./effect.js";
export { port, PortUnboundError, type Port } from "./port.js";
export {
  registry,
  RegistryMissingKeyError,
  type Registry,
} from "./registry.js";
export {
  makeRegistry,
  RegistryConfigError,
  type PersistentRegistry,
  type PersistencePolicy,
  type PersistEvent,
  type MakeRegistryOptions,
} from "./persistent-registry.js";
export { eventBus, type EventBus } from "./event-bus.js";
export { slice, type Slice, type SliceDef } from "./slice.js";
export type { Dispose, Getter } from "./internal.js";

```
