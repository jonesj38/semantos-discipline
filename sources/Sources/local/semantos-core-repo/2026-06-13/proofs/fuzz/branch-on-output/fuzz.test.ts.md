---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/branch-on-output/fuzz.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.355561+00:00
---

# proofs/fuzz/branch-on-output/fuzz.test.ts

```ts
/**
 * OP_BRANCHONOUTPUT — L3 Differential Oracle Test
 *
 * Formally proved theorems in BranchOnOutput.lean:
 *
 *   T1 — determinism:        stepOp on equal inputs gives equal outputs.
 *   T2 — stack delta = +1:   OP_BRANCHONOUTPUT pushes exactly one item:
 *                             the 4-byte LE encoding of currentOutputIndex.
 *   T3 — non-malleability:   no opcode can write currentOutputIndex.
 *   T4 — sole observer:      scripts without OP_BRANCHONOUTPUT produce
 *                             results independent of currentOutputIndex.
 *
 * Oracle: core/cell-engine/lean4/.lake/build/bin/BranchOnOutputOracle
 *   Input:  {"outputIndex": N}     (decimal uint32)
 *   Output: {"bytes": [b0,b1,b2,b3]}  — the exact bytes the model predicts
 *
 * WASM opcode: 0xE0 (OP_BRANCHONOUTPUT)
 * WASM API:
 *   kernel_set_output_index(N) — inject currentOutputIndex before execute
 *   kernel_stack_peek(i)       — returns linear-memory offset of slot i
 *   kernel_stack_value_length(i) — byte length of slot i
 *   kernel_stack_depth()       — current stack depth
 *
 * Test groups:
 *
 *   t2_oracle_sanity (9): oracle output matches manual u32ToLE calculation
 *     for key values (0, 1, 256, 0xFFFF, 0xFF0000, 0xFFFFFFFF, ...)
 *
 *   t2_stack_delta_plus_one (9): after executing OP_BRANCHONOUTPUT with an
 *     initially empty stack, kernel_stack_depth() must be exactly 1.
 *
 *   t2_differential (9): bytes on the WASM stack top agree exactly with the
 *     oracle's u32ToLE prediction for each test outputIndex.
 *
 *   t4_independence (3): a script containing NO OP_BRANCHONOUTPUT produces
 *     the same kernel_execute result and same stack content regardless of
 *     which outputIndex was injected (currentOutputIndex independence).
 */

import { describe, it, expect, beforeAll } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join, resolve } from "path";
import { spawnSync } from "bun";

// ── Paths ─────────────────────────────────────────────────────────────────────

const REPO_ROOT  = resolve(import.meta.dir, "../../..");
const LEAN4_DIR  = join(REPO_ROOT, "core/cell-engine/lean4");
const ORACLE_BIN = join(LEAN4_DIR, ".lake/build/bin/BranchOnOutputOracle");
const LAKE_BIN   = join(process.env.HOME ?? "/root", ".elan/bin/lake");
const WASM_PATH  = join(REPO_ROOT, "core/cell-engine/zig-out/bin/cell-engine.wasm");

// ── WASM kernel setup ─────────────────────────────────────────────────────────

interface KernelExports {
  memory: WebAssembly.Memory;
  kernel_init:              () => number;
  kernel_reset:             () => void;
  kernel_load_script:       (ptr: number, len: number) => number;
  kernel_set_enforcement:   (enabled: number) => void;
  kernel_set_output_index:  (index: number) => number;
  kernel_execute:           () => number;
  kernel_stack_depth:       () => number;
  kernel_stack_peek:        (index: number) => number;     // → linear-mem offset
  kernel_stack_value_length:(index: number) => number;     // → byte count
}

let kernel: KernelExports | null = null;

function getKernel(): KernelExports {
  if (!kernel) throw new Error("WASM kernel not initialised");
  return kernel;
}

function writeToWasm(k: KernelExports, bytes: Uint8Array): number {
  const offset = 64 * 1024;
  new Uint8Array(k.memory.buffer).set(bytes, offset);
  return offset;
}

/** Read `len` bytes from WASM linear memory at `ptr`. */
function readFromWasm(k: KernelExports, ptr: number, len: number): number[] {
  return Array.from(new Uint8Array(k.memory.buffer, ptr, len));
}

// ── Oracle ────────────────────────────────────────────────────────────────────

/** Query oracle: given outputIndex N, return the predicted 4 LE bytes. */
function queryOracle(outputIndex: number): number[] {
  const input = JSON.stringify({ outputIndex }) + "\n";
  const result = spawnSync([ORACLE_BIN], {
    stdin: Buffer.from(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`BranchOnOutputOracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  const out = JSON.parse(result.stdout.toString().trim());
  if ("error" in out) throw new Error(`Oracle error: ${out.error} (outputIndex: ${outputIndex})`);
  return out.bytes as number[];
}

