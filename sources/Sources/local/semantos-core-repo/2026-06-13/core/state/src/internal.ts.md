---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/internal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.012918+00:00
---

# core/state/src/internal.ts

```ts
export type Dispose = () => void;

export interface AtomInternal<T> {
  value: T;
  subscribers: Set<(next: T) => void>;
  computations: Set<Computation>;
}

export type Getter = <T>(atom: AtomInternal<T>) => T;

export type ComputationFn = (get: Getter) => void | (() => void);

let currentComputation: Computation | null = null;

export function getCurrentComputation(): Computation | null {
  return currentComputation;
}

export class Computation {
  private readonly deps = new Set<AtomInternal<unknown>>();
  private cleanup: (() => void) | null = null;
  private running = false;
  private disposed = false;

  constructor(private readonly fn: ComputationFn) {}

  run(): void {
    if (this.disposed) return;
    if (this.running) {
      throw new Error(
        "Cycle detected: a derived or effect depends on itself (directly or transitively).",
      );
    }
    this.running = true;

    if (this.cleanup) {
      const c = this.cleanup;
      this.cleanup = null;
      try {
        c();
      } catch (err) {
        this.running = false;
        throw err;
      }
    }

    for (const dep of this.deps) dep.computations.delete(this);
    this.deps.clear();

    const prev = currentComputation;
    currentComputation = this;
    try {
      const ret = this.fn(trackingGet);
      if (typeof ret === "function") this.cleanup = ret as () => void;
    } finally {
      currentComputation = prev;
      this.running = false;
    }
  }

  /** Called by an atom when its value changes. */
  notify(): void {
    if (this.disposed) return;
    this.run();
  }

  /** Register a dep discovered via {@link trackingGet}. */
  trackDep(dep: AtomInternal<unknown>): void {
    if (this.deps.has(dep)) return;
    this.deps.add(dep);
    dep.computations.add(this);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    if (this.cleanup) {
      const c = this.cleanup;
      this.cleanup = null;
      c();
    }
    for (const dep of this.deps) dep.computations.delete(this);
    this.deps.clear();
  }
}

function trackingGet<T>(atom: AtomInternal<T>): T {
  const comp = currentComputation;
  if (comp) comp.trackDep(atom as AtomInternal<unknown>);
  return atom.value;
}

export function notifyAtom<T>(atom: AtomInternal<T>, next: T): void {
  const comps = Array.from(atom.computations);
  for (const c of comps) c.notify();
  const subs = Array.from(atom.subscribers);
  for (const s of subs) s(next);
}

```
