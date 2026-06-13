---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-6-TS-BINDINGS.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.703843+00:00
---

# Phase 6: TypeScript Bindings and Bun Integration

**Duration**: 2 weeks (with 40% buffer: ~20 days)
**Prerequisites**: Phase 5 complete — all host functions working, BEEF/BUMP verification passing, capability tokens evaluating.
**Master document**: `SEMANTOS_ZIG_WASM_PRD.md` (in this directory: `semantos-core/docs/prd/`)

---

## Context

The Zig WASM engine is now functionally complete. This phase wraps it in a typed TypeScript API that existing code can consume — the semantic wallet CLI tools, the Tauri desktop app, and future Bun server deployments. The bindings must load the WASM binary, inject host functions, and expose a clean API that hides the raw pointer arithmetic.

This phase also runs the first full integration test: create a semantic object → pack it into cells → construct a BSV transaction → anchor on testnet → verify the BUMP proof through WASM → evaluate a capability token script. If this end-to-end flow works, the engine is production-viable.

---

## Source Files You MUST Read

| Alias | Path | What to extract |
|-------|------|----------------|
| `CORE:WASM` | `semantos-core/src/cell-engine/wasm-interface.ts` | `loadKernel()` function — the existing WASM loader pattern. Export validation logic. This is what existing code expects. |
| `CORE:INDEX` | `semantos-core/src/index.ts` | Barrel export pattern. What modules semantos-core currently exposes. |
| `WALLET:CLI` | `semantic-wallet/cli/semantic-cli.cjs` | How existing CLI tools consume BSV SDK primitives. Import patterns, transaction construction flow. |
| `KERNEL:SCHEMA` | `oddjobtodd/src/lib/semantos-kernel/schema.core.ts` | **39KB Drizzle schema** — 15+ tables (`semanticObjects`, `objectStates`, `objectPatches`, `objectScores`, `evidenceItems`, `semInstruments`, `anchorRequests`, `participants`, `channels`, `channelPolicies`, `accessPolicies`, `objectEdges`, `objectBindings`, `pendingWrites`, `outcomes`). **Production persistence target — integration tests validate against this, NOT WALLET:SCHEMA (legacy SQLite).** |
| `KERNEL:ADAPTER` | `oddjobtodd/src/lib/semantos-kernel/adapter.base.ts` | SemanticAdapter base — `ensureObject()`, `recordState()`, `requestAnchor()` (two-phase commit), `retryPendingWrites()` (DLQ). Base class for domain extensions. |
| `KERNEL:MERKLE` | `oddjobtodd/src/lib/semantos-kernel/merkleEnvelope.ts` | Merkle envelope generation — `buildMerkleTree()`, `serializeMerkleEnvelope()`. Reference for ENVELOPE cell content. |
| `SEMOBJ:OUTPUT-STORE` | `semantos/semantic-wallet/src/lib/stores/outputs.ts` | SpendableOutput store — the existing output tracking API. |
| `SEMOBJ:BTC-TYPES` | `semantos/semantic-wallet/src/lib/types/bitcoin.ts` | `SpendableOutput` interface: txid, index, satoshis, spent, lockScript, bumpProof. |
| `SDK:TS` | `ts-sdk/` | `@bsv/sdk` — Transaction, Beef, ARC broadcaster. |
| `SDK:TOOLBOX` | `wallet-toolbox/` | `@bsv/wallet-toolbox` — createAction, signAction, internalizeAction. |

---

## Deliverables

### D6.1 — `loader.ts` (WASM Binary Loader)

```typescript
import type { PlexusKernelWasm, PlexusKernelHostImports } from './types';
import { createHostFunctions } from './host-functions';

export interface LoadOptions {
    wasmPath?: string;          // Path to .wasm file (default: bundled)
    hostContext?: ScriptContext; // Context for host functions
    target?: 'bun' | 'browser'; // Runtime target
}

export async function loadCellEngine(options?: LoadOptions): Promise<CellEngine> {
    const wasmBytes = await loadWasmBinary(options?.wasmPath);
    const hostFunctions = createHostFunctions(options?.hostContext);

    const instance = await WebAssembly.instantiate(wasmBytes, {
        host: hostFunctions,
    });

    // Validate exports match PlexusKernelWasm
    validateExports(instance.exports);

    return new CellEngine(instance);
}
```

**Must support**:
- Bun: `Bun.file()` for WASM loading, WASI support
- Browser: `fetch()` + `WebAssembly.instantiateStreaming()`
- Both: identical API surface

### D6.2 — `index.ts` (Typed API Wrapper)

```typescript
export class CellEngine {
    // Cell operations
    packCell(header: CellHeader, payload: Uint8Array): Uint8Array;
    unpackCell(cell: Uint8Array): { header: CellHeader; payload: Uint8Array };
    packMultiCell(object: SemanticObjectInput): Uint8Array[];
    unpackMultiCell(cells: Uint8Array[]): SemanticObjectResult;

    // BCA operations
    deriveBCA(input: BCAInput): BCAOutput;
    verifyBCA(input: BCAVerifyInput): boolean;

    // Script execution
    executeScript(context: ScriptContext): ScriptResult;
    checkLinearity(operation: LinearityOperation): LinearityResult;

    // SPV verification
    verifyBEEF(beefBytes: Uint8Array, txid: Uint8Array): boolean;
    verifyBUMP(proofBytes: Uint8Array, txid: Uint8Array): boolean;

    // Capability tokens
    verifyCapabilityToken(token: CapabilityTokenRef): boolean;

    // Kernel interface (matching PlexusKernelWasm)
    kernelInit(): void;
    kernelReset(): void;
    kernelLoadScript(script: Uint8Array): void;
    kernelLoadUnlock(unlock: Uint8Array): void;
    kernelExecute(): ScriptResult;
    kernelGetTypeClass(): LinearityType;
    kernelGetOpcount(): number;
    kernelGetError(): string;
    kernelStackDepth(): number;
    kernelStackPeek(index: number): Uint8Array;

    // Memory management
    readonly memory: WebAssembly.Memory;
}
```