// ── WASM helpers ──────────────────────────────────────────────────────────────

/** Execute the OP_BRANCHONOUTPUT script with a given outputIndex. */
function executeBranchOnOutput(outputIndex: number): {
  exitCode: number;
  stackDepth: number;
  topBytes: number[];
} {
  const k = getKernel();
  const script = new Uint8Array([0xE0]); // OP_BRANCHONOUTPUT
  const ptr = writeToWasm(k, script);
  k.kernel_reset();
  k.kernel_set_enforcement(0); // linearity off — not what we're testing here
  const setResult = k.kernel_set_output_index(outputIndex);
  if (setResult !== 0) throw new Error(`kernel_set_output_index failed: ${setResult}`);
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult}`);
  const exitCode = k.kernel_execute();
  const stackDepth = k.kernel_stack_depth();
  let topBytes: number[] = [];
  if (stackDepth > 0) {
    const valueLen = k.kernel_stack_value_length(0);
    const dataPtr  = k.kernel_stack_peek(0);
    topBytes = readFromWasm(k, dataPtr, valueLen);
  }
  return { exitCode, stackDepth, topBytes };
}

/** Execute a non-branchOnOutput script (just OP_1 = 0x51) with given outputIndex. */
function executeNoBranchScript(outputIndex: number): {
  exitCode: number;
  stackDepth: number;
  topBytes: number[];
} {
  const k = getKernel();
  // OP_1 (0x51): pushes [0x01] onto the stack. Contains no OP_BRANCHONOUTPUT.
  const script = new Uint8Array([0x51]);
  const ptr = writeToWasm(k, script);
  k.kernel_reset();
  k.kernel_set_enforcement(0);
  k.kernel_set_output_index(outputIndex);
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult}`);
  const exitCode = k.kernel_execute();
  const stackDepth = k.kernel_stack_depth();
  let topBytes: number[] = [];
  if (stackDepth > 0) {
    const valueLen = k.kernel_stack_value_length(0);
    const dataPtr  = k.kernel_stack_peek(0);
    topBytes = readFromWasm(k, dataPtr, valueLen);
  }
  return { exitCode, stackDepth, topBytes };
}

// ── Test values ───────────────────────────────────────────────────────────────

