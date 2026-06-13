---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-6-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.709192+00:00
---

# Phase 6 Prompt

**STATUS: NOT STARTED**
**Architecture: Bun-native + Browser loaders, Phase 5 errata remediation first**

Copy everything below the line into a fresh Claude Code session.

---

## Prompt Start

Read these documents in full before producing any output:

1. `/Users/toddprice/projects/semantos-core/docs/prd/README.md`
2. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-6-BINDINGS.md` — the specification for this phase. Read it completely.
3. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-5-PROMPT.md` — read the **Embedded host runtime options** section and the **dual profile architecture** section for context on how the two WASM binaries differ.
4. `/Users/toddprice/projects/semantos-core/docs/prd/PHASE-4-PLEXUS-OPCODES.md` — read the **Post-Implementation Errata** for context on Plexus opcodes.

Then read these source files — existing code you'll modify or replace:

5. `/Users/toddprice/projects/semantos-core/packages/cell-engine/bindings/host-functions.ts` — Current host function implementations. **E-P5.1**: `host_checksig` and `host_checkmultisig` are stubs returning 0. You must implement them with real `@bsv/sdk` ECDSA before anything else.
6. `/Users/toddprice/projects/semantos-core/packages/cell-engine/bindings/index.ts` — Current stub barrel export. Will be replaced by runtime-specific entry points.
7. `/Users/toddprice/projects/semantos-core/src/cell-engine/wasm-interface.ts` — `PlexusKernelWasm` interface, `PlexusKernelHostImports`, `loadKernel()`, `KernelError` enum. The CellEngine class must satisfy `PlexusKernelWasm`. Do not break this interface.

Then read these source files — Zig engine code you need to understand but will NOT modify (except for errata fixes):

8. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/host.zig` — Zig host function dispatch. **E-P5.3**: embedded native HASH160 is fake (truncated SHA256D, not real RIPEMD160). **E-P5.4**: embedded native CHECKSIG stub returns false. Understand the `comptime embedded` toggle. The Bun host functions you write in D6.2 are what the embedded WASM profile calls through.
9. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/beef.zig` — BEEF/BUMP module. **E-P5.2**: uses `GullibleChainTracker` (accepts any merkle root). Document this limitation in the CellEngine.verifyBEEF() JSDoc — it's format validation, not full SPV.
10. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/main.zig` — WASM exports. Phase 5 added `kernel_verify_beef`, `kernel_verify_bump`, `kernel_beef_version`, `kernel_verify_capability`. Understand what each returns.
11. `/Users/toddprice/projects/semantos-core/packages/cell-engine/src/errors.zig` — Error codes through 40. Your CellEngine class maps these to typed results.
12. `/Users/toddprice/projects/semantos-core/packages/cell-engine/build.zig` — Build system. Produces two WASM binaries: `cell-engine.wasm` (full profile, ~178KB with BSVZ) and `cell-engine-embedded.wasm` (embedded, ~28KB). The `-Dembedded=true` flag controls which.

Then read existing TypeScript tests to understand patterns:

13. `/Users/toddprice/projects/semantos-core/packages/cell-engine/tests-ts/compat.test.ts` — Phase 0 compatibility tests. Pattern for WASM loading and host function injection.
14. `/Users/toddprice/projects/semantos-core/packages/cell-engine/tests-ts/kernel_compat.test.ts` — Kernel tests. Pattern for script loading and execution through WASM.
15. `/Users/toddprice/projects/semantos-core/packages/cell-engine/tests-ts/linearity_compat.test.ts` — Linearity tests. Pattern for enforcement toggle and Plexus opcodes.

Then read these reference implementations:

16. `/Users/toddprice/projects/semantos-core/src/cell-engine/cellPacker.ts` — Cell packing TypeScript reference. The CellEngine.packCell() and unpackCell() methods must produce bit-identical output to this.
17. `/Users/toddprice/projects/semantos-core/src/cell-engine/typeHashRegistry.ts` — Cell header layout constants. Offsets for linearity, domain flag, type hash, owner ID in the 256-byte header.

---

## Phase 5 Errata — Fix These First

Before writing any new code, fix these four issues from Phase 5. Run existing tests after each fix to ensure no regressions.

### Step 0A: Implement host_checksig (E-P5.1, CRITICAL)

In `bindings/host-functions.ts`, replace the `host_checksig` stub (currently returns 0) with a real implementation:

```typescript
host_checksig: (
  pkPtr: number, pkLen: number,
  msgPtr: number, msgLen: number,
  sigPtr: number, sigLen: number,
): number => {
  try {
    const pubkeyBytes = new Uint8Array(memory.buffer, pkPtr, pkLen);
    const msgHash = new Uint8Array(memory.buffer, msgPtr, msgLen);
    const sigBytes = new Uint8Array(memory.buffer, sigPtr, sigLen);

    // sigBytes includes sighash type as last byte — strip it
    const derSig = sigBytes.slice(0, sigBytes.length - 1);

    // Use @bsv/sdk for verification
    const { PublicKey, Signature } = require('@bsv/sdk');
    const pubkey = PublicKey.fromString(Buffer.from(pubkeyBytes).toString('hex'));
    const sig = Signature.fromDER(derSig);

    // msgHash is already the sighash digest — verify directly
    const valid = pubkey.verify(Array.from(msgHash), sig);
    return valid ? 1 : 0;
  } catch {
    return 0;
  }
},
```

**Verify**: Write a test that signs a message with `@bsv/sdk` PrivateKey, extracts the public key, and verifies through the host function. This test must pass before proceeding.

Similarly implement `host_checkmultisig` — iterate pubkeys and signatures per BSV consensus rules (sequential matching).

### Step 0B: Document GullibleChainTracker limitation (E-P5.2)

The `beef.zig` module uses `GullibleChainTracker` which accepts any merkle root. This means `kernel_verify_beef` validates BEEF format and internal consistency but does NOT verify against actual block headers. This is acceptable for Phase 6 — real SPV requires a header chain oracle (Phase 8+ infrastructure).

Action: Add clear JSDoc on `CellEngine.verifyBEEF()` stating this is format validation only. Do not claim SPV verification.

### Step 0C: Document embedded native HASH160 limitation (E-P5.3)

The embedded *native* path (Zig tests without WASM) uses truncated SHA256D for HASH160. The embedded *WASM* path correctly delegates to host_hash160 which uses real `@bsv/sdk` Hash.hash160(). The full profile uses BSVZ's real RIPEMD160.

Action: No code change needed — the WASM path (which is what production uses) is correct. Add a comment in host.zig's native HASH160 fallback noting it's test-only and not consensus-correct.

### Step 0D: Document embedded native CHECKSIG limitation (E-P5.4)

Same pattern as E-P5.3. The embedded *WASM* path delegates to host_checksig (fixed in Step 0A). The native path stub is test-only.

Action: Add a comment in host.zig noting the native CHECKSIG stub is for compilation only, not for correctness testing. Real embedded CHECKSIG testing goes through the WASM path with host functions.

---

## Implementation Steps

After Step 0 (errata), proceed in order:

### Step 1: Create directory structure

```
packages/cell-engine/bindings/bun/
packages/cell-engine/bindings/browser/
packages/cell-engine/tests-bun/     (rename from tests-ts/)
```

Move `host-functions.ts` to `bindings/bun/host-functions.ts`. Update all imports.

### Step 2: Bun-native WASM loader (`bindings/bun/loader.ts`)

```typescript
export interface BunLoadOptions {
  wasmPath?: string;
  profile?: 'full' | 'embedded';
  hostContext?: ScriptContext;
}