**Critical**: All pointer arithmetic (writing to / reading from WASM memory) happens ONLY in this class. External callers pass typed TypeScript objects, never raw pointers.

### D6.3 — Integration tests with real infrastructure

```typescript
// integration.test.ts
import { Database } from 'bun:sqlite';

describe('Full semantic object lifecycle', () => {
    let db: Database;
    let engine: CellEngine;

    beforeAll(async () => {
        // Real SQLite database with real schema
        db = new Database(':memory:');
        db.run(readFileSync('semantic-wallet/migrations/004_linear_semantic_objects.sql', 'utf-8'));

        // Real WASM engine
        engine = await loadCellEngine();
    });

    test('create LINEAR semantic object → pack → store', () => {
        const header = buildCellHeader({
            linearity: LinearityType.LINEAR,
            typeHash: computeTypeHash('commerce:trade:invoice'),
            ownerId: randomOwnerId(),
        });

        const cell = engine.packCell(header, payload);
        expect(cell.length).toBe(1024);

        // Store in real database
        db.run('INSERT INTO linear_semantic_objects ...', [cell]);
    });

    test('anchor on BSV testnet', () => {
        // Skip if BSV_TESTNET_KEY not set
        const key = process.env.BSV_TESTNET_KEY;
        if (!key) {
            console.log('SKIPPED: BSV_TESTNET_KEY not set');
            return;
        }

        // Real transaction via @bsv/sdk
        // Real BEEF envelope
        // Real BUMP proof
    });

    test('verify BUMP proof through WASM engine', () => {
        // Use pre-captured testnet fixture if no live key
        const isValid = engine.verifyBUMP(bumpProof, txid);
        expect(isValid).toBe(true);
    });

    test('linearity enforcement rejects double-spend attempt', () => {
        // Create LINEAR cell, consume it, attempt to consume again → fail
    });
});
```

---

## TDD Gate — Tests That Must Pass

### Test 1: WASM loading (TypeScript)
```typescript
test("loadCellEngine returns CellEngine instance", () => { ... });
test("WASM binary loads in Bun", () => { ... });
test("export validation catches missing exports", () => { ... });
test("host function injection works", () => { ... });
```

### Test 2: Typed API (TypeScript)
```typescript
test("packCell accepts CellHeader object, returns Uint8Array", () => { ... });
test("unpackCell returns typed header fields", () => { ... });
test("deriveBCA accepts BCAInput, returns BCAOutput", () => { ... });
test("executeScript accepts ScriptContext, returns ScriptResult", () => { ... });
test("checkLinearity returns typed LinearityResult", () => { ... });
```

### Test 3: Kernel interface compatibility (TypeScript)
```typescript
test("CellEngine satisfies PlexusKernelWasm interface", () => {
    // Type-check: CellEngine must have all methods from PlexusKernelWasm
});
test("kernel_init + kernel_load_script + kernel_execute works", () => { ... });
test("kernel_get_type_class returns correct enum value", () => { ... });
```

### Test 4: Integration with real SQLite
```typescript
test("create and store LINEAR object in real database", () => { ... });
test("query stored objects matches original data", () => { ... });
test("audit log records creation", () => { ... });
```

### Test 5: End-to-end BSV testnet (conditional)
```typescript
test("full lifecycle: create → anchor → verify → consume", () => {
    // SKIP with message if BSV_TESTNET_KEY not set
    // DO NOT mock — either real testnet or explicit skip
});
```

---

## Phase Completion Criteria

You are **done with Phase 6** when ALL of the following are true:

1. `loadCellEngine()` loads WASM binary in both Bun and browser targets
2. `CellEngine` class exposes typed API for all WASM exports
3. `CellEngine` satisfies `PlexusKernelWasm` interface from semantos-core
4. Integration tests with real database pass (using production `KERNEL:SCHEMA` Drizzle schema)
5. End-to-end BSV testnet test passes (or explicitly skips with message)
6. No raw pointer arithmetic exposed to API callers — all marshalling is internal
7. All Phase 1-5 tests still pass (no regressions)
8. `bun test` and `bun test:integration` both pass

## What NOT To Do

- Do not expose raw WASM memory pointers in the public API
- Do not mock SQLite or BSV testnet — use real instances or skip explicitly
- Do not break the `PlexusKernelWasm` interface — existing code depends on it
- Do not duplicate type definitions — import from `@semantos/protocol-types`
- Do not bundle @bsv/sdk inside the WASM — it stays on the TypeScript side

---

## Next Phase

Phase 6 output feeds into **Phase 7: CI/CD Pipeline and Performance Benchmarks**.