const TEST_INDICES = [
  0,             // all-zero LE
  1,             // byte 0 = 1, rest 0
  42,            // small value
  255,           // max single byte
  256,           // byte 0 = 0, byte 1 = 1
  65535,         // 0x0000FFFF
  16777215,      // 0x00FFFFFF
  2147483647,    // 0x7FFFFFFF
  4294967295,    // 0xFFFFFFFF (u32 max)
] as const;

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  if (!existsSync(ORACLE_BIN)) {
    const build = spawnSync([LAKE_BIN, "build", "BranchOnOutputOracle"], {
      cwd: LEAN4_DIR,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (build.exitCode !== 0) throw new Error("Failed to build BranchOnOutputOracle");
  }

  const wasmBytes = readFileSync(WASM_PATH);
  const hostStubs = {
    host_fetch_cell:       () => 0,
    host_call_by_name:     () => 0,
    hostDbOpenCursor:      () => 0,
    hostDbCursorPull:      () => 0,
    hostDbCursorClose:     () => 0,
    host_sha256:           () => {},
    host_hash160:          () => {},
    host_hash256:          () => {},
    host_ripemd160:        () => {},
    host_sha1:             () => {},
    host_checksig:         () => 0,
    host_checkmultisig:    () => 0,
    host_sign:             () => 0,
    host_get_blocktime:    () => 0,
    host_get_sequence:     () => 0,
    host_log:              () => {},
    host_derive_leaf:      () => 0,
    host_state_next_index: () => 0,
    host_unlock_tier:      () => 0,
    host_persist_cell:     () => 0,
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { host: hostStubs });
  const e = instance.exports as unknown as KernelExports;
  const initResult = e.kernel_init();
  if (initResult !== 0) throw new Error(`kernel_init failed: ${initResult}`);
  kernel = e;
}, 120_000);

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("OP_BRANCHONOUTPUT — L3 Oracle vs WASM", () => {

  // ── Oracle sanity: u32ToLE encoding matches manual expectations ─────────────

  describe("t2_oracle_sanity — u32ToLE matches expected LE bytes", () => {
    it("outputIndex=0        → [0,0,0,0]",           () => expect(queryOracle(0)).toEqual([0,0,0,0]));
    it("outputIndex=1        → [1,0,0,0]",           () => expect(queryOracle(1)).toEqual([1,0,0,0]));
    it("outputIndex=42       → [42,0,0,0]",          () => expect(queryOracle(42)).toEqual([42,0,0,0]));
    it("outputIndex=255      → [255,0,0,0]",         () => expect(queryOracle(255)).toEqual([255,0,0,0]));
    it("outputIndex=256      → [0,1,0,0]",           () => expect(queryOracle(256)).toEqual([0,1,0,0]));
    it("outputIndex=65535    → [255,255,0,0]",       () => expect(queryOracle(65535)).toEqual([255,255,0,0]));
    it("outputIndex=16777215 → [255,255,255,0]",     () => expect(queryOracle(16777215)).toEqual([255,255,255,0]));
    it("outputIndex=2147483647 → [255,255,255,127]", () => expect(queryOracle(2147483647)).toEqual([255,255,255,127]));
    it("outputIndex=4294967295 → [255,255,255,255]", () => expect(queryOracle(4294967295)).toEqual([255,255,255,255]));
  });

  // ── T2: OP_BRANCHONOUTPUT pushes exactly one item ───────────────────────────

  describe("t2_stack_delta_plus_one — executing 0xE0 on empty stack → depth 1", () => {
    // Note: exitCode 0 = truthy result, 6 = falsy result (verify_failed).
    // For outputIndex=0 the pushed bytes are [0,0,0,0] which is falsy,
    // so kernel_execute legitimately returns 6.  T2 is about the pushed
    // item count, not about the script's truth value — we only assert depth.
    // Operational errors (no_tx_context=18, stack_underflow=2) are checked
    // separately by asserting the opcode was actually reachable (depth=1).
    for (const idx of TEST_INDICES) {
      it(`outputIndex=${idx}: stack depth after execute = 1`, () => {
        const { stackDepth } = executeBranchOnOutput(idx);
        expect(stackDepth).toBe(1);
      });
    }
  });

  // ── T2 differential: WASM top-of-stack agrees with oracle prediction ─────────

  describe("t2_differential — WASM stack top matches oracle u32ToLE prediction", () => {
    for (const idx of TEST_INDICES) {
      it(`outputIndex=${idx}: top-of-stack bytes = oracle prediction`, () => {
        const expected = queryOracle(idx);          // [b0,b1,b2,b3] from model
        const { topBytes } = executeBranchOnOutput(idx);
        expect(topBytes).toHaveLength(4);
        expect(topBytes).toEqual(expected);
      });
    }
  });

  // ── T4: scripts without OP_BRANCHONOUTPUT are currentOutputIndex-independent

  describe("t4_independence — non-branchOnOutput scripts produce same result for any outputIndex", () => {
    const referenceIndices = [0, 1, 4294967295] as const;
    it("OP_1 script: exitCode identical for outputIndex 0, 1, 4294967295", () => {
      const results = referenceIndices.map(i => executeNoBranchScript(i));
      const exitCodes = results.map(r => r.exitCode);
      expect(exitCodes[1]).toBe(exitCodes[0]);
      expect(exitCodes[2]).toBe(exitCodes[0]);
    });
    it("OP_1 script: stack depth identical for all three outputIndex values", () => {
      const results = referenceIndices.map(i => executeNoBranchScript(i));
      const depths = results.map(r => r.stackDepth);
      expect(depths[1]).toBe(depths[0]);
      expect(depths[2]).toBe(depths[0]);
    });
    it("OP_1 script: top-of-stack bytes identical for all three outputIndex values", () => {
      const results = referenceIndices.map(i => executeNoBranchScript(i));
      expect(results[1].topBytes).toEqual(results[0].topBytes);
      expect(results[2].topBytes).toEqual(results[0].topBytes);
    });
  });
});

```
