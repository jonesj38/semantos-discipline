---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/slice.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.014516+00:00
---

# core/state/src/slice.ts

```ts
import { atom, type Atom, set } from "./atom.js";

export interface SliceDef<S, A> {
  reducer: (state: S, action: A) => S;
  initial: S;
}

export interface Slice<S, A> {
  stateAtom: Atom<S>;
  dispatch(action: A): void;
}

export function slice<S, A>(def: SliceDef<S, A>): Slice<S, A> {
  const stateAtom = atom<S>(def.initial);
  return {
    stateAtom,
    dispatch(action) {
      const next = def.reducer(stateAtom.value, action);
      set(stateAtom, next);
    },
  };
}

```
