---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/linearity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.506856+00:00
---

# cartridges/oddjobz/brain/src/cell-types/linearity.ts

```ts
/**
 * Linearity classes — high-level extension labels and their canonical
 * mapping to the wire-level linearity field at cell-header offset 16.
 *
 * **Source of truth: Lean + Zig kernel.**
 *   - `proofs/lean/Semantos/Cell.lean:13-17` — inductive `Linearity` type.
 *   - `core/cell-engine/src/linearity.zig:10-14` — `LinearityType` enum.
 *
 * `proofs/lean/Semantos/Linearity.lean`'s file header explicitly says it
 * transliterates the Zig source and "Every row must match." The Lean and
 * Zig agree; the protocol spec doc (`docs/spec/protocol-v0.5.md` §3.4) is
 * stale and will be corrected via a separate erratum.
 *
 * The on-wire encoding has four values:
 *   LINEAR    = 1  (consumed exactly once; no DUP, no DROP)
 *   AFFINE    = 2  (used at most once; no DUP, DROP permitted)
 *   RELEVANT  = 3  (used at least once; DUP permitted, no DROP)
 *   DEBUG     = 4  (unrestricted — development only)
 *
 * The Zig kernel enforces these via `OP_ASSERTLINEAR` (0xC5) and the
 * standard DUP/DROP linearity checks. Lean K1 (`LinearityK1.lean`)
 * proves the consumption invariants for LINEAR/AFFINE/RELEVANT.
 *
 * The §O2 plan (ODDJOBZ-EXTENSION-PLAN.md) speaks in three high-level
 * labels we ship: LINEAR, PERSISTENT, AFFINE. The mapping below pins
 * each high-level label to a wire-level encoding so the Forth/Zig
 * kernel and the TS pack/unpack agree.
 *
 *   LINEAR     → wire LINEAR    (job/quote/visit/invoice — consumed once)
 *   PERSISTENT → wire RELEVANT  (customer/site/message — accumulate, never destructively consumed)
 *   AFFINE     → wire AFFINE    (estimate — discardable draft)
 *
 * Note: §O2's draft table also listed a PATCH high-level label for the
 * message cell. PATCH has no formal Lean backing — the
 * parentHash-anchoring + compaction semantics that distinguish PATCH
 * from plain RELEVANT live at the state-machine layer (D-O4
 * territory), not at the kernel-gate layer. Per the user's directive
 * ("conform with Lean and TLA+; don't do it if we can't formally
 * verify it"), `oddjobz.message.v1` ships as plain PERSISTENT (wire
 * RELEVANT). The patch-anchoring semantics are an extension-layer
 * concern documented in the message cell's module head.
 *
 * The high-level label is what consumers reason about (state machines,
 * cap mints). The wire-level code is what the kernel checks. The
 * mapping is canonical and frozen here.
 */

/** Wire-level linearity codes (header offset 16, uint32 LE).
 * Values match `core/cell-engine/src/linearity.zig:10-14` and
 * `proofs/lean/Semantos/Cell.lean:13-17`. */
export const WireLinearity = {
  LINEAR: 1,
  AFFINE: 2,
  RELEVANT: 3,
  DEBUG: 4,
} as const;

export type WireLinearityCode = (typeof WireLinearity)[keyof typeof WireLinearity];

/** High-level linearity labels per §O2 (PATCH dropped — no formal backing). */
export type Linearity = 'LINEAR' | 'PERSISTENT' | 'AFFINE';

/**
 * Canonical mapping from §O2 labels to wire-level codes.
 *
 * Frozen — do not edit without updating the Lean `Linearity` inductive
 * type, the Zig `LinearityType` enum, and every conformance vector.
 * Wire code drift would silently break K1/K2/K4 enforcement.
 */
export const linearityWire: Readonly<Record<Linearity, WireLinearityCode>> =
  Object.freeze({
    LINEAR: WireLinearity.LINEAR,
    PERSISTENT: WireLinearity.RELEVANT,
    AFFINE: WireLinearity.AFFINE,
  });

/** Reverse lookup: wire code → §O2 label. RELEVANT maps to PERSISTENT
 * (the only §O2 label using that wire code in this extension). DEBUG
 * is not used by any oddjobz cell type and is rejected. */
export function wireToCanonicalLinearity(code: WireLinearityCode): Linearity {
  if (code === WireLinearity.LINEAR) return 'LINEAR';
  if (code === WireLinearity.AFFINE) return 'AFFINE';
  if (code === WireLinearity.RELEVANT) return 'PERSISTENT';
  throw new Error(`unmapped wire linearity code: ${code}`);
}

```
