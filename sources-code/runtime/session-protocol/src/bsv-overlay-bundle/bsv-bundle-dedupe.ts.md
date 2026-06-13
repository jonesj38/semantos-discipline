---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-dedupe.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.047899+00:00
---

# runtime/session-protocol/src/bsv-overlay-bundle/bsv-bundle-dedupe.ts

```ts
/**
 * Bundle dedupe — observable seen-outpoint set.
 *
 * The overlay may return the same output on successive polls (SLAP
 * caching, retries). Subscribers must see each bundle exactly once
 * per subscription lifetime, so the poller folds incoming results
 * through a per-subscription dedupe instance.
 *
 * The instance is observable — subscribers can read `size`, snapshot
 * the seen set, and listen for changes. This makes test assertions
 * trivial ("after publish + poll, dedupe contains exactly one
 * outpoint") and matches the wave-1 atom-backed registry pattern.
 *
 * No `@semantos/protocol-types/atoms` dep — session-protocol stays
 * peer-light. The shape is the same: snapshot + subscribe + clear.
 */

export type DedupeListener = (event: DedupeEvent) => void;

export interface DedupeEvent {
  /** The outpoint just added. */
  outpoint: string;
  /** Total seen-set size after the add. */
  size: number;
}

export interface BundleDedupe {
  /**
   * Mark `outpoint` as seen. Returns `true` on first sight (caller
   * should deliver the bundle), `false` if the outpoint was already
   * recorded.
   */
  markSeen(outpoint: string): boolean;
  /** Number of distinct outpoints currently tracked. */
  readonly size: number;
  /** Snapshot of the current seen-set. Defensive copy. */
  snapshot(): readonly string[];
  /** Drop all tracked outpoints — used on unsubscribe. */
  clear(): void;
  /**
   * Subscribe to additions. Listener fires once per new outpoint
   * (never on duplicates, never on `clear`). Returns an unsubscribe.
   */
  subscribe(listener: DedupeListener): () => void;
}

/**
 * Construct a fresh dedupe instance. One per subscription; cleared
 * when the subscription tears down.
 */
export function createBundleDedupe(): BundleDedupe {
  const seen = new Set<string>();
  const listeners = new Set<DedupeListener>();

  return {
    markSeen(outpoint: string): boolean {
      if (seen.has(outpoint)) return false;
      seen.add(outpoint);
      const event: DedupeEvent = { outpoint, size: seen.size };
      for (const l of listeners) {
        try {
          l(event);
        } catch {
          // Listener errors must not corrupt dedupe state.
        }
      }
      return true;
    },

    get size() {
      return seen.size;
    },

    snapshot(): readonly string[] {
      return Array.from(seen);
    },

    clear(): void {
      seen.clear();
    },

    subscribe(listener: DedupeListener): () => void {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
}

```
