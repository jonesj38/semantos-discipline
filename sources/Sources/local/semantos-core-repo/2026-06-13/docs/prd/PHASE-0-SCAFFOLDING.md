---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-0-SCAFFOLDING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.656608+00:00
---

# Phase 0: Scaffolding and Constants Unification

**Duration**: 1 week (with 40% buffer: ~10 days)
**Prerequisites**: None — this is the first phase.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

You are building the Semantos Cell Engine — a Zig-implemented, WASM-compiled execution layer for 1KB semantic cells with cryptographic linearity enforcement. This phase creates the foundation: a single source of truth for all constants, the shared TypeScript types package, and an empty but compiling Zig scaffold.

**What Semantos is**: A Semantic Name System (SNS) that maps cryptographically typed names to sovereign digital objects. NOT a blockchain app, NOT a wallet. It operates at the level of meaning rather than addresses. The system uses 1KB cells (256-byte header + 768-byte payload) with linearity types (LINEAR/AFFINE/RELEVANT) that enforce resource semantics.

**What you are building in this phase**: The scaffolding that every subsequent phase depends on. No implementation logic — just the project structure, constants pipeline, and type definitions that ensure all future code references a single source of truth.

---

## Source Files You MUST Read

All paths relative to `/Users/toddprice/projects/semantos/`.

| Alias | Path | What to extract |
|-------|------|----------------|
| `FORTH:SEMOBJ` | `semantos-gift-pack/forth/semantic-objects.fs` | Magic numbers (lines 78-81): 0xDEADBEEF, 0xCAFEBABE, 0x13371337, 0x42424242. Linearity constants (lines 23-26): LINEAR=1, AFFINE=2, RELEVANT=3, DEBUG=4. Cell size (line 16): 1024. Header size: 256. Payload size: 768. |
| `FORTH:COMMERCE` | `semantos-gift-pack/forth/commerce-header.fs` | Phase constants (lines 38-46): SOURCE=0x00 through OUTCOME=0x07, UNKNOWN=0xFF. Dimension constants (lines 51-54): COMPOSITE=0x00, WHAT=0x01, HOW=0x02, INSTRUMENT=0x03. |
| `FORTH:2PDA` | `semantos-gift-pack/forth/bitcoin-2pda.fs` | Stack sizes (lines 16-18): CELL-SIZE=1024, MAIN-STACK-CELLS=1024, AUX-STACK-CELLS=256. |
| `FORTH:MACROS` | `semantos-gift-pack/forth/craig-macros.fs` | Opcode ranges: Craig macros 0xB0-0xBF. Plexus opcodes 0xC0-0xCF. |
| `PACKER:TYPE-REGISTRY` | `oddjobtodd/src/lib/domain/bridge/typeHashRegistry.ts` | **CANONICAL packed wire-format header offsets** — magic(0,16B), linearity(16,4B), version(20,4B), flags(24,4B), refCount(28,2B), typeHash(30,32B), ownerId(62,16B), timestamp(78,8B), cellCount(86,4B), totalSize(90,4B). Commerce: phase(94,1B), dimension(95,1B), parentHash(96,32B), prevState(128,32B). |
| `PACKER:MAIN` | `oddjobtodd/src/lib/semantos-kernel/cellPacker.ts` | Continuation types: BUMP(0x01), ATOMIC_BEEF(0x02), ENVELOPE(0x03), DATA(0x04), STATE(0x05). Continuation header: 8 bytes (cellType:1, cellIndex:2, totalCells:2, payloadSize:2, reserved:1). |
| `CORE:SEMOBJ` | `semantos-core/src/types/semantic-objects.ts` | SemanticType enum, LinearObject, AffineObject, RelevantObject interfaces. |
| `CORE:CAPABILITY` | `semantos-core/src/types/capability.ts` | CapabilityToken, CapabilityType enum, CapabilityConstraints. |
| `CORE:DOMAIN-FLAGS` | `semantos-core/src/types/domain-flags.ts` | DomainFlag type, well-known flags 0x01-0x0A, 3-tier ranges. |
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | PlexusKernelWasm interface, PlexusKernelHostImports interface. |
| `DOC:BCA-PAPER` | `(uploaded) 2311.15842v1.pdf` | BCA parameters: modifier(16B), subnetPrefix(8B), IPv6(16B), pubkey(33B), collisionCountMax(2). |

---

## Deliverables

### D0.1 — `constants.json`

A single JSON file containing ALL constants extracted from the Forth references and typeHashRegistry.ts. This is the single source of truth. See Appendix A of the master PRD for the full schema.

**Critical**: The `headerOffsets` section MUST use the packed wire-format offsets from `PACKER:TYPE-REGISTRY`, NOT the GForth cell-width offsets. This was resolved as Q6 in the master PRD.

### D0.2 — Build script: `constants.json` → `constants.zig` + `constants.ts`

A script (TypeScript, run via `bun run generate-constants`) that reads `constants.json` and produces:
- `src/constants.zig` — Zig `pub const` declarations
- `packages/protocol-types/src/constants.ts` — TypeScript `export const` declarations

