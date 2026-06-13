---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/42-wasm-interface-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.768828+00:00
---

# 42 — Split `core/cell-ops/src/wasm-interface.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/42-wasm-interface`

## Why

481 LOC mixes error code translation, memory I/O helpers, and per-feature wrappers around the WASM module. Each feature wrapper is currently blocked by the module's size from being improved independently.

## Deliverables

Create under `core/cell-ops/src/wasm/`:

- `error-translator.ts` — map numeric error codes to `WasmError` subtypes; pure.
- `memory-accessor.ts` — `readBytes`, `writeBytes`, `readString`, `writeString`, `allocScope` helpers.
- `wrappers/` — one file per exported feature (e.g. `validate.ts`, `encode.ts`, `decode.ts`).
- `wasm-interface.ts` — module loader + facade (≤180 LOC).
- `__tests__/*.test.ts`.

Edit:

- Keep `core/cell-ops/src/wasm-interface.ts` re-exporting facade.

## Acceptance criteria

- [ ] No file over 200 LOC.
- [ ] Memory accessor can be unit-tested against a stub `WebAssembly.Memory`.
- [ ] Error translator has exhaustive switch and compile-time enum coverage check.
- [ ] `pnpm --filter @semantos/cell-ops check` passes.

## Out of scope

- Changing the WASM module itself or any exported signatures.

## Test plan

Unit tests for memory helpers (round-trip bytes, strings, allocation cleanup). Smoke test loading the WASM module and calling each feature wrapper with a fixture.
