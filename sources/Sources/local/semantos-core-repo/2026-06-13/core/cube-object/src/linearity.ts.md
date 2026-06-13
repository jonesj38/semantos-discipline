---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cube-object/src/linearity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.011131+00:00
---

# core/cube-object/src/linearity.ts

```ts
/**
 * Linearity primitives — the cube's substructural type.
 *
 * Two notations co-existed in the codebase before this extraction:
 *
 *   - Numeric (`Linearity = 0|1|2|3`) used by `apps/world-client/src/types.ts`
 *     to match the world-host wire format (`EntityDelta.linearity`).
 *   - String (`LinearityClass = 'linear'|'affine'|'relevant'`) used by
 *     `apps/demo-wasm-threejs/src/cell-engine.ts` to match the WASM kernel's
 *     human-friendly opcode-table input.
 *
 * Both are correct in their respective contexts; this module exposes both
 * shapes plus mappers so consumers don't have to reinvent the bridge.
 *
 * Numeric encoding (matches the server `Linearity` enum and the WASM
 * `linearity_code` byte):
 *
 *     0 LINEAR        — must be consumed exactly once. No DUP, no DROP.
 *     1 AFFINE        — at most once. DROP ok; DUP forbidden.
 *     2 RELEVANT      — at least once. DUP ok; DROP forbidden.
 *     3 UNRESTRICTED  — no constraints. (World-only; the WASM kernel
 *                       does not yet emit this code.)
 *
 * Color palette is a single source of truth here; both demo apps used to
 * keep their own copies. They now import `linearityColor` from this file.
 */

/** Numeric server-shape linearity. */
export type Linearity = 0 | 1 | 2 | 3;

/** String kernel-shape linearity (no UNRESTRICTED — kernel has 3 classes). */
export type LinearityClass = 'linear' | 'affine' | 'relevant';

/** Map a numeric linearity to its display name. */
export function linearityName(l: Linearity): string {
  switch (l) {
    case 0:
      return 'LINEAR';
    case 1:
      return 'AFFINE';
    case 2:
      return 'RELEVANT';
    case 3:
      return 'UNRESTRICTED';
  }
}

/** Map a numeric linearity to a hex color. */
export function linearityColor(l: Linearity): number {
  switch (l) {
    case 0:
      return 0x2cb2a5; // teal — LINEAR
    case 1:
      return 0xd98e23; // amber — AFFINE
    case 2:
      return 0x8b5cf6; // violet — RELEVANT
    case 3:
      return 0x64748b; // slate — UNRESTRICTED
  }
}

/**
 * Same color palette but keyed by string kernel notation. Convenience for
 * the substructural-typing object demo; identical mapping under the hood.
 */
export function linearityClassColor(c: LinearityClass): number {
  return linearityColor(linearityClassToNumeric(c));
}

/** Convert string kernel notation to numeric. */
export function linearityClassToNumeric(c: LinearityClass): Linearity {
  switch (c) {
    case 'linear':
      return 0;
    case 'affine':
      return 1;
    case 'relevant':
      return 2;
  }
}

/**
 * Convert numeric to string kernel notation. UNRESTRICTED has no kernel
 * counterpart and falls back to `'linear'` (the most-restrictive bound)
 * with a console warning so accidental misuse is observable.
 */
export function linearityToClass(l: Linearity): LinearityClass {
  switch (l) {
    case 0:
      return 'linear';
    case 1:
      return 'affine';
    case 2:
      return 'relevant';
    case 3:
      console.warn(
        '[cube-object] UNRESTRICTED linearity has no LinearityClass equivalent; falling back to "linear".',
      );
      return 'linear';
  }
}

```
