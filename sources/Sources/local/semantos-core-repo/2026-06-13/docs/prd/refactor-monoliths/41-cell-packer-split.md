---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/41-cell-packer-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.770341+00:00
---

# 41 — Split `core/cell-ops/src/cellPacker.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/41-cell-packer`

## Why

650 LOC mixes varint encoding, continuation/multicell assembly, and per-op packers. This is core-path code — it needs small, testable modules.

## Deliverables

Create under `core/cell-ops/src/packer/`:

- `varint.ts` — pure `encodeVarInt`, `decodeVarInt`, `sizeOfVarInt`.
- `continuation-handlers.ts` — continuation frame build/parse; one function per frame kind.
- `multicell-assembler.ts` — gather continuation frames into a logical cell; pure reducer over incoming frames.
- `op-packers/` — one file per cell op (e.g. `pack-create.ts`, `pack-update.ts`, `pack-delete.ts`). Each exports `pack(input) → bytes`.
- `cell-packer.ts` — public facade `pack(cell) → bytes` / `unpack(bytes) → cell` (≤150 LOC).
- `__tests__/*.test.ts`.

Edit:

- `core/cell-ops/src/cellPacker.ts` → re-export facade.

## Acceptance criteria

- [ ] No file over 200 LOC.
- [ ] `varint.ts` has zero imports from other project files.
- [ ] Round-trip property tests: `unpack(pack(x)) === x` for 100 random cells of each kind.
- [ ] `pnpm --filter @semantos/cell-ops check` passes.

## Out of scope

- Changing byte layout or version numbers.

## Test plan

Fixture-based round-trip + property-based with fast-check. Benchmark: pack/unpack of 1k cells ≤ current baseline ±10%.
