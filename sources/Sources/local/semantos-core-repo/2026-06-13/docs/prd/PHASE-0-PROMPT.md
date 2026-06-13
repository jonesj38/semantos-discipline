---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-0-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.659485+00:00
---

# Phase 0 Re-Run Prompt

Copy everything below the line into Claude Code as the initial prompt.

---

## Prompt Start

Read these two documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-0-SCAFFOLDING.md`

Pay special attention to the **Errata section (E1–E10)** at the bottom of Phase 0. A previous attempt failed on every one of those points. You must not repeat them.

### What you are building

Phase 0 of the Semantos Zig/WASM Cell Engine — scaffolding only. No implementation logic. Four deliverables:

- D0.1: `constants.json` — single source of truth for all constants
- D0.2: Build script that generates `constants.zig` + `constants.ts` from that JSON
- D0.3: `@semantos/protocol-types` TypeScript package (thin bridge over `@semantos/core`, not a reimplementation)
- D0.4: Zig scaffold that compiles to WASM (stubs only — no stack allocation, no logic)

### Critical constraints from errata

1. **WASM binary must be single-digit KB** (2-8KB). Do NOT allocate PDA stacks. Do NOT import arrays. Stubs return a simple error code. If your WASM binary exceeds 20KB, something is wrong — stop and investigate.

2. **TDD means RED first, from the source**. Before writing any generator code:
   - Read `FORTH:SEMOBJ` (`semantos-gift-pack/forth/semantic-objects.fs`)
   - Read `PACKER:TYPE-REGISTRY` (`oddjobtodd/src/lib/domain/bridge/typeHashRegistry.ts`)
   - Extract the exact constant names and values from those files
   - Write tests with hardcoded expected values FROM those files
   - THEN write the generator to pass those tests
   - If a test fails, fix the code — NEVER adjust the test to match wrong output

3. **Directory layout must match the PRD exactly**:
   ```
   semantos-core/packages/
   ├── constants/
   │   ├── constants.json
   │   └── generate.ts
   ├── protocol-types/
   │   ├── package.json
   │   └── src/index.ts
   └── cell-engine/
       ├── build.zig
       ├── src/
       │   ├── main.zig
       │   ├── constants.zig      (generated)
       │   ├── cell.zig
       │   ├── bca.zig
       │   ├── pda.zig
       │   ├── linearity.zig
       │   ├── host.zig
       │   ├── errors.zig
       │   └── opcodes/
       │       ├── standard.zig
       │       ├── macro.zig
       │       └── plexus.zig
       ├── tests/
       │   └── smoke_test.zig
       └── bindings/
           ├── package.json
           ├── index.ts
           └── host-functions.ts
   ```
   This is under `semantos-core/packages/`, NOT `oddjobtodd/packages/`.

4. **Three Zig build targets** in `build.zig`:
   - `zig build test` → native tests
   - `zig build` (default) → wasm32-freestanding (embedded, no WASI)
   - Named step for wasm32-wasi (server)

5. **Protocol-types is a bridge, not a reimplementation**. Start by reading `CORE:WASM`, `CORE:SEMOBJ`, `CORE:CAPABILITY`, `CORE:DOMAIN-FLAGS` from semantos-core at `/Users/toddprice/projects/semantos-core/`. Import and re-export what already exists. Only define new types for things that genuinely don't exist in semantos-core (CellHeader with packed offsets, BCA types, generated constants enums).

6. **semantos-core dependency** resolves at `/Users/toddprice/projects/semantos-core/`. Do not use a symlink hack. Use `"@semantos/core": "file:/Users/toddprice/projects/semantos-core"` in package.json.

7. **Test count should be honest**. Aim for 15-25 meaningful tests, not 64 inflated ones. Every test should validate something specific:
   - Constants generator produces values that match source files (hardcoded expected values in tests)
   - Generated Zig constants compile
   - Generated TS constants match Zig constants
   - Protocol-types compile and re-export core types
   - WASM binary exists, is under 20KB, exports `kernel_init`
   - Stubs return error codes, not fake success
   - Name stub tests clearly: `"stub: packCell returns NOT_IMPLEMENTED"`

### Sequence

1. Read the source files listed in the Phase 0 doc (all 11 of them)
2. Write RED tests for constants with hardcoded expected values from the sources
3. Write the generator (GREEN) to pass those tests
4. Write RED tests for protocol-types
5. Write protocol-types package (GREEN)
6. Write RED tests for Zig scaffold (smoke test + WASM validation)
7. Write the Zig scaffold (GREEN)
8. Run all TDD gate tests
9. Verify WASM binary size is single-digit KB
10. Report what was built and what the test results are

### Done criteria

All 8 Phase Completion Criteria from the Phase 0 doc must be true. If any criterion fails, fix it before declaring done.
