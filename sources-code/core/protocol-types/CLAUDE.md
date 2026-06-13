---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/CLAUDE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.797056+00:00
---

# `@semantos/protocol-types` — substrate contracts

The canonical TypeScript home for semantos protocol-level types: cell
wire format, BSV anchor attestation, field-tree disclosure (L8), scoped
disclosure envelopes (L9), MNCA snapshot-anchor builder (L13 carriers),
identity ports, and the shared adapter interfaces every cartridge
consumes when talking to the substrate.

Pairs with the Zig types under `zig/` for byte-identical
representations on both sides of the language boundary.

## Substrate governance line

This package is a **substrate**: the protocol-level type vocabulary
every cartridge depends on.

The cross-repo path-dep + pinned-rev pattern
([`docs/canon/cross-repo-path-dep-pattern.md`](../../docs/canon/cross-repo-path-dep-pattern.md), L26)
governs the boundary between substrate and extensions:

> Cartridges (`cartridges/*`) and runtime extensions (`runtime/*`)
> MAY depend on `@semantos/protocol-types`.
> `@semantos/protocol-types` SHALL NOT depend on any cartridge or
> runtime extension.

Concretely, no file under `src/` (excluding `__tests__/` and `tests/`,
which may use cartridge exports as cross-validation fixtures) may
import from:

- a relative path resolving into `cartridges/` or `runtime/`,
- a `@semantos/*` alias that resolves to a cartridge or runtime
  package (see [`tests/gates/substrate-one-way-dep.test.ts`](../../tests/gates/substrate-one-way-dep.test.ts)
  for the authoritative deny-list).

CI enforcement: `tests/gates/substrate-one-way-dep.test.ts` scans every
`core/<pkg>/src/` and rejects any reverse-dep automatically. Adding a
new cartridge or runtime package? Add its `@semantos/<name>` to the
gate's `FORBIDDEN_EXTENSION_ALIASES` list.

## Companions

- [`tests/gates/tessera-adapter-consumption.test.ts`](../../tests/gates/tessera-adapter-consumption.test.ts) —
  enforces the **run-down** direction for tessera specifically
  (cartridge → substrate only via `@semantos/protocol-types`).
- [`docs/canon/cw-lift-matrix.yml`](../../docs/canon/cw-lift-matrix.yml) — L26.
- [`docs/canon/templates/substrate-governance-line.md.template`](../../docs/canon/templates/substrate-governance-line.md.template) —
  pasteable snippet for new substrate packages.
