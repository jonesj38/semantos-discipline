---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantic-objects/src/hash.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.936634+00:00
---

# core/semantic-objects/src/hash.ts

```ts
/**
 * State-hash helper. Each patch carries `prev_state_hash` and
 * `new_state_hash`; the new hash is computed deterministically from
 * the previous hash + the patch content.
 *
 * Uses node:crypto SHA-256. Portable to bun, node 20+.
 */
import { createHash } from 'node:crypto';

/**
 * Canonical hash: prev_state_hash (or empty) || stable JSON of delta || kind.
 * Produces a hex string (64 chars).
 */
export function computeNewStateHash(input: {
  prevStateHash: string | null;
  kind: string;
  delta: unknown;
  timestamp?: number | null;
}): string {
  const h = createHash('sha256');
  h.update(input.prevStateHash ?? '');
  h.update('\x1f');
  h.update(input.kind);
  h.update('\x1f');
  h.update(stableStringify(input.delta));
  h.update('\x1f');
  h.update(String(input.timestamp ?? 0));
  return h.digest('hex');
}

/**
 * Deterministic JSON stringify with sorted keys. Not a full JSON canon;
 * enough for our patch-delta hashing use case (no circular refs, no
 * non-JSON values).
 */
export function stableStringify(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) {
    return '[' + v.map(stableStringify).join(',') + ']';
  }
  const keys = Object.keys(v as Record<string, unknown>).sort();
  return (
    '{' +
    keys
      .map(
        (k) => JSON.stringify(k) + ':' + stableStringify((v as Record<string, unknown>)[k]),
      )
      .join(',') +
    '}'
  );
}

```