Both files must be byte-reproducible (same input → same output). Include a header comment in each generated file stating it is auto-generated from `constants.json`.

### D0.3 — `@semantos/protocol-types` package

TypeScript package with all shared types. Must contain:
- `CellHeader` interface (matching packed wire-format offsets)
- `CommerceExtension` interface
- `OnChainBinding` interface
- `LinearityType` enum (LINEAR=1, AFFINE=2, RELEVANT=3, DEBUG=4)
- `CommercePhase` enum
- `TaxonomyDimension` enum
- `CellType` enum (BUMP=1, ATOMIC_BEEF=2, ENVELOPE=3, DATA=4, STATE=5)
- `BCAInput`, `BCAOutput`, `BCAVerifyInput` interfaces
- `ScriptContext`, `ScriptResult` interfaces
- `LinearityOperation`, `LinearityResult` interfaces
- `CapabilityTokenRef` interface
- `DomainFlag` type
- Generated `constants.ts` from D0.2

**Decision required** (see Q5 in master PRD): Should this be a new package or extend `@semantos/core`? Default: create new package. Much of the type system already exists in `CORE:SEMOBJ`, `CORE:CAPABILITY`, `CORE:DOMAIN-FLAGS` — import and re-export where possible rather than duplicating.

### D0.4 — Zig build scaffold

```
packages/cell-engine/
├── build.zig
├── src/
│   ├── main.zig          # WASM entry point (empty — just exports init)
│   ├── constants.zig      # Generated from constants.json
│   ├── cell.zig           # Stub: pub fn packCell(...) ...
│   ├── bca.zig            # Stub
│   ├── pda.zig            # Stub
│   ├── linearity.zig      # Stub
│   ├── host.zig           # Stub: extern declarations
│   ├── errors.zig         # Error union type
│   └── opcodes/
│       ├── standard.zig   # Stub
│       ├── macro.zig      # Stub
│       └── plexus.zig     # Stub
├── tests/
│   └── smoke_test.zig     # Verifies constants load
└── bindings/
    ├── package.json
    ├── index.ts           # Stub loader
    └── host-functions.ts  # Stub
```

`build.zig` must support three targets:
- `zig build` → native tests
- `zig build -Dtarget=wasm32-freestanding` → embedded WASM (no WASI)
- `zig build -Dtarget=wasm32-wasi` → server WASM

---

## TDD Gate — Tests That Must Pass

### Test 1: Constants round-trip
```
bun run generate-constants
# Verify: constants.zig exists, constants.ts exists
# Verify: re-running produces byte-identical output
```

### Test 2: Protocol-types compile
```
cd packages/protocol-types && bun run build
# Verify: zero TypeScript errors
# Verify: all enums have correct values (LinearityType.LINEAR === 1, etc.)
```

### Test 3: Zig scaffold compiles
```
cd packages/cell-engine && zig build
# Verify: produces WASM binary (even if empty/minimal)
# Verify: `zig build test` runs smoke_test.zig successfully
```

### Test 4: WASM binary basic validation
```
# Verify: WASM binary is under 500KB (should be trivial at this stage)
# Verify: WASM binary exports at minimum: kernel_init
```

### Test 5: Constants consistency
```
# Verify: constants.zig CELL_SIZE == 1024
# Verify: constants.zig HEADER_SIZE == 256
# Verify: constants.zig PAYLOAD_SIZE == 768
# Verify: constants.zig MAGIC_1 == 0xDEADBEEF
# Verify: constants.zig LINEARITY_LINEAR == 1
# Verify: constants.ts values match constants.zig values exactly
```

---

## Phase Completion Criteria

You are **done with Phase 0** when ALL of the following are true:

1. `constants.json` exists and contains every constant from Appendix A of the master PRD
2. `bun run generate-constants` produces `constants.zig` and `constants.ts` deterministically
3. `@semantos/protocol-types` compiles with `bun run build` — zero errors
4. `zig build` in `packages/cell-engine/` produces a WASM binary
5. `zig build test` passes `smoke_test.zig`
6. All 5 TDD gate tests above pass
7. No hardcoded values exist anywhere — every constant traces back to `constants.json`
8. Header offsets in `constants.json` match the packed wire-format from `PACKER:TYPE-REGISTRY` (NOT GForth offsets)

## What NOT To Do

- Do not implement any cell packing logic — that's Phase 1
- Do not implement any cryptographic operations — that's Phase 2+
- Do not implement any stack operations — that's Phase 3
- Do not create mock data or placeholder return values — stubs return errors, not fake success
- Do not use GForth cell-width (8-byte) offsets for the header layout — use packed offsets from typeHashRegistry.ts
- Do not hardcode any constant values in Zig or TypeScript source — everything comes from constants.json

---

## Blockers and Dependencies

- **None** — this phase has no external dependencies
- If `PACKER:TYPE-REGISTRY` offsets conflict with `FORTH:SEMOBJ` offsets, **the TypeScript offsets win** (they are the production wire format)
- If `CORE:SEMOBJ` types conflict with `FORTH:SEMOBJ` structure, **semantos-core types win** for TypeScript, **Forth structure wins** for the binary wire format

