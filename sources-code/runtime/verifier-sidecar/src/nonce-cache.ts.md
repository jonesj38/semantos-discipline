---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/verifier-sidecar/src/nonce-cache.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.085394+00:00
---

# runtime/verifier-sidecar/src/nonce-cache.ts

```ts
/**
 * InMemoryNonceCache — in-process anti-replay nonce store.
 *
 * Spec: docs/spec/protocol-v0.5.md §12.1, §13.3 (constant-time, replay
 * prevention) and textbook §14 ("nonce and timestamp replay prevention").
 *
 * This implementation uses a Map with TTL-based expiry. Entries are
 * reaped lazily on every setNonce call, keeping memory bounded for
 * long-running processes.
 *
 * K invariant: no specific K; supports K2 boundary guarantee by ensuring
 * that replay attacks are rejected before the cell engine gate.
 */

import type { NonceCache } from "./types.js";

export class InMemoryNonceCache implements NonceCache {
  /** nonce hex → absolute expiry time (Date.now()-epoch ms) */
  private readonly store = new Map<string, number>();
  private readonly defaultTtlMs: number;
  private readonly nowMs: () => number;

  constructor(defaultTtlMs = 600_000, nowMs: () => number = Date.now) {
    this.defaultTtlMs = defaultTtlMs;
    this.nowMs = nowMs;
  }

  hasNonce(nonce: string): boolean {
    const expiry = this.store.get(nonce);
    if (expiry === undefined) return false;
    // If expired, treat as not-present (avoid false positive after TTL).
    if (this.nowMs() >= expiry) {
      this.store.delete(nonce);
      return false;
    }
    return true;
  }

  setNonce(nonce: string, expireMs: number): void {
    this.store.set(nonce, expireMs);
    this.reapExpired();
  }

  /** Purge expired entries. Called lazily on every write. */
  private reapExpired(): void {
    const now = this.nowMs();
    for (const [n, exp] of this.store) {
      if (now >= exp) this.store.delete(n);
    }
  }

  /** Number of live (non-expired) entries — for testing. */
  get size(): number {
    const now = this.nowMs();
    let count = 0;
    for (const exp of this.store.values()) {
      if (now < exp) count++;
    }
    return count;
  }
}

```
