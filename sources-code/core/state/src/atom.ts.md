---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/atom.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.014255+00:00
---

# core/state/src/atom.ts

```ts
import {
  type AtomInternal,
  type Dispose,
  notifyAtom,
} from "./internal.js";

export type Atom<T> = AtomInternal<T>;

export function atom<T>(initial: T): Atom<T> {
  return {
    value: initial,
    subscribers: new Set(),
    computations: new Set(),
  };
}

export function get<T>(a: Atom<T>): T {
  return a.value;
}

export function set<T>(a: Atom<T>, next: T): void {
  if (Object.is(a.value, next)) return;
  a.value = next;
  notifyAtom(a, next);
}

export function subscribe<T>(a: Atom<T>, fn: (value: T) => void): Dispose {
  a.subscribers.add(fn);
  return () => {
    a.subscribers.delete(fn);
  };
}

```
