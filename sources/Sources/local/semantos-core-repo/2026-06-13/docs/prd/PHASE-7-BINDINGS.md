---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-7-BINDINGS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.679932+00:00
---

# Phase 7: Bun Bindings, Browser Loader, and FFI Spec

**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 6 complete — octave memory scaling working, pointer cells packing/unpacking, OP_DEREF_POINTER operational. Phase 5 errata assessed.
**Previously**: Phase 6 (renumbered after octave memory insertion)

---

## Why This Phase Changed

The original Phase 6 was "TypeScript Bindings and Bun Integration." That conflated two things. The WASM binary is the product. The "bindings" are thin loaders that instantiate it and wire up host functions. Those loaders are runtime-specific, not language-specific:

- **Bun** — for Oddjobz and any Bun/Node server. Uses `Bun.file()`, Bun-optimized WASM instantiation.
- **Browser** — for client-side verification (browser extension, web app). Uses `fetch()` + `WebAssembly.instantiateStreaming()`.
- **Everything else** — Python, Go, Rust, C. They get the WASM binary + an FFI spec document. They write their own loader.

The current `host-functions.ts` and `wasm-interface.ts` are generic TypeScript — no Bun APIs, no browser APIs. They'd run identically in Node, Deno, or Bun. Phase 7 makes them runtime-aware.

---

## Phase 5 Errata Assessment

Phase 5 left four gaps. Their status determines how Phase 7 proceeds.

### E-P5.1 — host_checksig and host_checkmultisig — RESOLVED

`bindings/host-functions.ts` now implements real ECDSA verification via `@bsv/sdk` PublicKey.verify() and Signature.fromDER(). The embedded profile has working signature verification. Multi-sig follows BSV consensus sequential verification. No action needed.

### E-P5.2 — GullibleChainTracker — DOCUMENTED LIMITATION

`src/beef.zig` uses BSVZ's tracker which accepts any merkle root. Real SPV needs a header chain oracle (Phase 8+ infrastructure). Documented as "format validation only, not SPV" — the separate `kernel_verify_beef_spv()` export accepts caller-supplied trusted roots for real SPV. No action needed for Phase 7.

### E-P5.3 — Embedded native HASH160 — DOCUMENTED LIMITATION (not gating)

`src/host.zig` embedded native path returns truncated SHA256D instead of real HASH160. This affects only native Zig test builds. The embedded WASM path correctly delegates to `host_hash160` in host-functions.ts which uses `@bsv/sdk` Hash.hash160(). Since Phase 7 loaders operate exclusively in WASM mode, this does not gate any deliverable.

### E-P5.4 — Embedded native CHECKSIG stub — DOCUMENTED LIMITATION (not gating)

`src/host.zig` native path returns false for any signature. The embedded WASM path delegates to host_checksig (resolved by E-P5.1). Native embedded testing can't verify signatures — same known limitation as Phase 6 (BUG-5). Does not gate Phase 7.

**Verdict**: E-P5.1 is resolved. E-P5.2/3/4 are documented limitations that don't affect WASM-side correctness. Phase 7 proceeds without blocking on them.

---

## Pre-Phase 7: Interface Updates (Must Complete First)

Before writing loaders, the TypeScript interface contract must match reality.

### P7.0.1 — Add host_fetch_cell to PlexusKernelHostImports

The `wasm-interface.ts` `PlexusKernelHostImports` interface lists 8 host functions but is missing `host_fetch_cell` from Phase 6. Add:

```typescript
/** Fetch a 1KB chunk from a higher-octave cell. Returns 1 on success, 0 on failure. */
host_fetch_cell(octave: number, slot: number, offset: number, outPtr: number): number;
```

### P7.0.2 — Add missing WASM exports to PlexusKernelWasm

The actual WASM binary exports 29 functions. `PlexusKernelWasm` only declares 14. Add the missing exports that are present in both profiles:

