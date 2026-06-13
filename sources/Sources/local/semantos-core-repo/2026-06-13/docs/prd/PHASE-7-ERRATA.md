---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-7-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.710818+00:00
---

# Phase 7 Errata — Bun Bindings, Browser Loader, FFI Spec

Audit of the Phase 7 implementation against `main.zig`, `pointer.zig`, and the Phase 7 PRD.

**Audited files**: `bindings/bun/cell-engine.ts`, `bindings/bun/loader.ts`, `bindings/bun/types.ts`, `bindings/browser/loader.ts`, `bindings/ffi-spec.md`, `tests-bun/loader.test.ts`, `tests-bun/cell-engine.test.ts`, `tests-bun/integration.test.ts`, `src/cell-engine/wasm-interface.ts`

---

## BUG-1: `packMultiCell` output clobbers IO_SCRIPT at 3+ continuations

**Severity**: BUG
**File**: `bindings/bun/cell-engine.ts`, lines 119–149
**Details**: `packMultiCell` writes its result to `IO_OUT` (0x300400). The output size is `(1 + count) * 1024` bytes. With 3 continuations, the output is 4096 bytes, ending at `0x301400` — which overlaps `IO_SCRIPT` (0x301000). With 12+ continuations, the output reaches `IO_SPV` (0x303000) where the continuation input data is stored, clobbering input while still being read.

**Fix**: Write the multicell output to a dedicated high-address region (e.g., `IO_MULTICELL_OUT = IO_BASE + 0x80000`) or compute it dynamically. The current IO layout doesn't have enough space between `IO_OUT` and `IO_SCRIPT` for multi-cell packing.

---

## BUG-2: `kernelGetError` returns raw WASM pointer, not string

**Severity**: BUG
**File**: `bindings/bun/cell-engine.ts`, lines 337–339
**Details**: The PRD specifies `kernelGetError(): string`. The WASM export `kernel_get_error()` returns a pointer to a null-terminated string in WASM linear memory. The CellEngine method returns this pointer as a `number`, which is exactly the kind of pointer leak the class is supposed to prevent.

**Fix**: Read the null-terminated string from WASM memory:
```typescript
kernelGetError(): string {
  const ptr = this.wasm.kernel_get_error();
  if (ptr === 0) return '';
  const mem = new Uint8Array(this.memory.buffer);
  let end = ptr;
  while (mem[end] !== 0 && end < mem.length) end++;
  return new TextDecoder().decode(mem.slice(ptr, end));
}
```

---

## BUG-3: Browser loader double-consumes Response on streaming fallback

**Severity**: BUG
**File**: `bindings/browser/loader.ts`, lines 88–101
**Details**: Line 88 starts `const response = fetch(...)` (unawaited Promise). Line 93 passes it to `WebAssembly.instantiateStreaming(response, ...)`. If streaming fails (e.g., wrong MIME type), line 97 does `const resp = await response` and then `resp.arrayBuffer()`. But `instantiateStreaming` may have already consumed the Response body, making `arrayBuffer()` throw "body already read."

**Fix**: Clone the response or re-fetch:
```typescript
const response = await fetch(options.wasmUrl);
try {
  const result = await WebAssembly.instantiateStreaming(
    Promise.resolve(response.clone()), importObject
  );
  instance = result.instance;
} catch {
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, importObject);
  instance = result.instance;
}
```

---

## BUG-4: `verifyBEEF` / `verifyBUMP` buffer overflow with large inputs

**Severity**: BUG
**File**: `bindings/bun/cell-engine.ts`, lines 264–293
**Details**: `verifyBEEF` writes `beefBytes` to `IO_SPV` (0x303000) then `txid` immediately after. `IO_TX` starts at 0x304000 — only 4096 bytes away. If `beefBytes.length > 3968` (4096 - 32 for txid), the txid write clobbers `IO_TX`. Similarly `verifyBUMP` writes proof + txid + merkle_root sequentially.

Real-world BEEF envelopes can easily exceed 4KB. `verifyBEEFWithSPV` also writes trusted roots after txid, compounding the issue.

**Fix**: Either add bounds checks that throw before writing, or allocate SPV data at a higher offset with more room (e.g., `IO_SPV = IO_BASE + 0x20000` with 128KB available).

---

## INCONSISTENCY-1: `packCell` accepts `Uint8Array` not structured `CellHeader`