export async function loadCellEngine(options?: BunLoadOptions): Promise<CellEngine>
```

Implementation requirements:
- Use `Bun.file()` for WASM binary loading (not fs.readFile)
- Resolve WASM path from package root: `zig-out/cell-engine.wasm` (full) or `zig-out/cell-engine-embedded.wasm` (embedded)
- Create host functions from `createHostFunctions(memory, context)`
- Instantiate via `WebAssembly.instantiate()`
- Validate exports match PlexusKernelWasm — different validation for full vs embedded profile
- Return `new CellEngine(exports, profile)`

### Step 3: CellEngine typed API wrapper (`bindings/bun/cell-engine.ts`)

This is the core deliverable. Every method follows the same pattern:

1. Allocate buffer in WASM memory (use an exported `alloc_buffer` if available, or write directly)
2. Copy input bytes from TypeScript Uint8Array into WASM memory
3. Call the WASM export function
4. Read result bytes from WASM memory into TypeScript Uint8Array
5. Return typed result object

**Critical**: The existing tests in `tests-ts/` (soon `tests-bun/`) do this pointer management inline in each test. CellEngine centralizes it. After Phase 6, no code outside CellEngine touches WASM memory pointers.

Methods to implement (grouped by complexity):

**Simple (single WASM call, fixed-size I/O):**
- `kernelInit()`, `kernelReset()`, `kernelGetOpcount()`, `kernelGetTypeClass()`, `kernelStackDepth()`

**Medium (copy bytes in, call, read result code):**
- `kernelLoadScript(script)`, `kernelLoadUnlock(unlock)`, `kernelExecute()`
- `packCell(header, payload)`, `unpackCell(cell)`
- `deriveBCA(input)`, `verifyBCA(input)`
- `verifyCapability(lockScript, ownerPubkey, capType, domainFlag, currentTime)`

**Complex (variable-size I/O, profile-gated):**
- `verifyBEEF(beefBytes, txid)` — full profile only, throws on embedded
- `verifyBUMP(proofBytes, txid, merkleRoot)` — full profile only, throws on embedded
- `beefVersion(data)` — full profile only

**String extraction:**
- `kernelGetError()` — reads null-terminated string from WASM memory pointer
- `kernelStackPeek(index)` — reads variable-length value from WASM memory

For the memory management pattern, study how `tests-ts/compat.test.ts` writes script bytes into WASM memory and reads results back. Centralize that pattern into private helper methods:

```typescript
private writeBytes(data: Uint8Array): number {
  // Write data to WASM memory, return pointer
  const ptr = /* offset into WASM memory */;
  new Uint8Array(this.memory.buffer, ptr, data.length).set(data);
  return ptr;
}

private readBytes(ptr: number, len: number): Uint8Array {
  return new Uint8Array(this.memory.buffer, ptr, len).slice();
}
```

### Step 4: Browser WASM loader (`bindings/browser/loader.ts`)

Same API as Bun loader but:
- Uses `fetch(wasmUrl)` + `WebAssembly.instantiateStreaming(response, imports)` for loading
- wasmUrl is required (no filesystem to resolve from)
- Host functions use browser-compatible `@bsv/sdk` (the SDK has browser builds)
- No `Bun.file()`, no `bun:sqlite`, no Node-specific APIs

```typescript
export interface BrowserLoadOptions {
  wasmUrl: string;  // Required — URL to the .wasm file
  profile?: 'full' | 'embedded';
  hostContext?: ScriptContext;
}

export async function loadCellEngine(options: BrowserLoadOptions): Promise<CellEngine>
```

Browser host-functions.ts: can share the same implementation as Bun (both use @bsv/sdk), but must not import any Node/Bun APIs. Factor the shared crypto logic into a common module if needed.

### Step 5: FFI specification document (`bindings/ffi-spec.md`)

Write a markdown document covering:

1. **WASM exports table**: Every exported function with parameter types, return type, and one-sentence description. Group by phase (0-5).

2. **WASM imports table**: Every host function the module expects, with parameter types and semantics. Note which are called in full vs embedded profile.

3. **Memory model**: How to allocate a write buffer, how to read results, what the memory layout looks like. The WASM module exports `memory` — callers read/write directly.

4. **Profile differences**: Table showing which exports are present in full vs embedded. Which host imports are actively called in each profile.

5. **Minimal loader example (Python)**:
```python
import wasmtime
store = wasmtime.Store()
module = wasmtime.Module.from_file(store.engine, "cell-engine-embedded.wasm")

