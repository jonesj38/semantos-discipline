---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/address-normalisation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.477919+00:00
---

# cartridges/oddjobz/brain/src/address-normalisation.ts

```ts
/**
 * Address normalisation utilities for the oddjobz site dedupe path.
 *
 * Extracted from `cell-types/site.v2.ts` 2026-05-20 (CC5.B2b) as part of
 * retiring the v2 TS hand-mirror mirrors — the v2 *schema* now lives
 * declaratively in `cartridge.json` `objectTypes` (see CC5.B2a, PR #478),
 * but these pure utility functions remain load-bearing for the
 * conformance vectors at `core/cell-ops/tests/vectors/`.
 *
 * Note (flagged for CC6 cleanup): `runtime/legacy-ingest/src/` currently
 * has its own *separate* local copies of these functions (with comments
 * stating "Mirror of site.v2.ts ..."). That dual-truth is exactly the
 * source-adapter problem CC6 retires; unifying ingest onto these
 * canonical implementations is CC6 territory, not CC5.B2b.
 */

/**
 * Compute the canonical normalised form of an address.
 *
 * Lowercase + collapse internal whitespace to single spaces + trim. This
 * intentionally does NOT mangle the address structure — keeping things
 * like "13 orealla cr" and "13 orealla crescent" distinct is desirable
 * (the operator gets to confirm dedupes; aggressive normalisation would
 * collapse genuinely-different sites). Per the original PRD §6 R3.
 */
export function normaliseAddress(input: string): string {
  return input.toLowerCase().replace(/\s+/g, ' ').trim();
}

/**
 * Compute the lookupKey from a normalised address + optional key number.
 * Format: `<normalisedAddress>|<keyNumber-or-empty>`
 *
 * This is what the site lookup-or-mint path hashes on. Different units
 * at the same building disambiguate via their distinct keyNumber suffix.
 */
export function deriveLookupKey(normalisedAddress: string, keyNumber: string | null): string {
  return `${normalisedAddress}|${keyNumber ?? ''}`;
}

```