```typescript
// Phase 1: Cell packing (both profiles)
cell_pack(headerPtr: number, payloadPtr: number, payloadLen: number, outPtr: number): number;
cell_unpack(cellPtr: number, headerOutPtr: number, payloadOutPtr: number): number;
cell_validate_magic(cellPtr: number): number;

// Phase 1: Multi-cell packing (both profiles)
multicell_pack(headerPtr: number, payloadPtr: number, payloadLen: number,
  contTypesPtr: number, contOffsetsPtr: number, contSizesPtr: number,
  contDataPtr: number, contCount: number, outPtr: number): number;
multicell_unpack(bufferPtr: number, bufferLen: number): number;

// Phase 2: BCA (both profiles)
bca_derive(pubkeyPtr: number, prefixPtr: number, modifierPtr: number,
  sec: number, outPtr: number): number;
bca_verify(addrPtr: number, pubkeyPtr: number, prefixPtr: number,
  modifierPtr: number): number;

// Phase 3: Debug/stepping (both profiles)
kernel_step(): number;
kernel_get_pc(): number;
kernel_get_current_op(): number;
kernel_alt_stack_depth(): number;
kernel_alt_stack_peek(index: number): number;
kernel_load_tx_context(txPtr: number, txLen: number, inputIndex: number, inputValue: bigint): number;
kernel_set_enforcement(enabled: number): void;

// Phase 5: SPV with trusted roots (full profile only)
kernel_verify_beef_spv?(beefPtr: number, beefLen: number, txidPtr: number,
  rootsPtr: number, rootsCount: number): number;
```

### P7.0.3 — Add Phase 6 error codes to KernelError enum

```typescript
INVALID_POINTER_CELL = 41,
HOST_FETCH_FAILED = 42,
```

---

## D7.0 — Rename tests-ts/ to tests-bun/ (Do First)

The tests run on `bun test`. Call them what they are. This is step 0 so all new test files land in the right directory from the start.

- Rename `packages/cell-engine/tests-ts/` → `packages/cell-engine/tests-bun/`
- Update any import paths or config that references `tests-ts`
- Verify `bun test` still passes after rename

---

## Directory Structure (Target)

```
packages/cell-engine/
├── src/                          # Zig source (unchanged)
├── zig-out/
│   ├── cell-engine.wasm          # Full profile (BSVZ, ~185KB)
│   └── cell-engine-embedded.wasm # Embedded profile (~29KB)
│
├── bindings/
│   ├── host-functions.ts         # SHARED: @bsv/sdk host implementations (both loaders import this)
│   ├── bun/
│   │   ├── loader.ts             # Bun-native WASM loader (Bun.file())
│   │   ├── cell-engine.ts        # Typed API wrapper (CellEngine class)
│   │   └── index.ts              # Barrel export
│   │
│   ├── browser/
│   │   ├── loader.ts             # Browser WASM loader (fetch + instantiateStreaming)
│   │   └── index.ts              # Barrel export
│   │
│   └── ffi-spec.md               # For non-JS runtimes: export signatures,
│                                 #   memory model, host import contract
│
├── tests-bun/                    # Renamed from tests-ts/
│   ├── __tests__/wasm-build.test.ts  # WASM binary validation (existing)
│   ├── compat.test.ts            # Phase 1 cell packing (existing)
│   ├── bca_compat.test.ts        # BCA compatibility (existing)
│   ├── kernel_compat.test.ts     # Kernel function exports (existing)
│   ├── linearity_compat.test.ts  # Linearity compatibility (existing)
│   ├── spv_integration.test.ts   # SPV integration (existing)
│   ├── capability_compat.test.ts # Capability compat (existing)
│   ├── checksig_integration.test.ts # Crypto (existing)
│   ├── octave_compat.test.ts     # Octave memory (existing)
│   ├── loader.test.ts            # NEW: Bun loader tests
│   ├── cell-engine.test.ts       # NEW: CellEngine typed API tests
│   └── integration.test.ts       # NEW: Full lifecycle with real SQLite
│
└── tests-browser/                # NEW: Browser loader tests (playwright or similar)
    └── loader.test.ts
```

**Note**: `host-functions.ts` stays at `bindings/host-functions.ts` as shared code. Both `bun/loader.ts` and `browser/loader.ts` import from it. Only the WASM loading mechanism and runtime-specific APIs differ between loaders.

---

## Deliverables

### D7.1 — Update wasm-interface.ts (P7.0.1 through P7.0.3)

Apply all three interface updates. This is gating — the CellEngine class types derive from this interface.

### D7.2 — Bun-native WASM loader (`bindings/bun/loader.ts`)

