---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/anchor-attestation/CLAUDE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.800596+00:00
---

# `@semantos/anchor-attestation` — substrate anchor surface

BSV anchor-attestation operations: `verifyAnchor`, the L4 composed
SPV-verify (`verifyInclusion` + `verifyAnchorAttestationInclusion`),
and the L5 idempotent batch-anchor primitives.

## Substrate governance line

This package is a **substrate**: the on-chain anchor verification surface
every cartridge that mints or verifies anchored cells depends on.

The cross-repo path-dep + pinned-rev pattern
([`docs/canon/cross-repo-path-dep-pattern.md`](../../docs/canon/cross-repo-path-dep-pattern.md), L26)
governs the boundary between substrate and extensions:

> Cartridges (`cartridges/*`) and runtime extensions (`runtime/*`)
> MAY depend on `@semantos/anchor-attestation`.
> `@semantos/anchor-attestation` SHALL NOT depend on any cartridge or
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

- [`docs/canon/cw-lift-matrix.yml`](../../docs/canon/cw-lift-matrix.yml) —
  L4 (verifyInclusion), L5 (idempotent batch anchor).
- [`docs/canon/templates/substrate-governance-line.md.template`](../../docs/canon/templates/substrate-governance-line.md.template).
