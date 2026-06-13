---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-7-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.675126+00:00
---

# Phase 7 Execution Prompt — Bun Bindings, Browser Loader, and FFI Spec

> Paste this prompt into a fresh session to execute Phase 7. The PRD is at `docs/prd/PHASE-7-BINDINGS.md` — read it first, then follow this prompt step by step.

---

## Context

You are working on `@semantos/core`, a Zig-compiled WASM engine for Bitcoin Script semantic objects. Phases 0–6 are complete:

- **Phase 0–1**: Cell packing (1KB cells, 256-byte headers, multi-cell continuations)
- **Phase 2**: BCA (Bitcoin Cellular Address) derivation and verification
- **Phase 3**: 2-PDA script executor with full opcode set, debug stepping, tx context
- **Phase 4**: Linearity enforcement (LINEAR, AFFINE, RELEVANT) and plexus opcodes
- **Phase 5**: BEEF/BUMP SPV verification, capability tokens, ECDSA via @bsv/sdk host functions
- **Phase 6**: Octave memory scaling — pointer cells (0x06), OP_DEREF_POINTER (0xC8), host_fetch_cell

The WASM binary exists in two profiles:
- **Full** (`zig-out/bin/cell-engine.wasm`, ~185KB): BSVZ native crypto + SPV
- **Embedded** (`zig-out/bin/cell-engine-embedded.wasm`, ~29KB): Crypto delegated to host functions

Current test counts: 300+ Zig native tests, 84+ Bun (TypeScript) tests. All passing.

## Your Task

Implement Phase 7: wrap the WASM binary in typed loaders and a CellEngine class so callers never touch raw pointers. Read the full PRD at `docs/prd/PHASE-7-BINDINGS.md` before writing any code.

## Critical Files to Read First

Before writing ANY code, read these files to understand the existing codebase:

```
docs/prd/PHASE-7-BINDINGS.md                          # The PRD — your source of truth
src/cell-engine/wasm-interface.ts                           # Current TypeScript interface (needs updating)
packages/cell-engine/bindings/host-functions.ts        # Shared host function implementations
packages/cell-engine/src/main.zig                      # All 29 WASM exports — the real contract
packages/cell-engine/tests-ts/octave_compat.test.ts    # Test pattern: WASM loading, MemoryProxy, host setup
packages/cell-engine/tests-ts/compat.test.ts           # Test pattern: cell pack/unpack cross-language
packages/cell-engine/tests-ts/kernel_compat.test.ts    # Test pattern: kernel export validation
packages/cell-engine/src/constants.zig                 # Cell sizes, header offsets, type constants
packages/constants/constants.json                      # Source of truth for shared constants
```

## Execution Steps

Follow this order exactly. Each step has a gate — do not proceed past a step until its gate passes.

---

### Step 1: Rename tests-ts/ → tests-bun/ (D7.0)

```bash
cd packages/cell-engine
mv tests-ts tests-bun
```

Update any references in config files or imports. Then run:

```bash
cd ../.. && bun test packages/cell-engine/tests-bun/
```

**Gate**: All 84+ existing tests pass from the new directory. Zero failures.

---

### Step 2: Update wasm-interface.ts (D7.1)

Edit `src/cell-engine/wasm-interface.ts`:

1. **Add `host_fetch_cell` to `PlexusKernelHostImports`** (P7.0.1):
   ```typescript
   host_fetch_cell(octave: number, slot: number, offset: number, outPtr: number): number;
   ```

2. **Add 15 missing exports to `PlexusKernelWasm`** (P7.0.2). Cross-reference every `export fn` in `packages/cell-engine/src/main.zig`. The interface must declare all 29 exports. Missing ones include:
   - `cell_pack`, `cell_unpack`, `cell_validate_magic`
   - `multicell_pack`, `multicell_unpack`
   - `bca_derive`, `bca_verify`
   - `kernel_step`, `kernel_get_pc`, `kernel_get_current_op`
   - `kernel_alt_stack_depth`, `kernel_alt_stack_peek`
   - `kernel_load_tx_context`, `kernel_set_enforcement`
   - `kernel_verify_beef_spv?` (full profile only)

