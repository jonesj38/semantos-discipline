---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/decision-cache.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.471897+00:00
---

# packages/scada/scada/src/authorization/decision-cache.ts

```ts
/**
 * Decision cache — short-TTL memoization of authorization outcomes.
 *
 * Authorization decisions for the same `(operatorId, commandType,
 * targetEquipment, tokenId)` tuple within the TTL window return the
 * cached result. Decisions are LINEAR though, so the cache is
 * intentionally conservative: only `pass` decisions are cached, never
 * rejects (an operator may have just been re-credentialed). The cache
 * is also flushed when a token is consumed.
 *
 * Backed by an `Atom<Map<string, CachedDecision>>` so:
 *   - the cache state is observable (tests, dashboards)
 *   - per-runtime instances stay isolated (the atom registry is keyed
 *     by an arbitrary scope id, default "global")
 *   - tests can `resetDecisionCache()` between cases
 *
 * No timers, no setInterval — eviction is lazy at lookup time so the
 * cache is safe to use in single-tick test environments.
 */

import { atom, type Atom } from '@semantos/state';

import type { SCADACommandType } from '../types';

export interface CachedDecision {
  /** Wall-clock ms when the decision was recorded. */
  cachedAtMs: number;
  /** TTL in ms — entry expires when `nowMs > cachedAtMs + ttlMs`. */
  ttlMs: number;
  /** The verdict — only `pass` is ever stored. */
  verdict: 'pass';
  /** Required capability number that was satisfied (for audit). */
  required: number | null;
}

export interface DecisionCacheAtoms {
  scopeId: string;
  cacheAtom: Atom<Map<string, CachedDecision>>;
}

const registry = new Map<string, DecisionCacheAtoms>();

/** Idempotently get-or-create a decision-cache bundle for a scope. */
export function getDecisionCacheAtoms(scopeId = 'global'): DecisionCacheAtoms {
  const existing = registry.get(scopeId);
  if (existing) return existing;
  const bundle: DecisionCacheAtoms = {
    scopeId,
    cacheAtom: atom<Map<string, CachedDecision>>(new Map()),
  };
  registry.set(scopeId, bundle);
  return bundle;
}

/** Test helper — wipes all per-scope caches. */
export function resetDecisionCache(): void {
  registry.clear();
}

/** Build the canonical cache key from a decision tuple. */
export function decisionKey(
  operatorId: string,
  commandType: SCADACommandType,
  targetEquipment: string,
  tokenId: string,
): string {
  return `${operatorId}::${commandType}::${targetEquipment}::${tokenId}`;
}

/**
 * Look up a cached pass-decision. Returns `undefined` if no entry, or
 * if the entry has expired (and lazily evicts it).
 */
export function lookupDecision(
  scope: DecisionCacheAtoms,
  key: string,
  nowMs: number,
): CachedDecision | undefined {
  const cache = scope.cacheAtom.value;
  const entry = cache.get(key);
  if (!entry) return undefined;
  if (nowMs > entry.cachedAtMs + entry.ttlMs) {
    // Lazy eviction. Mutate then notify observers.
    cache.delete(key);
    return undefined;
  }
  return entry;
}

/** Record a successful decision with a TTL. */
export function recordDecision(
  scope: DecisionCacheAtoms,
  key: string,
  decision: CachedDecision,
): void {
  const cache = scope.cacheAtom.value;
  cache.set(key, decision);
}

/** Drop all entries that mention a particular token id. */
export function invalidateForToken(
  scope: DecisionCacheAtoms,
  tokenId: string,
): void {
  const cache = scope.cacheAtom.value;
  for (const key of Array.from(cache.keys())) {
    if (key.endsWith(`::${tokenId}`)) cache.delete(key);
  }
}

```