**Severity**: INCONSISTENCY
**File**: `bindings/bun/cell-engine.ts`, line 86
**Details**: The PRD D7.3 declares `packCell(header: CellHeader, payload: Uint8Array)` where `CellHeader` is a structured interface with typed fields. The implementation accepts `header: Uint8Array` (pre-serialized 256 bytes). Callers must use `buildCellHeader()` from `typeHashRegistry.ts` to serialize first, which defeats part of the "typed API" goal.

**Fix**: Either accept both via overloading (`Uint8Array | CellHeader`), or add a `serializeHeader(header: CellHeader): Uint8Array` helper and call it internally. The test files already use `buildCellHeader` — this would remove that boilerplate.

---

## INCONSISTENCY-2: `deriveBCA` hardcodes `sec: 0`, ignoring BCA security parameter

**Severity**: INCONSISTENCY
**File**: `bindings/bun/cell-engine.ts`, line 165
**Details**: The Zig `bca_derive` export accepts a `sec: u8` parameter (0–31 security level). The CellEngine hardcodes `0`. The `BCAInput` type (from `protocol-types`) doesn't have a `sec` field, so there's no way for callers to control it through the typed API.

**Fix**: Add `sec?: number` to `BCAInput` interface and pass `input.sec ?? 0`.

---

## INCONSISTENCY-3: `stackPeek` returns 1024 bytes regardless of actual value length

**Severity**: INCONSISTENCY
**File**: `bindings/bun/cell-engine.ts`, lines 236–242
**Details**: The PDA tracks actual value length per stack slot in `main_lengths[]`. The WASM exports `kernel_stack_peek` which returns a pointer to the 1024-byte slot. The CellEngine reads all 1024 bytes, but the actual value may be 1–1024 bytes. There's no WASM export to get the value's length.

This means `stackPeek(0)` after pushing `OP_1` returns 1024 bytes where only byte[0] = 1 is meaningful and bytes[1..1023] are stale data from previous stack operations.

**Fix (Phase 8)**: Add `kernel_stack_peek_len(index: u32): u32` export to `main.zig` that returns `main_lengths[idx]`. Then `stackPeek` can return a correctly-sized `Uint8Array`. This requires a Zig change so it's out of scope for Phase 7 but should be tracked.

---

## INCONSISTENCY-4: Export validation duplicated across two loaders

**Severity**: TECH_DEBT
**File**: `bindings/bun/loader.ts` lines 33–50, `bindings/browser/loader.ts` lines 26–62
**Details**: `REQUIRED_EXPORTS`, `FULL_PROFILE_EXPORTS`, and `validateExports()` are copy-pasted identically between the Bun and browser loaders. If an export is added or removed, both files must be updated.

**Fix**: Extract validation into a shared module (e.g., `bindings/validation.ts`) imported by both loaders. The `loadKernel` function in `wasm-interface.ts` already has its own copy of the required exports list (3 copies total).

---

## INCONSISTENCY-5: `loadKernel` in `wasm-interface.ts` duplicates loader validation

**Severity**: TECH_DEBT
**File**: `src/cell-engine/wasm-interface.ts`, lines 420–454
**Details**: `loadKernel()` has its own `requiredExports` array (now 26 items) that matches the Bun/browser loaders' lists. Three places to update for any export change.

**Fix**: Either deprecate `loadKernel` (the Bun/browser loaders replace it) or have all three import from a shared list.

---

## INCONSISTENCY-6: FFI spec `kernel_load_tx_context` parameter type wrong

**Severity**: INCONSISTENCY
**File**: `bindings/ffi-spec.md`, line 39
**Details**: The FFI spec documents `input_value: i64` but the Zig signature is `input_value: u64` (unsigned). Satoshi values are always non-negative. The `PlexusKernelWasm` interface correctly uses `bigint`.

**Fix**: Change to `u64` in the FFI spec.

---

## INCONSISTENCY-7: FFI spec `kernel_step` return values incomplete

**Severity**: INCONSISTENCY
**File**: `bindings/ffi-spec.md`, line 34
**Details**: FFI spec says `kernel_step` returns `0=ok, 1=done, <0=error`. The actual `StepResult` enum is: `0=continue_execution, 1=done_true, 2=done_false, -1=done_error`. Missing `done_false = 2`.

**Fix**: Update FFI spec to document all four values.

---

## TECH_DEBT-1: No bounds checking on any `writeBytes` call

**Severity**: TECH_DEBT
**File**: `bindings/bun/cell-engine.ts`, line 71
**Details**: `writeBytes(ptr, data)` writes directly to WASM memory with no bounds check against the memory size (8MB) or against the IO region boundaries. Any method that writes user-supplied data (scripts, BEEF, tx context) could write out of bounds if the data is large enough.