```typescript
import type { PlexusKernelWasm } from '../../../src/cell-engine/wasm-interface';
import { createHostFunctions, type ScriptContext, type OctaveCellStore } from '../host-functions';

export interface BunLoadOptions {
  wasmPath?: string;            // Default: resolve from package
  profile?: 'full' | 'embedded'; // Default: 'full'
  hostContext?: ScriptContext;
  cellStore?: OctaveCellStore;  // Per-instance octave cell store
}

export async function loadCellEngine(options?: BunLoadOptions): Promise<CellEngine> {
  // Use Bun.file() for WASM loading — faster than fs.readFile
  const wasmFile = Bun.file(wasmPath);
  const wasmBytes = await wasmFile.arrayBuffer();

  const { instance } = await WebAssembly.instantiate(wasmBytes, {
    host: hostFunctions,
  });

  validateExports(instance.exports, options?.profile ?? 'full');
  return new CellEngine(instance.exports as unknown as PlexusKernelWasm, options?.profile ?? 'full');
}
```

Must handle: profile selection (full vs embedded WASM binary), export validation per profile (SPV exports optional in embedded), automatic WASM path resolution from package root, per-instance octave cell store passthrough.

### D7.3 — CellEngine typed API wrapper (`bindings/bun/cell-engine.ts`)

Split into two tiers:

#### Tier A — Wraps existing WASM exports (all present in main.zig today)

```typescript
export class CellEngine {
  // ── Cell operations (Phase 1) ──
  packCell(header: CellHeader, payload: Uint8Array): Uint8Array;
  unpackCell(cell: Uint8Array): { header: CellHeader; payload: Uint8Array; payloadLen: number };
  validateMagic(cell: Uint8Array): boolean;

  // ── Multi-cell operations (Phase 1) ──
  packMultiCell(header: CellHeader, payload: Uint8Array, continuations: ContinuationInput[]): Uint8Array;
  unpackMultiCell(buffer: Uint8Array): number; // returns cell count

  // ── BCA operations (Phase 2) ──
  deriveBCA(input: BCAInput): BCAOutput;
  verifyBCA(address: Uint8Array, input: BCAInput): boolean;

  // ── Script execution (Phase 3) ──
  executeScript(lockScript: Uint8Array, unlockScript?: Uint8Array): ScriptResult;
  step(): StepResult;
  getPC(): number;
  getCurrentOp(): number;
  checkLinearity(): TypeClassification;
  setEnforcement(enabled: boolean): void;

  // ── Stack inspection (Phase 3) ──
  stackDepth(): number;
  stackPeek(index: number): Uint8Array | null;
  altStackDepth(): number;
  altStackPeek(index: number): Uint8Array | null;

  // ── Transaction context (Phase 3) ──
  loadTxContext(rawTx: Uint8Array, inputIndex: number, inputValue: bigint): void;

  // ── SPV verification (Phase 5 — full profile only, throws on embedded) ──
  verifyBEEF(beefBytes: Uint8Array, txid: Uint8Array): VerifyResult;
  verifyBEEFWithSPV(beefBytes: Uint8Array, txid: Uint8Array, trustedRoots: Uint8Array[]): VerifyResult;
  verifyBUMP(proofBytes: Uint8Array, txid: Uint8Array, merkleRoot: Uint8Array): VerifyResult;
  beefVersion(data: Uint8Array): BeefVersion;

  // ── Capability tokens (Phase 5 — both profiles) ──
  verifyCapability(lockScript: Uint8Array, ownerPubkey: Uint8Array,
                   capType: number, domainFlag: number, currentTime: number): VerifyResult;

  // ── Kernel interface (low-level, for advanced callers) ──
  kernelInit(): void;
  kernelReset(): void;
  kernelGetOpcount(): number;
  kernelGetError(): string;

  // ── Profile info ──
  readonly profile: 'full' | 'embedded';
  readonly memory: WebAssembly.Memory;
}
```

#### Tier B — Octave convenience methods (TypeScript-side, uses host_fetch_cell + WASM memory)

These methods compose existing primitives. They do NOT require new WASM exports.

```typescript
  // ── Octave memory (Phase 6) ──
  // Pointer cell pack/unpack runs through cell_pack/cell_unpack with
  // continuation type 0x06 and the 90-byte PointerPayload wire format.
  createPointerCell(payload: PointerPayload): Uint8Array;
  parsePointerCell(cell: Uint8Array): PointerPayload;
  isPointerCell(cell: Uint8Array): boolean;
  derefPointer(pointerCell: Uint8Array): Uint8Array;
  // Executes OP_DEREF_POINTER (0xC8) through executeScript internally.
```

