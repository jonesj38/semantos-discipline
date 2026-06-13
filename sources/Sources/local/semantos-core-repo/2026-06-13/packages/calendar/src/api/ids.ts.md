---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/calendar/src/api/ids.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.484027+00:00
---

# packages/calendar/src/api/ids.ts

```ts
/**
 * ID generation. Prefixed with a type tag so logs + debug output are
 * legible. UUID-free (no dep) — uses crypto.randomUUID under the hood
 * if available; falls back to timestamp+random for node <19.
 */
export function newHoldId(): string {
  return `hold_${randomSegment()}`;
}

export function newBookingId(): string {
  return `book_${randomSegment()}`;
}

function randomSegment(): string {
  // crypto.randomUUID is Node >= 19; available in all current runtimes.
  const g = globalThis as { crypto?: { randomUUID?: () => string } };
  if (g.crypto?.randomUUID) return g.crypto.randomUUID().replace(/-/g, '');
  // Fallback: ts + 8 random chars.
  return `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

```
