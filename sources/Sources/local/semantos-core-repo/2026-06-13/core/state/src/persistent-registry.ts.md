---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/persistent-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.012642+00:00
---

# core/state/src/persistent-registry.ts

```ts
/**
 * `makeRegistry<K, V>` — atom-backed key/value registry with a declared
 * persistence policy.
 *
 * This is **distinct** from `registry<H>()` in `./registry.ts`:
 *   - `registry<H>()` is a strategy registry (string keys → handler fn). It
 *     has no notion of persistence — handlers are app-boot wiring.
 *   - `makeRegistry<K, V>(opts)` is a **value** registry. It can be mutated
 *     at runtime, exposes a subscribable atom, and lets the caller declare
 *     up-front whether mutations should propagate to durable storage
 *     (Plexus recovery, IDB snapshot, on-chain anchor, or stay
 *     session-only).
 *
 * Why both: the strategy registry is the right shape for `capabilityLookup`,
 * `keyClassRouting`, etc. — small, fixed, registered once. The value
 * registry is the right shape for `messageQueue`, `turnAtom`, app-state
 * cluster — frequently mutated, observable, possibly recoverable.
 *
 * The persistence-policy axis is what makes the Plexus integration cheap:
 * change `'session'` → `'plexus-recovered'` and a runtime registry
 * automatically enrolls in the Plexus recovery substrate without
 * downstream code changes.
 *
 * ── policy semantics ──────────────────────────────────────────────────────
 *
 * - 'session'         : in-memory only. Survives nothing. Tests, transient
 *                       state, anything you'd happily lose.
 * - 'snapshot'        : `persist()` is called on every set. Caller-supplied
 *                       writer (IDB/file/etc.). No recovery substrate
 *                       awareness — purely local.
 * - 'plexus-recovered': `persist()` is called on every set with the value
 *                       AND a recovery enrollment hint. Apps wire
 *                       `persist` to call `recoveryPort.enrollContext` so
 *                       a subsequent disaster recovery rehydrates this
 *                       registry's contents.
 * - 'chain'           : reserved. `persist()` is required and is expected
 *                       to anchor the value via an on-chain BRC-52/BRC-108
 *                       transaction. Implementing this requires a wallet
 *                       binding and is out of scope for the foundations PR
 *                       — set `persist` and the registry will call it; it
 *                       does NOT itself broadcast or sign anything.
 *
 * ── lifecycle ────────────────────────────────────────────────────────────
 *
 *   const reg = makeRegistry<string, Move>({
 *     name: 'pokerMoveQueue',
 *     persistencePolicy: 'session',
 *   });
 *
 *   reg.set('hand-1', m);       // updates atom; subscribers fire
 *   reg.get('hand-1');          // → m
 *   reg.subscribe(snap => ...); // observes the whole map
 *   reg.delete('hand-1');
 *
 * For 'snapshot' / 'plexus-recovered' / 'chain' policies, supply `persist`:
 *
 *   makeRegistry<...>({
 *     name: '...',
 *     persistencePolicy: 'plexus-recovered',
 *     persist: ({ key, value, kind }) => recoveryPort.get().enrollContext({...}),
 *   });
 */

import { atom, get, set, subscribe, type Atom } from './atom.js';

export type PersistencePolicy = 'session' | 'snapshot' | 'plexus-recovered' | 'chain';

export interface PersistEvent<K, V> {
  /** 'set' for an upsert, 'delete' for a removal. */
  kind: 'set' | 'delete';
  key: K;
  /** Present on 'set'; absent on 'delete'. */
  value?: V;
  /** Snapshot of the full registry after the mutation, for batch writers. */
  snapshot: ReadonlyMap<K, V>;
}

export interface MakeRegistryOptions<K, V> {
  /**
   * Human-readable name used in error messages and logs. Should be unique
   * within the app (a duplicate name is not enforced today but will produce
   * confusing logs).
   */
  name: string;
  /**
   * Persistence policy — see module-level JSDoc. Required: there is
   * deliberately no default. Picking 'session' for a registry that should
   * be recoverable is a silent bug, so we force the call site to think
   * about it.
   */
  persistencePolicy: PersistencePolicy;
  /**
   * Side-effect callback fired after every successful set/delete. Required
   * for any non-'session' policy; the constructor throws if a non-'session'
   * policy is passed without `persist`.
   *
   * The callback is fire-and-forget — its return value (if a Promise) is
   * NOT awaited. If the persistence layer fails, the in-memory atom still
   * reflects the mutation; recovery is the persistence layer's problem.
   */
  persist?: (event: PersistEvent<K, V>) => void | Promise<void>;
  /**
   * Optional initial entries. For 'plexus-recovered' policy, this is the
   * hook for wiring the post-recovery rehydration: pass the entries the
   * recovery export rebuilt locally. The constructor does NOT fire
   * `persist` for these initial entries (they're already persisted).
   */
  initial?: Iterable<readonly [K, V]>;
}

export class RegistryConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'RegistryConfigError';
  }
}

export interface PersistentRegistry<K, V> {
  readonly name: string;
  readonly persistencePolicy: PersistencePolicy;
  /** The backing atom. Useful for `subscribe` integrations and effect graphs. */
  readonly atom: Atom<ReadonlyMap<K, V>>;

  set(key: K, value: V): void;
  get(key: K): V | undefined;
  has(key: K): boolean;
  delete(key: K): boolean;
  size(): number;
  keys(): IterableIterator<K>;
  values(): IterableIterator<V>;
  entries(): IterableIterator<readonly [K, V]>;
  /** Snapshot the entire registry. Returns a new Map (caller may mutate freely). */
  snapshot(): Map<K, V>;
  /**
   * Subscribe to mutations. Fires synchronously after every set/delete
   * with the post-mutation snapshot.
   */
  subscribe(fn: (snapshot: ReadonlyMap<K, V>) => void): () => void;
  /** Remove all entries. Fires `persist` for each removed key on policies that have one. */
  clear(): void;
}

export function makeRegistry<K, V>(opts: MakeRegistryOptions<K, V>): PersistentRegistry<K, V> {
  if (opts.persistencePolicy !== 'session' && !opts.persist) {
    throw new RegistryConfigError(
      `makeRegistry("${opts.name}"): persistencePolicy "${opts.persistencePolicy}" requires a "persist" callback. Pick "session" for in-memory-only registries.`,
    );
  }

  // Internal mutable map — we re-publish a NEW Map<K,V> on each mutation so
  // referential equality works as a change-detection signal for downstream
  // `derived`/`effect` consumers.
  const initial = new Map<K, V>(opts.initial ?? []);
  const a: Atom<ReadonlyMap<K, V>> = atom<ReadonlyMap<K, V>>(initial);

  function readMap(): Map<K, V> {
    // The atom holds a ReadonlyMap; we know it's a Map under the hood (we
    // built it). Cast for internal mutation; consumers see ReadonlyMap.
    return get(a) as Map<K, V>;
  }

  function publish(next: Map<K, V>): void {
    set(a, next);
  }

  function fire(event: PersistEvent<K, V>): void {
    if (!opts.persist) return;
    try {
      const r = opts.persist(event);
      if (r && typeof (r as Promise<unknown>).catch === 'function') {
        // Don't await — surface async failures so they don't crash silently.
        void (r as Promise<unknown>).catch((err) => {
          console.error(
            `[${opts.name}] persist callback rejected for ${event.kind} of`,
            event.key,
            err,
          );
        });
      }
    } catch (err) {
      console.error(`[${opts.name}] persist callback threw for ${event.kind} of`, event.key, err);
    }
  }

  return {
    name: opts.name,
    persistencePolicy: opts.persistencePolicy,
    atom: a,

    set(key, value) {
      const next = new Map(readMap());
      next.set(key, value);
      publish(next);
      fire({ kind: 'set', key, value, snapshot: next });
    },

    get(key) {
      return readMap().get(key);
    },

    has(key) {
      return readMap().has(key);
    },

    delete(key) {
      const cur = readMap();
      if (!cur.has(key)) return false;
      const next = new Map(cur);
      next.delete(key);
      publish(next);
      fire({ kind: 'delete', key, snapshot: next });
      return true;
    },

    size() {
      return readMap().size;
    },

    keys() {
      return readMap().keys();
    },

    values() {
      return readMap().values();
    },

    entries() {
      return readMap().entries();
    },

    snapshot() {
      return new Map(readMap());
    },

    subscribe(fn) {
      return subscribe(a, fn);
    },

    clear() {
      const cur = readMap();
      if (cur.size === 0) return;
      const removedKeys = Array.from(cur.keys());
      const next = new Map<K, V>();
      publish(next);
      // Fire persist once per removed key so downstream stores can replay
      // the deletion sequence. Snapshot is the empty post-state for all.
      for (const key of removedKeys) {
        fire({ kind: 'delete', key, snapshot: next });
      }
    },
  };
}

```