def host_sha256(data_ptr, data_len, out_ptr):
    # Read data from WASM memory, compute SHA256, write back
    ...

linker = wasmtime.Linker(store.engine)
linker.define_func("host", "host_sha256", host_sha256)
# ... define other host functions ...
instance = linker.instantiate(store, module)
```

6. **Minimal loader example (Rust)**:
```rust
use wasmer::{imports, Instance, Module, Store};
// Similar pattern
```

### Step 6: Rename tests-ts/ to tests-bun/

Rename the directory. Update all import paths. Update `package.json` test scripts. Update `bunfig.toml` if it exists. Verify `bun test` still finds and runs all tests.

### Step 7: Write Bun loader tests (`tests-bun/loader.test.ts`)

```typescript
describe('Bun WASM loader', () => {
  test('loadCellEngine() returns CellEngine with full profile', async () => {
    const engine = await loadCellEngine();
    expect(engine.profile).toBe('full');
    expect(engine.memory).toBeInstanceOf(WebAssembly.Memory);
  });

  test('loadCellEngine({ profile: "embedded" }) loads embedded binary', async () => {
    const engine = await loadCellEngine({ profile: 'embedded' });
    expect(engine.profile).toBe('embedded');
  });

  test('full profile has SPV exports', async () => {
    const engine = await loadCellEngine({ profile: 'full' });
    expect(() => engine.beefVersion(new Uint8Array([0]))).not.toThrow();
  });

  test('embedded profile throws on SPV methods', async () => {
    const engine = await loadCellEngine({ profile: 'embedded' });
    expect(() => engine.verifyBEEF(new Uint8Array(), new Uint8Array(32)))
      .toThrow(/not available in embedded profile/);
  });

  test('export validation rejects broken WASM', async () => {
    // Attempt to load invalid bytes
    await expect(loadCellEngine({ wasmPath: '/dev/null' })).rejects.toThrow();
  });
});
```

### Step 8: Write CellEngine typed API tests (`tests-bun/cell-engine.test.ts`)

```typescript
describe('CellEngine typed API', () => {
  let engine: CellEngine;
  beforeAll(async () => { engine = await loadCellEngine(); });

  test('packCell accepts CellHeader + payload, returns 1024-byte Uint8Array', () => {
    const header = buildTestHeader({ linearity: 0 /* LINEAR */ });
    const payload = new Uint8Array(768).fill(0x42);
    const cell = engine.packCell(header, payload);
    expect(cell.length).toBe(1024);
  });

  test('unpackCell round-trips with packCell', () => {
    const header = buildTestHeader({ linearity: 1, domainFlag: 0x0103 });
    const payload = randomBytes(768);
    const cell = engine.packCell(header, payload);
    const { header: h2, payload: p2 } = engine.unpackCell(cell);
    expect(h2.linearity).toBe(1);
    expect(h2.domainFlag).toBe(0x0103);
    expect(p2).toEqual(payload);
  });

  test('executeScript runs OP_TRUE and returns success', () => {
    const result = engine.executeScript(new Uint8Array([0x51])); // OP_TRUE
    expect(result.success).toBe(true);
  });

  test('executeScript runs OP_FALSE and returns failure', () => {
    const result = engine.executeScript(new Uint8Array([0x00])); // OP_FALSE
    expect(result.success).toBe(false);
  });

  test('real CHECKSIG: sign with @bsv/sdk, verify through engine', () => {
    // THIS IS THE KEY TEST — proves the full path works
    const { PrivateKey, PublicKey, Hash, Signature, TransactionSignature } = require('@bsv/sdk');
    const privkey = PrivateKey.fromRandom();
    const pubkey = privkey.toPublicKey();

    // Build a P2PKH-style script verification:
    // unlockScript: <sig> <pubkey>
    // lockScript: OP_DUP OP_HASH160 <pubkeyhash> OP_EQUALVERIFY OP_CHECKSIG

    // ... construct scripts ...

    const result = engine.executeScript(lockScript, unlockScript);
    expect(result.success).toBe(true);
  });

  test('verifyCapability with OP_TRUE script succeeds', () => {
    const result = engine.verifyCapability(
      new Uint8Array([0x51]), // OP_TRUE
      new Uint8Array(33),    // dummy pubkey
      0, 0, 0
    );
    expect(result.valid).toBe(true);
  });
});
```

### Step 9: Write integration tests (`tests-bun/integration.test.ts`)

```typescript
import { Database } from 'bun:sqlite';