3. **Add Phase 6 error codes to `KernelError`** (P7.0.3):
   ```typescript
   INVALID_POINTER_CELL = 41,
   HOST_FETCH_FAILED = 42,
   ```

4. Update the `loadKernel` function's `requiredExports` array to include the new required exports. SPV exports and `kernel_verify_beef_spv` remain optional (full profile only).

**Gate**: `bun test packages/cell-engine/tests-bun/` still passes. The interface is a TypeScript file — it doesn't change runtime behavior, but it must compile cleanly and the existing `loadKernel` validation must still work.

---

### Step 3: Bun Loader (D7.2)

Create `packages/cell-engine/bindings/bun/loader.ts`.

Key requirements:
- Use `Bun.file()` for WASM loading (not `readFileSync`)
- Accept `BunLoadOptions` with optional `wasmPath`, `profile`, `hostContext`, `cellStore`
- Default WASM path: resolve relative to package root (`../../../zig-out/bin/cell-engine.wasm` for full, `cell-engine-embedded.wasm` for embedded)
- Import `createHostFunctions` from `../host-functions` (shared — do NOT duplicate)
- Validate exports per profile after instantiation
- Return a `CellEngine` instance

Create `packages/cell-engine/bindings/bun/index.ts` as barrel:
```typescript
export { loadCellEngine, type BunLoadOptions } from './loader';
export { CellEngine } from './cell-engine';
```

Write tests in `packages/cell-engine/tests-bun/loader.test.ts`:
- `loadCellEngine()` returns CellEngine with full profile
- `loadCellEngine({ profile: 'embedded' })` returns CellEngine with embedded profile
- Missing required export throws descriptive error
- Profile-specific validation: full has SPV exports, embedded doesn't

**Gate**: `bun test packages/cell-engine/tests-bun/loader.test.ts` — all loader tests pass.

---

### Step 4: CellEngine Tier A (D7.3)

Create `packages/cell-engine/bindings/bun/cell-engine.ts`.

This is the core deliverable. The CellEngine class hides ALL pointer arithmetic. Study how existing tests write bytes into WASM memory — look at the `MemoryProxy` pattern in `octave_compat.test.ts` and the direct memory writes in `compat.test.ts`.

For every method:
1. Accept typed arguments (Uint8Array, typed objects)
2. Allocate space in WASM linear memory (write input bytes)
3. Call the raw WASM export
4. Read result bytes from WASM memory
5. Return typed result

Critical patterns:
- **Memory writes**: `new Uint8Array(this.memory.buffer, ptr, len).set(inputBytes)`
- **Memory reads**: `new Uint8Array(this.memory.buffer, ptr, len).slice()` (slice to copy — buffer may detach on next call)
- **Error handling**: Check return codes against `KernelError` enum, throw descriptive TypeScript errors
- **Profile guards**: SPV methods (`verifyBEEF`, `verifyBEEFWithSPV`, `verifyBUMP`, `beefVersion`) throw `Error('SPV not available in embedded profile')` when `this.profile === 'embedded'`

The constructor receives raw WASM exports and the profile string. It calls `kernel_init()` internally.

Implement ALL Tier A methods listed in the PRD:
- Cell: `packCell`, `unpackCell`, `validateMagic`
- Multi-cell: `packMultiCell`, `unpackMultiCell`
- BCA: `deriveBCA`, `verifyBCA`
- Script execution: `executeScript`, `step`, `getPC`, `getCurrentOp`, `checkLinearity`, `setEnforcement`
- Stack: `stackDepth`, `stackPeek`, `altStackDepth`, `altStackPeek`
- Tx context: `loadTxContext`
- SPV: `verifyBEEF`, `verifyBEEFWithSPV`, `verifyBUMP`, `beefVersion`
- Capability: `verifyCapability`
- Kernel: `kernelInit`, `kernelReset`, `kernelGetOpcount`, `kernelGetError`

