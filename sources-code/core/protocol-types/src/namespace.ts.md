---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/namespace.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.840063+00:00
---

# core/protocol-types/src/namespace.ts

```ts
/**
 * Namespace partition — single source of truth for flag-typed uint32 IDs.
 *
 * Per §8 Q2 of `docs/prd/UNIFICATION-ROADMAP.md` (resolved 2026-04-26),
 * every flag-typed ID type in the substrate (domain flags, lexicon ids,
 * region types, world-frame msgTypes, tenant types, and any future
 * id type) uses the same three-tier uint32 partition:
 *
 * | Tier | Range                  | Mnemonic              |
 * |------|------------------------|-----------------------|
 * | 1    | 0x00000001–0x000000FF  | Plexus reserved       |
 * | 2    | 0x00000100–0x0000FFFF  | Extended Plexus       |
 * | 3    | 0x00010000–0xFFFFFFFF  | Operator sovereignty  |
 *
 * Consumers MUST import these predicates rather than re-deriving the
 * partition convention. Single source of truth eliminates a class of
 * bug where two id types independently re-derive the partition and
 * disagree at the boundary.
 *
 * Side-finding from the GD9 audit (2026-05-13):
 * `core/plexus-contracts/src/domain-flags.ts` currently exports a
 * two-tier collapse (`PLEXUS_RESERVED_MAX = 0x0000ffff`, `CLIENT_BASE`).
 * Migration to use this module's predicates is a separate task
 * (Recommendation 2 of `docs/audits/2026-05-13-namespace-partition-vs-brc43-brc123.md`).
 */

// ── Tier boundaries (canonical) ───────────────────────────────────────────

/** Inclusive max for Tier 1 — Plexus reserved (single-byte slot). */
export const PLEXUS_RESERVED_MAX = 0x000000ff as const;

/** Inclusive max for Tier 2 — Extended Plexus (16-bit). */
export const EXTENDED_PLEXUS_MAX = 0x0000ffff as const;

/** Inclusive min for Tier 3 — Operator sovereignty. */
export const OPERATOR_BASE = 0x00010000 as const;

/** Inclusive max for any valid uint32 flag-typed ID. */
export const UINT32_MAX = 0xffffffff as const;

// ── Tier predicates ───────────────────────────────────────────────────────

/**
 * True iff the flag value is in Tier 1 (Plexus reserved, `0x01–0xFF`).
 * Tier 1 is for the smallest, most-frequently-checked Plexus flags
 * that need to fit in a single-byte slot.
 */
export function isPlexusReserved(flag: number): boolean {
  return Number.isInteger(flag) && flag >= 1 && flag <= PLEXUS_RESERVED_MAX;
}

/**
 * True iff the flag value is in Tier 2 (Extended Plexus, `0x100–0xFFFF`).
 * Tier 2 is for Plexus-owned flags that don't merit a single-byte slot
 * but still belong to the Plexus protocol rather than operator space.
 */
export function isExtendedPlexus(flag: number): boolean {
  return Number.isInteger(flag) && flag > PLEXUS_RESERVED_MAX && flag <= EXTENDED_PLEXUS_MAX;
}

/**
 * True iff the flag value is in Tier 3 (Operator sovereignty,
 * `0x10000–0xFFFFFFFF`). Tier 3 is for client/operator-defined flags;
 * Plexus does not assign or interpret values in this range.
 */
export function isOperatorSovereign(flag: number): boolean {
  return Number.isInteger(flag) && flag >= OPERATOR_BASE && flag <= UINT32_MAX;
}

// ── Composite ─────────────────────────────────────────────────────────────

/** Tier classification result. `invalid` for 0 or out-of-range values. */
export type NamespaceTier = "plexus" | "extended" | "operator" | "invalid";

/**
 * Classify a flag value by tier. Returns `"invalid"` for `0`, negative
 * numbers, non-integers, or values exceeding `0xFFFFFFFF`. Tier 1, 2,
 * and 3 are mutually exclusive by construction.
 */
export function namespaceTier(flag: number): NamespaceTier {
  if (isPlexusReserved(flag)) return "plexus";
  if (isExtendedPlexus(flag)) return "extended";
  if (isOperatorSovereign(flag)) return "operator";
  return "invalid";
}

/**
 * True iff the flag value falls within ANY valid tier (1, 2, or 3).
 * Convenience wrapper; equivalent to `namespaceTier(flag) !== "invalid"`.
 */
export function isValidNamespaceFlag(flag: number): boolean {
  return namespaceTier(flag) !== "invalid";
}

```