describe('Full lifecycle integration', () => {
  let db: Database;
  let engine: CellEngine;

  beforeAll(async () => {
    db = new Database(':memory:');
    // Create a minimal table for semantic objects
    db.run(`CREATE TABLE semantic_objects (
      id TEXT PRIMARY KEY,
      cell_data BLOB NOT NULL,
      linearity INTEGER NOT NULL,
      domain_flag INTEGER NOT NULL,
      type_hash BLOB NOT NULL,
      created_at INTEGER DEFAULT (unixepoch())
    )`);
    engine = await loadCellEngine();
  });

  test('LINEAR object: create → pack → store → query → verify linearity', () => {
    const header = buildTestHeader({ linearity: 0 /* LINEAR */ });
    const payload = new TextEncoder().encode('invoice:001');
    const cell = engine.packCell(header, payload);

    // Store
    db.run('INSERT INTO semantic_objects VALUES (?, ?, ?, ?, ?)',
      ['obj-1', cell, 0, header.domainFlag, header.typeHash]);

    // Query
    const row = db.query('SELECT * FROM semantic_objects WHERE id = ?').get('obj-1');
    expect(row).not.toBeNull();

    // Verify linearity through engine
    const { header: stored } = engine.unpackCell(row.cell_data);
    expect(stored.linearity).toBe(0); // LINEAR
  });

  test('BSV testnet: anchor → BEEF → verify (conditional)', () => {
    const key = process.env.BSV_TESTNET_KEY;
    if (!key) {
      console.log('SKIPPED: BSV_TESTNET_KEY not set');
      return;
    }
    // Real @bsv/sdk transaction
    // Real ARC broadcast
    // Real BEEF envelope
    // Real engine.verifyBEEF()
  });
});
```

### Step 10: Update package.json scripts

```json
{
  "scripts": {
    "test": "bun test tests-bun/",
    "test:integration": "bun test tests-bun/integration.test.ts",
    "build": "cd packages/cell-engine && zig build",
    "build:embedded": "cd packages/cell-engine && zig build -Dembedded=true"
  }
}
```

### Step 11: Delete stale Phase 0 tests

Two tests in `tests-bun/` (formerly `tests-ts/`) are stale Phase 0 stub tests:
- One checks binary size < 20KB (now 178KB by design)
- One checks kernel_init returns 255/NOT_IMPLEMENTED (now returns 0/SUCCESS)

Find and delete these specific test cases. They test the absence of functionality that now exists.

---

## Verification Checklist

Run these in order. All must pass.

1. `cd packages/cell-engine && zig build` — full profile builds
2. `cd packages/cell-engine && zig build -Dembedded=true` — embedded profile builds
3. `cd packages/cell-engine && zig build test` — all Zig tests pass (both profiles)
4. `bun test tests-bun/loader.test.ts` — Bun loader tests pass
5. `bun test tests-bun/cell-engine.test.ts` — CellEngine API tests pass
6. `bun test tests-bun/` — all tests pass (including existing compat, bca, kernel, linearity, spv, capability, checksig)
7. `bun test tests-bun/integration.test.ts` — integration tests pass
8. Verify: `engine.executeScript()` with a real P2PKH script (sign with @bsv/sdk, verify through engine) returns success — this proves CHECKSIG works end-to-end
9. Verify: `engine.verifyBEEF()` on full profile doesn't throw (embedded profile does throw)
10. Verify: `engine.verifyCapability()` works on both profiles
11. Verify: WASM binary sizes unchanged — full ~178KB, embedded ~28KB
12. Verify: `bindings/ffi-spec.md` exists and documents all exports/imports
13. Verify: no raw pointer arithmetic outside CellEngine class (grep for `memory.buffer` in test files — should only appear in CellEngine internals, not in tests)

---

## Files You Will Create

| File | Purpose |
|------|---------|
| `bindings/bun/loader.ts` | Bun-native WASM loader |
| `bindings/bun/host-functions.ts` | Moved + fixed from `bindings/host-functions.ts` |
| `bindings/bun/cell-engine.ts` | CellEngine typed API wrapper |
| `bindings/bun/index.ts` | Barrel export for `@semantos/cell-engine/bun` |
| `bindings/browser/loader.ts` | Browser WASM loader |
| `bindings/browser/host-functions.ts` | Browser-compatible host functions |
| `bindings/browser/index.ts` | Barrel export for `@semantos/cell-engine/browser` |
| `bindings/ffi-spec.md` | FFI specification for non-JS runtimes |
| `tests-bun/loader.test.ts` | Bun loader tests |
| `tests-bun/cell-engine.test.ts` | CellEngine typed API tests |
| `tests-bun/integration.test.ts` | Full lifecycle integration tests |

## Files You Will Modify

| File | Change |
|------|--------|
| `bindings/host-functions.ts` | Move to `bindings/bun/host-functions.ts`, implement CHECKSIG/CHECKMULTISIG |
| `bindings/index.ts` | Replace stub with redirect or remove |
| `tests-ts/*.test.ts` | Rename directory to `tests-bun/`, update imports |
| `package.json` | Update test scripts, add exports map for bun/browser entry points |
| `src/cell-engine/wasm-interface.ts` | No changes needed — CellEngine wraps this interface |

## Files You Will NOT Modify

| File | Why |
|------|-----|
| `src/host.zig` | Add comments only (E-P5.3, E-P5.4 documentation) |
| `src/beef.zig` | No changes — GullibleChainTracker limitation documented in CellEngine JSDoc |
| `src/main.zig` | No changes — WASM exports are correct |
| `build.zig` | No changes — dual profile build is working |
| `build.zig.zon` | No changes — BSVZ dependency is wired |

---

## Anti-Pattern Warnings

**Do not create a universal loader.** Bun and browser have different WASM loading APIs. Two separate files, two separate entry points. No `if (typeof Bun !== 'undefined')` branching.

**Do not wrap errors in generic Error.** Use the KernelError enum. Map WASM return codes to typed results: `{ valid: true }` or `{ valid: false, error: KernelError.BEEF_PARSE_ERROR, message: '...' }`.

**Do not test CHECKSIG with stubs.** Gate 3 requires a real @bsv/sdk signature flowing through the WASM engine. If this test passes with a stub, the test is wrong.

**Do not claim SPV verification.** The CellEngine.verifyBEEF() JSDoc must state: "Validates BEEF format and internal merkle proof consistency. Does NOT verify against actual block headers (requires chain tracker oracle, not yet implemented)."

**Do not leave pointer arithmetic in tests.** After Phase 6, the only code that touches `memory.buffer` is inside CellEngine. Tests use `engine.executeScript()`, not `new Uint8Array(memory.buffer, ptr, len)`.