Write tests in `packages/cell-engine/tests-bun/cell-engine.test.ts`:
- `packCell` → `unpackCell` round-trip matches
- `deriveBCA` returns typed `BCAOutput`
- `executeScript` with `[OP_TRUE]` returns success
- `executeScript` with `[OP_1, OP_1, OP_ADD]` → `stackPeek(0)` returns `[2]`
- `step()` advances PC correctly
- `verifyBEEF` on embedded profile throws
- `verifyCapability` with known-good script returns success

**Gate**: `bun test packages/cell-engine/tests-bun/cell-engine.test.ts` — all Tier A tests pass.

---

### Step 5: CellEngine Tier B — Octave (D7.3)

Add Tier B methods to the same CellEngine class:
- `createPointerCell(payload: PointerPayload)` — builds a 1KB cell with continuation type 0x06 and the 90-byte PointerPayload wire format (see `packages/cell-engine/src/pointer.zig` for layout)
- `parsePointerCell(cell: Uint8Array)` — extracts PointerPayload from a pointer cell
- `isPointerCell(cell: Uint8Array)` — checks continuation type byte
- `derefPointer(pointerCell: Uint8Array)` — pushes the pointer cell onto the stack, executes OP_DEREF_POINTER (0xC8), returns the fetched cell

The pointer cell wire layout (from `pointer.zig`):
```
Continuation header: 8 bytes [sequence:u16, type:u8=0x06, reserved:5]
PointerPayload: 90 bytes
  [0]    octave: u8
  [1..2] slot: u16 LE
  [3..6] offset: u32 LE
  [7]    _pad: u8
  [8..39]  content_hash: [32]u8
  [40..71] type_hash: [32]u8
  [72..79] total_size: u64 LE
  [80]   flags: u8
  [81..82] fragment_count: u16 LE
  [83..89] reserved: [7]u8
Padding: 926 zero bytes
```

Write tests (add to `cell-engine.test.ts` or a new `octave-engine.test.ts`):
- `createPointerCell` → `isPointerCell` returns true
- `createPointerCell` → `parsePointerCell` round-trips
- `derefPointer` with seeded cell store returns expected data

**Gate**: Octave tests pass. All previous tests still pass.

---

### Step 6: Browser Loader (D7.4)

Create `packages/cell-engine/bindings/browser/loader.ts`.

