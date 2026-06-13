---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/CLAUDE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.811305+00:00
---

# `@semantos/plexus-vendor-sdk` — substrate vendor surface

Vendor-side crypto primitives: BRC-42 self-derivation (`deriveChildKey`),
L11 EP3259724B1 base derivation (`deriveSegment`, `deriveScalar`),
ECDH-42 (`deriveEdgeSk`), and the helper surface cartridges consume
when they need substrate-level crypto without reaching into `@bsv/sdk`
directly.

## Substrate governance line

This package is a **substrate**: the vendor-side crypto vocabulary
every cartridge that derives keys, signs envelopes, or computes
ECDH secrets depends on.

The cross-repo path-dep + pinned-rev pattern
([`docs/canon/cross-repo-path-dep-pattern.md`](../../docs/canon/cross-repo-path-dep-pattern.md), L26)
governs the boundary between substrate and extensions:

> Cartridges (`cartridges/*`) and runtime extensions (`runtime/*`)
> MAY depend on `@semantos/plexus-vendor-sdk`.
> `@semantos/plexus-vendor-sdk` SHALL NOT depend on any cartridge or
> runtime extension.

Concretely, no file under `src/` (excluding `__tests__/` and `tests/`,
which may use cartridge exports as cross-validation fixtures) may
import from:

- a relative path resolving into `cartridges/` or `runtime/`,
- a `@semantos/*` alias that resolves to a cartridge or runtime
  package (see [`tests/gates/substrate-one-way-dep.test.ts`](../../tests/gates/substrate-one-way-dep.test.ts)
  for the authoritative deny-list).

CI enforcement: `tests/gates/substrate-one-way-dep.test.ts` scans every
`core/<pkg>/src/` and rejects any reverse-dep automatically.

## Companions

- [`docs/canon/cw-lift-matrix.yml`](../../docs/canon/cw-lift-matrix.yml) — L11.
- [`docs/canon/templates/substrate-governance-line.md.template`](../../docs/canon/templates/substrate-governance-line.md.template).
