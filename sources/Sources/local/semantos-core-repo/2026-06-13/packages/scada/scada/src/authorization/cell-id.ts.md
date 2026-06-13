---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/authorization/cell-id.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.474222+00:00
---

# packages/scada/scada/src/authorization/cell-id.ts

```ts
/**
 * Cell-id and timestamp helpers — extracted from the legacy file so the
 * flow modules can share the same monotonic sequence and timestamp
 * format without duplicating the closure.
 *
 * Behaviour preserved exactly:
 *   - `cell-${Date.now() in hex}-${counter in 4-hex padded}`
 *   - `YYYY-MM-DDTHH:mm:ss.sssZZZZ` (microsecond-suffix ISO).
 */

let cellCounter = 0;

export function generateCellId(): string {
  cellCounter++;
  return `cell-${Date.now().toString(16)}-${cellCounter.toString(16).padStart(4, '0')}`;
}

export function microsecondTimestamp(): string {
  const now = new Date();
  return now.toISOString().replace('Z', '000Z');
}

/** Test helper — reset the counter between tests. Not part of the
 * public surface but exposed via the barrel for `__tests__`. */
export function _resetCellIdCounter(): void {
  cellCounter = 0;
}

```