**Deferred to Phase 8+** (requires storage backend that doesn't exist yet):
- ~~storeWithEscalation(data, typeHash)~~
- ~~fetchByTypeHash(typeHash)~~
- ~~fetchByAddress(addr)~~
- ~~CellRegistry with CAS + location addressing~~

Critical rules:
- All pointer writes (copying Uint8Array into WASM memory) happen inside this class only
- All pointer reads (extracting results from WASM memory) happen inside this class only
- SPV methods throw a clear error if called on embedded profile
- Types come from `@semantos/protocol-types`, not redefined locally

### D7.4 — Browser WASM loader (`bindings/browser/loader.ts`)

Same API surface as Bun loader but uses:
- `fetch()` + `WebAssembly.instantiateStreaming()` for WASM loading
- No `Bun.file()`, no `bun:sqlite`, no Node/Bun-specific APIs
- Browser-compatible `@bsv/sdk` imports (the SDK supports browser builds)
- Must work in: Chrome extensions (MV3 service worker), web apps, iframes

**Octave cell store strategy**: Same in-memory `OctaveCellStore` (Map<string, Uint8Array>) as Bun. The browser caller is responsible for populating the store before executing scripts that dereference pointer cells. The loader accepts an optional `cellStore` parameter — if not provided, creates a fresh empty store. No IndexedDB or remote CAS in Phase 7.

Returns `CellEngine` with identical API to the Bun loader. The `CellEngine` class itself is runtime-agnostic — only the loader differs.

### D7.5 — FFI specification document (`bindings/ffi-spec.md`)

For non-JS runtimes (Python, Go, Rust, C). Documents:
- All 29 WASM exports: function name, parameter types, return type, semantics
- All 9 WASM imports (host functions): function name, parameter types, when called
- Memory model: linear memory layout, how to allocate/write/read buffers
- Profile differences: which exports are present in full vs embedded
- Error codes: complete KernelError enum with descriptions
- Example: minimal Python loader using wasmtime-py
- Example: minimal Rust loader using wasmer

### D7.6 — Integration tests with real infrastructure

```typescript
// tests-bun/integration.test.ts
describe('Full semantic object lifecycle', () => {
  // Real Bun SQLite (bun:sqlite), real CellEngine, real @bsv/sdk

  test('LINEAR object: create → pack → store → query → verify', () => { ... });
  test('AFFINE vote: create → consume → reject double consume', () => { ... });
  test('Capability token: verify valid → verify expired → verify wrong domain', () => { ... });
  test('CHECKSIG: sign with @bsv/sdk → verify through CellEngine', () => { ... });

  // Conditional testnet tests
  test('BSV testnet: anchor → BEEF → verify BUMP', () => {
    if (!process.env.BSV_TESTNET_KEY) {
      console.log('SKIPPED: BSV_TESTNET_KEY not set');
      return;
    }
    // Real transaction, real BEEF, real BUMP — through CellEngine API
  });
});
```

No mocks. Real SQLite, real WASM engine, real @bsv/sdk. Skip testnet if no key.

---

## TDD Gate — Tests That Must Pass

### Gate 0: Interface contract
- `wasm-interface.ts` PlexusKernelWasm lists all 29 WASM exports
- `wasm-interface.ts` PlexusKernelHostImports lists all 9 host functions (including host_fetch_cell)
- KernelError enum includes Phase 6 error codes (41, 42)
- Existing Phase 0-6 tests still pass (84+ TS, 300+ Zig, 0 new failures)

### Gate 1: WASM loading (Bun)
- loadCellEngine() returns CellEngine instance (full profile)
- loadCellEngine({ profile: 'embedded' }) returns CellEngine instance
- Export validation catches missing exports
- Profile-specific validation: full profile has SPV exports, embedded doesn't

### Gate 2: Typed API — Tier A
- packCell accepts CellHeader + payload, returns 1024-byte Uint8Array
- unpackCell round-trips correctly
- deriveBCA accepts typed input, returns typed output
- executeScript runs OP_TRUE, returns success
- verifyBEEF throws on embedded profile with clear message
- stackDepth/stackPeek work after executeScript

### Gate 3: Typed API — Tier B (Octave)
- createPointerCell produces valid pointer cell (verifiable by isPointerCell)
- parsePointerCell round-trips with createPointerCell
- derefPointer fetches from octave cell store through host_fetch_cell

### Gate 4: Real CHECKSIG through CellEngine
- Sign a message with @bsv/sdk PrivateKey
- Build a P2PKH locking script
- Execute through CellEngine.executeScript()
- Verify the signature validates (returns success, not stub failure)

### Gate 5: Integration with real SQLite
- Create LINEAR object, store in bun:sqlite, query matches
- Attempt double-spend of LINEAR object, rejected by linearity check

### Gate 6: End-to-end BSV testnet (conditional)
- Full lifecycle or explicit skip with message
- No mocks, no fakes — real testnet or real skip

### Gate 7: Browser loader
- loadCellEngine() works via fetch + instantiateStreaming (playwright test)
- CellEngine API surface identical to Bun loader

---

## Phase Completion Criteria

Phase 7 is done when ALL of the following are true:

1. `wasm-interface.ts` matches actual WASM exports (29 exports, 9 imports, Phase 6 error codes)
2. `tests-ts/` renamed to `tests-bun/`
3. `loadCellEngine()` loads WASM in Bun (both profiles)
4. Browser loader loads WASM via fetch/instantiateStreaming
5. CellEngine class (Tier A) hides all pointer arithmetic — typed API only
6. CellEngine class (Tier B) provides octave convenience methods
7. FFI spec document enables a non-JS runtime to load the WASM
8. Real CHECKSIG works end-to-end: @bsv/sdk sign → CellEngine verify
9. Integration tests pass with real bun:sqlite
10. Testnet test passes or explicitly skips
11. All Phase 0-6 tests still pass
12. `bun test` passes all gates

---

## Execution Order

Recommended sequence (respects dependency chain):

1. **D7.0** — Rename tests-ts/ → tests-bun/ (clean foundation)
2. **D7.1** — Update wasm-interface.ts (P7.0.1-P7.0.3)
3. **D7.2** — Bun loader (depends on D7.1 types)
4. **D7.3 Tier A** — CellEngine wrapping existing exports
5. **D7.3 Tier B** — Octave convenience methods
6. **D7.4** — Browser loader (reuses CellEngine class + host-functions.ts)
7. **D7.5** — FFI spec (documents what D7.1-D7.4 implemented)
8. **D7.6** — Integration tests (exercises D7.2-D7.4)

---

## What NOT To Do

- Do not write generic TypeScript that ignores runtime capabilities — use Bun.file() in Bun, fetch() in browser
- Do not expose raw WASM pointers in the CellEngine public API
- Do not mock SQLite, CHECKSIG, or BSV testnet — real or skip
- Do not duplicate types — import from @semantos/protocol-types
- Do not bundle @bsv/sdk inside WASM — it stays in the host runtime
- Do not "pass" tests by testing stubs — Gate 4 requires a real signature through the engine
- Do not create a single loader that branches on typeof window — separate files, separate entry points
- Do not duplicate host-functions.ts per loader — keep it shared at bindings/host-functions.ts
- Do not add storeWithEscalation, CellRegistry, or fetchByTypeHash — deferred to Phase 8+ (needs storage backend)
- Do not gate Phase 7 on E-P5.3/E-P5.4 native stub fixes — they don't affect WASM correctness

---

## What This Enables

After Phase 7, any Bun application (Oddjobz, future extensions) can:
```typescript
import { loadCellEngine } from '@semantos/cell-engine/bun';

const engine = await loadCellEngine();
const result = engine.verifyCapability(lockScript, ownerPub, capType, domainFlag, now);
```

Any browser extension or web app can:
```typescript
import { loadCellEngine } from '@semantos/cell-engine/browser';

const engine = await loadCellEngine({ wasmUrl: '/cell-engine.wasm' });
const beefValid = engine.verifyBEEF(beefBytes, txid);
```

Any Python, Go, Rust, or C application can read `ffi-spec.md` and write their own 20-line loader.

---

## Deferred to Phase 8+

The following were listed in earlier drafts but require infrastructure that doesn't exist yet:

| Item | Why Deferred | Dependency |
|------|-------------|------------|
| CellRegistry (CAS + location) | Needs persistent storage backend | Storage layer design |
| storeWithEscalation | Needs CellRegistry + octave storage | CellRegistry |
| fetchByTypeHash / fetchByAddress | Needs CellRegistry | CellRegistry |
| Real SPV chain tracker | Needs block header oracle | Header chain service |
| Native embedded HASH160 fix (E-P5.3) | Only affects native Zig tests | RIPEMD160 in Zig std or custom impl |
| Native embedded CHECKSIG fix (E-P5.4) | Only affects native Zig tests | Embedded ECDSA impl |

---

## Next Phase

Phase 7 output feeds into **Phase 8: CI/CD Pipeline and Performance Benchmarks**.