Same API as Bun loader but:
- Accept `wasmUrl` (string URL) instead of `wasmPath` (filesystem path)
- Use `fetch(wasmUrl)` + `WebAssembly.instantiateStreaming(response, imports)`
- Fallback: `WebAssembly.instantiate(await response.arrayBuffer(), imports)` for environments without streaming
- Import `createHostFunctions` from `../host-functions` (same shared file)
- Return the same `CellEngine` class (it's runtime-agnostic)

Create `packages/cell-engine/bindings/browser/index.ts` as barrel.

Browser tests are stretch goal — they require a test runner like Playwright. If feasible, create `packages/cell-engine/tests-browser/loader.test.ts`. If not, document the skip and why.

**Gate**: Browser loader compiles with `tsc --noEmit`. If Playwright is set up, browser test passes.

---

### Step 7: FFI Spec (D7.5)

Create `packages/cell-engine/bindings/ffi-spec.md`.

Document all 29 WASM exports grouped by phase. For each export:
- Function name
- Parameters with types (using C-like notation: `i32`, `i64`, `ptr`)
- Return type
- Brief description
- Which profile(s) it's available in

Document all 9 host imports with the same detail.

Document the memory model:
- WASM linear memory is exported as `memory`
- Callers allocate by writing to known offsets (the WASM module manages its own heap)
- 1KB cell buffers, 256-byte header buffers
- Results are written to caller-provided output pointers

Include minimal loader examples:
- Python (wasmtime-py): ~20 lines showing load → instantiate → call kernel_init → execute script
- Rust (wasmer): ~20 lines showing the same

**Gate**: The spec is complete and internally consistent. Every export in `main.zig` is documented.

---

### Step 8: Integration Tests (D7.6)

Create `packages/cell-engine/tests-bun/integration.test.ts`.

This is the end-to-end test through the CellEngine API with real infrastructure:

```typescript
import { loadCellEngine } from '../bindings/bun';
import { Database } from 'bun:sqlite';
import { PrivateKey, PublicKey, Hash, Signature } from '@bsv/sdk';
```

Tests:
1. **LINEAR lifecycle**: Create LINEAR cell via `engine.packCell()`, store in SQLite, query back, `engine.unpackCell()`, verify linearity via `engine.checkLinearity()`.

2. **AFFINE vote**: Create AFFINE object, consume it (mark as spent in SQLite), attempt second consumption → rejected.

3. **Capability token**: Build a capability locking script, verify through `engine.verifyCapability()` with valid params → success, expired time → failure, wrong domain → failure.

4. **Real CHECKSIG** (Gate 4 — critical):
   - Generate keypair with `@bsv/sdk` PrivateKey
   - Create a P2PKH locking script: `OP_DUP OP_HASH160 <pubkeyHash> OP_EQUALVERIFY OP_CHECKSIG`
   - Create unlock script: `<sig> <pubkey>`
   - Sign a 32-byte message hash with the private key
   - Execute through `engine.executeScript(lockScript, unlockScript)`
   - Assert success (returns 0, not stub failure)
   - This MUST use the embedded profile so CHECKSIG goes through host_checksig → @bsv/sdk

5. **BSV testnet** (conditional):
   ```typescript
   if (!process.env.BSV_TESTNET_KEY) {
     console.log('SKIPPED: BSV_TESTNET_KEY not set');
     return;
   }
   ```
   If key is set: broadcast real tx, get BEEF, verify through `engine.verifyBEEF()`.

**Gate**: `bun test packages/cell-engine/tests-bun/integration.test.ts` — all tests pass (testnet skips cleanly if no key).

---

### Step 9: Final Verification

Run the full test suite:

```bash
# Zig native tests (should still be 300+)
cd packages/cell-engine && zig build test 2>&1 | tail -5

# All Bun tests (should be 84+ existing + new loader/cell-engine/integration tests)
cd ../.. && bun test packages/cell-engine/tests-bun/

# WASM size check
ls -la packages/cell-engine/zig-out/bin/*.wasm
```

Verify:
- Zero Zig test regressions
- Zero Bun test regressions
- All new tests pass
- WASM sizes unchanged (~185KB full, ~29KB embedded)
- `wasm-interface.ts` declares all 29 exports and 9 imports
- No raw WASM pointers leak through CellEngine public API

---

## Rules

1. **Read the PRD first.** `docs/prd/PHASE-7-BINDINGS.md` is the source of truth. This prompt is the execution plan.
2. **No mocks in production paths.** Integration tests use real SQLite, real @bsv/sdk, real WASM. Testnet tests skip cleanly if no key.
3. **No pointer leaks.** Every public CellEngine method accepts and returns typed objects or Uint8Array. Raw numbers (pointers) stay internal.
4. **Shared host-functions.ts.** Both loaders import from `bindings/host-functions.ts`. Do NOT duplicate.
5. **Profile guards.** SPV methods throw on embedded profile. Don't silently return false.
6. **Don't touch Zig.** Phase 7 is TypeScript only. The WASM binary is frozen from Phase 6.
7. **Don't add deferred items.** No CellRegistry, no storeWithEscalation, no fetchByTypeHash. See "Deferred to Phase 8+" in the PRD.
8. **Test existing before writing new.** Run `bun test` after every step to catch regressions immediately.
9. **Slice on read.** When reading from WASM memory, always `.slice()` the Uint8Array. The underlying buffer detaches on the next WASM call.
10. **Cross-reference main.zig.** If you're unsure about an export's signature, read the actual Zig source. The PRD summarizes; `main.zig` is ground truth.