---

## Errata — Lessons from First Phase 0 Attempt

A previous Claude Code session attempted Phase 0. The following issues were identified and must be avoided on re-attempt:

### E1: WASM binary size (493KB for stubs)
The first attempt produced a 493KB WASM binary for an empty scaffold with stub functions returning -1. This is ~98% of the 500KB budget before any real code exists. **Root cause**: The static stack arrays (1024 × 1024 bytes = 1MB for main stack) were likely being included in the WASM data section even though they're unused at this phase. **Fix**: Do NOT statically allocate the PDA stacks in Phase 0. The stubs don't need them. Stacks are Phase 3. Phase 0's WASM binary should be single-digit KB — likely 2-8KB for stubs that only return error codes.

### E2: Symlink hack for semantos-core dependency
The protocol-types package had `"@semantos/core": "file:../../semantos-core"` as a dependency. In a worktree, this path didn't resolve, so a symlink was created. **Fix**: semantos-core now lives at `/Users/toddprice/projects/semantos-core/` (top-level project, not inside oddjobtodd). Use an absolute `file:` path or a workspace protocol. The dependency must resolve in CI without symlinks.

### E3: Constants naming drift
The generator produced `MAGIC1` but the initial test expected `MAGIC_1`. The test was adjusted to match the generator rather than the generator being corrected to match canonical names. **Fix**: Read the Forth source (`FORTH:SEMOBJ`) and `typeHashRegistry.ts` FIRST, establish the canonical naming convention, THEN write both generator and tests to that convention. Tests validate the generator against the source, not the generator against itself. The canonical naming convention uses underscores: `MAGIC_1`, `MAGIC_2`, `MAGIC_3`, `MAGIC_4`.

### E4: Test depth — 64 shallow tests instead of focused validation
64 tests passed, but the majority tested that stubs exist and return NOT_IMPLEMENTED, or that generated TypeScript files have expected exports. This inflates confidence. **Fix**: Name scaffold tests explicitly (e.g., `"stub: kernel_init returns NOT_IMPLEMENTED"`) and keep scaffold assertion count honest — Phase 0 should have ~15-25 meaningful tests, not 64 padding tests. Count tests that validate generator correctness against the source, not the generator against itself.

### E5: Package directory location
The first attempt created packages inside `oddjobtodd/packages/` (a Next.js app). The cell engine packages live in `semantos-core/packages/`, alongside the core TypeScript library. **Fix**: Create `semantos-core/packages/cell-engine/`, `semantos-core/packages/constants/`, `semantos-core/packages/protocol-types/`.

### E6: Test-adjusting instead of code-fixing
When constants tests failed because `MAGIC1` ≠ `MAGIC_1`, the test was changed to match the generator's incorrect output rather than fixing the generator. This is the opposite of TDD. **Fix**: RED phase tests encode the canonical expectation from source files. When RED fails, you fix the code (GREEN), never the test. If the test was wrong, it means the Forth source wasn't read before writing the test — which means the TDD sequence was violated.

### E7: Missing directory structure — flat stubs instead of modular scaffold
The PRD specifies `cell.zig`, `bca.zig`, `pda.zig`, `linearity.zig`, `host.zig`, `errors.zig`, and `opcodes/` subdirectory. The first attempt consolidated stubs into `main.zig` or minimal files. **Fix**: Follow the directory layout exactly. Each `.zig` file exists as a module boundary for a future phase. This matters because `build.zig` must add each as a module for incremental compilation.

### E8: No build-target flexibility
The PRD requires three build targets: `zig build` (native tests), `zig build -Dtarget=wasm32-freestanding` (embedded), and `zig build -Dtarget=wasm32-wasi` (server). The first attempt only built one target. **Fix**: `build.zig` must define all three as named steps (e.g., `zig build wasm-freestanding`, `zig build wasm-wasi`, `zig build test`).

### E9: Protocol-types re-export strategy was backwards
The first attempt created new types from scratch and then tried to reconcile with `@semantos/core`. **Fix**: Start from `CORE:WASM`, `CORE:SEMOBJ`, `CORE:CAPABILITY`, `CORE:DOMAIN-FLAGS` — import and re-export what exists, then add only what's genuinely new (CellHeader, BCA types, generated constants). The protocol-types package is a thin bridge, not a reimplementation.

### E10: Generator validated against itself, not against source
The generator produced output, then tests checked that the output matched the generator's logic. No test actually validated that the generator's output matched the Forth source or typeHashRegistry.ts. **Fix**: Include literal expected values in test fixtures extracted directly from the source files. For example: `expect(constants.headerOffsets.typeHash.offset).toBe(30)` because `typeHashRegistry.ts` writes at offset 30. If the generator produces 32, the test must fail.

---

## Next Phase

Phase 0 output feeds directly into **Phase 1: Cell Packing in Zig**, which implements `packCell`, `unpackCell`, `packMultiCell`, `unpackMultiCell` using the constants and types established here.
