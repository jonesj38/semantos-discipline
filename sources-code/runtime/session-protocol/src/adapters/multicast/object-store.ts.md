---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/object-store.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.064951+00:00
---

# runtime/session-protocol/src/adapters/multicast/object-store.ts

```ts
/**
 * object-store — local cache of `NetworkResult`s observed on the wire,
 * keyed on `(semanticPath, ownerCert)` so concurrent writes by
 * different owners don't overwrite each other.
 *
 * Mirrors the legacy `MulticastAdapter.objects` map + `recordObject`
 * conflict-detection logic, lifted into a standalone module so
 * `MulticastAdapter.resolve()` can query without going through the
 * network state-machine.
 *
 * Conflict semantics:
 *   - Same `(path, owner)` → silently overwrites (latest wins).
 *   - Same `path`, different `owner` → both records preserved AND
 *     a `DuplicatePathEvent` is returned so the orchestrator can fire
 *     `onDuplicatePath` observers.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — `objects` map + `recordObject`
 */

import type {
  NetworkQuery,
  NetworkResult,
} from "@semantos/protocol-types/network";

import type { DuplicatePathEvent } from "./types.js";

export interface ObjectStore {
  /** Keyed `${semanticPath}::${ownerCert}` → record. */
  byPathOwner: Map<string, NetworkResult>;
}

export function createObjectStore(): ObjectStore {
  return { byPathOwner: new Map() };
}

/**
 * Insert or update an object record. Returns a `DuplicatePathEvent` when
 * the new record collides on `semanticPath` with an existing one under
 * a different `ownerCert`; otherwise `null`.
 */
export function recordObject(
  store: ObjectStore,
  result: NetworkResult,
  now: number,
): DuplicatePathEvent | null {
  const key = `${result.semanticPath}::${result.ownerCert}`;

  let conflict: DuplicatePathEvent | null = null;
  for (const [existingKey, existing] of store.byPathOwner) {
    if (
      existing.semanticPath === result.semanticPath &&
      existing.ownerCert !== result.ownerCert &&
      existingKey !== key
    ) {
      conflict = {
        type: "duplicate_path",
        semanticPath: result.semanticPath,
        existingOwner: existing.ownerCert,
        newOwner: result.ownerCert,
        timestamp: now,
      };
      break;
    }
  }

  store.byPathOwner.set(key, result);
  return conflict;
}

/**
 * Linear scan — `NetworkQuery` filters are sparse and the legacy
 * adapter capped result counts so this never grows pathological.
 * Returns at most `query.limit` (default 10) matches.
 */
export function queryObjects(
  store: ObjectStore,
  query: NetworkQuery,
): NetworkResult[] {
  const limit = query.limit ?? 10;
  const out: NetworkResult[] = [];
  for (const result of store.byPathOwner.values()) {
    if (out.length >= limit) break;
    if (!matches(result, query)) continue;
    out.push(result);
  }
  return out;
}

function matches(result: NetworkResult, query: NetworkQuery): boolean {
  if (query.path !== undefined && result.semanticPath !== query.path) return false;
  if (
    query.contentHash !== undefined &&
    result.contentHash !== query.contentHash
  ) {
    return false;
  }
  if (query.ownerCert !== undefined && result.ownerCert !== query.ownerCert) {
    return false;
  }
  if (query.typeHash !== undefined && result.typeHash !== query.typeHash) {
    return false;
  }
  if (query.parentPath !== undefined && result.parentPath !== query.parentPath) {
    return false;
  }
  return true;
}

export function objectCount(store: ObjectStore): number {
  return store.byPathOwner.size;
}

export function clearObjects(store: ObjectStore): void {
  store.byPathOwner.clear();
}

```
