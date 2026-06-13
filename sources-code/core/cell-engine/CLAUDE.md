---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/CLAUDE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.806351+00:00
---

# `@semantos/cell-engine` — substrate graph engine

The cell-graph runtime: the WASM-portable engine that mints, indexes,
and walks cells. Carved for embedded targets (ESP32-C6 lands < 128 KB
linear memory; see `cell_engine_static_5mb_unfit_for_mcu` memory).

## Substrate governance line

This package is a **substrate**: the cell-graph engine every cartridge
and embedded edge node depends on.

The cross-repo path-dep + pinned-rev pattern
([`docs/canon/cross-repo-path-dep-pattern.md`](../../docs/canon/cross-repo-path-dep-pattern.md), L26)
governs the boundary between substrate and extensions:

> Cartridges (`cartridges/*`) and runtime extensions (`runtime/*`)
> MAY depend on `@semantos/cell-engine`.
> `@semantos/cell-engine` SHALL NOT depend on any cartridge or
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

- [`docs/canon/cw-lift-matrix.yml`](../../docs/canon/cw-lift-matrix.yml) — L26.
- [`docs/canon/templates/substrate-governance-line.md.template`](../../docs/canon/templates/substrate-governance-line.md.template) —
  pasteable snippet for new substrate packages.