**Fix**: Add a guard: `if (ptr + data.length > this.memory.buffer.byteLength) throw new Error(...)`. Also consider per-region bounds: script max = 64KB (IO_UNLOCK - IO_SCRIPT), BEEF max = documented limit, etc.

---

## TECH_DEBT-2: `derefPointer` depends on `OP_TRUE` staying at opcode 0x51

**Severity**: TECH_DEBT
**File**: `bindings/bun/cell-engine.ts`, line 436
**Details**: `derefPointer` builds a lock script `[0xC8, 0x51]` (OP_DEREF_POINTER + OP_1). It assumes OP_1 = 0x51 and that executing it leaves `[fetched_cell, 1]` on the stack. This is a hardcoded dependency on Bitcoin Script opcode assignments.

**Fix**: Define opcode constants (`OP_DEREF_POINTER = 0xC8`, `OP_1 = 0x51`) at the top of the file instead of magic numbers.

---

## TECH_DEBT-3: Integration test CHECKSIG doesn't prove the real ECDSA path ran

**Severity**: TECH_DEBT
**File**: `tests-bun/integration.test.ts`, lines 147–209
**Details**: The test builds a fake DER signature, executes OP_CHECKSIG, and expects `rc = 6` (VERIFY_FAILED). This proves the host function was *called* but not that it produced a *correct* result. A stub that always returns 0 would also produce `rc = 6`. The test comment acknowledges this: "combined with checksig_integration.test.ts... this confirms the embedded profile host path is correctly wired."

The real Gate 4 from the PRD says "Verify the signature validates (returns success, not stub failure)" — this test doesn't achieve that. A proper test requires computing the correct BIP-143 sighash for the test transaction and signing it with the private key.

**Fix**: Either implement proper BIP-143 sighash computation in the test (using `@bsv/sdk` Transaction + sign flow) to produce a valid signature, or document this as a known limitation and reference the checksig_integration test as partial coverage.

---

## TECH_DEBT-4: `IO_OUT2` is declared but never used

**Severity**: DEAD_CODE
**File**: `bindings/bun/cell-engine.ts`, line 35
**Details**: `const IO_OUT2 = IO_BASE + CELL_SIZE * 2` is declared but no method references it.

**Fix**: Remove it, or use it for `packMultiCell` output to avoid BUG-1.

---

## Summary

| ID | Severity | Impact | Effort |
|----|----------|--------|--------|
| BUG-1 | BUG | packMultiCell silently corrupts memory at 3+ continuations | Medium |
| BUG-2 | BUG | kernelGetError leaks raw pointer, doesn't return string | Low |
| BUG-3 | BUG | Browser loader fails on streaming fallback | Low |
| BUG-4 | BUG | SPV methods overflow at >4KB BEEF input | Medium |
| INCONSISTENCY-1 | INCONSISTENCY | packCell takes raw bytes not typed header | Medium |
| INCONSISTENCY-2 | INCONSISTENCY | BCA sec parameter not exposed | Low |
| INCONSISTENCY-3 | INCONSISTENCY | stackPeek returns 1024 bytes not actual length | Medium (Phase 8) |
| INCONSISTENCY-4 | TECH_DEBT | Validation lists duplicated across 3 files | Low |
| INCONSISTENCY-5 | TECH_DEBT | loadKernel duplicates loader validation | Low |
| INCONSISTENCY-6 | INCONSISTENCY | FFI spec i64 should be u64 | Trivial |
| INCONSISTENCY-7 | INCONSISTENCY | FFI spec missing StepResult value 2 | Trivial |
| TECH_DEBT-1 | TECH_DEBT | No bounds checks on writeBytes | Medium |
| TECH_DEBT-2 | TECH_DEBT | Hardcoded opcode magic numbers | Low |
| TECH_DEBT-3 | TECH_DEBT | CHECKSIG test doesn't prove valid signature | Medium |
| TECH_DEBT-4 | DEAD_CODE | IO_OUT2 unused | Trivial |

**4 bugs, 7 inconsistencies, 4 tech debt/dead code items.**

**Must-fix before Phase 8**: BUG-1, BUG-2, BUG-3, BUG-4 (all affect correctness or will cause runtime failures).

**Should-fix**: INCONSISTENCY-4/5 (DRY), INCONSISTENCY-6/7 (FFI spec accuracy), TECH_DEBT-4 (dead code).

**Phase 8 candidates**: INCONSISTENCY-1 (typed header API), INCONSISTENCY-3 (stack peek length export), TECH_DEBT-3 (real CHECKSIG test).
