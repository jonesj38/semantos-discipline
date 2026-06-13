---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/derived.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.012102+00:00
---

# core/state/src/derived.ts

```ts
import { atom, type Atom, set } from "./atom.js";
import { Computation, type Getter } from "./internal.js";

export function derived<T>(fn: (get: Getter) => T): Atom<T> {
  let placeholder!: T;
  const out: Atom<T> = atom<T>(placeholder);
  const comp = new Computation((get) => {
    const next = fn(get);
    set(out, next);
  });
  comp.run();
  return out;
}

```
