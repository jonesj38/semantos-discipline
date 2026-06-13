---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/fuzz/k1-linearity/fuzz.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.355237+00:00
---

# proofs/fuzz/k1-linearity/fuzz.test.ts

```ts
/**
 * K1 Linearity — L3 Differential Oracle Test
 *
 * Asserts that the Zig WASM cell-engine agrees with the Lean4 linearity
 * model (Semantos.linearityPermits) on every (linearity-type, stack-op)
 * pair in the 4×5 = 20-cell permission table.
 *
 * Three-tier structure:
 *   L1  — Zig unit tests (linearity_conformance.zig, 30+ tests)
 *   L2  — (covered by K1 Zig unit tests — the table is finite/exhaustive)
 *   L3  — THIS FILE: Lean4 oracle vs live WASM kernel
 *
 * Oracle: proofs/lean/.lake/build/bin/K1LinearityOracle
 *   Input:  {"linearity": "<l>", "op": "<op>"}
 *   Output: {"permitted": true|false}
 *
 * WASM test strategy per stack-op category:
 *   duplicate  → OP_DUP  (0x76)  — enforced_dup() checks linearity
 *   discard    → OP_DROP (0x75)  — enforced_drop() checks linearity
 *   swap       → OP_TOALTSTACK (0x6B) — spop() without check; always allowed
 *   inspect    → OP_DEPTH (0x74) — doesn't pop; always allowed
 *   consume    → OP_EQUAL (0x87) on two identical items — spop() × 2, no check
 *
 * Test cell: 20-byte minimum cell (no magic needed — getLinearity reads
 * bytes 16-19 regardless). Layout:
 *   bytes 0-15:  0x00 (unused header area)
 *   bytes 16-19: linearity type as u32 LE (1=LINEAR 2=AFFINE 3=RELEVANT 4=DEBUG)
 *
 * Linearity error codes (from errors.zig):
 *   22 = cannot_duplicate_linear
 *   23 = cannot_discard_linear
 *   24 = cannot_duplicate_affine
 *   25 = cannot_discard_relevant
 *
 * A result that is NOT one of [22, 23, 24, 25] means "operation permitted"
 * (the engine accepted it — possibly returning verify_failed=6 if the stack
 * ended falsy, but NOT a linearity error).
 */

import { describe, it, expect, beforeAll } from "bun:test";
import { readFileSync, existsSync } from "fs";
import { join, resolve } from "path";
import { spawnSync } from "bun";

// ── Paths ─────────────────────────────────────────────────────────────────────

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const LEAN4_DIR = join(REPO_ROOT, "proofs/lean");
const ORACLE_BIN = join(LEAN4_DIR, ".lake/build/bin/K1LinearityOracle");
const LAKE_BIN = join(process.env.HOME ?? "/root", ".elan/bin/lake");
const WASM_PATH = join(REPO_ROOT, "core/cell-engine/zig-out/bin/cell-engine.wasm");

// ── WASM kernel setup ─────────────────────────────────────────────────────────

interface KernelExports {
  memory: WebAssembly.Memory;
  kernel_init: () => number;
  kernel_reset: () => void;
  kernel_load_script: (ptr: number, len: number) => number;
  kernel_set_enforcement: (enabled: number) => void;
  kernel_execute: () => number;
  kernel_get_error: () => number;
}

let kernel: KernelExports | null = null;

function getKernel(): KernelExports {
  if (!kernel) throw new Error("WASM kernel not initialised");
  return kernel;
}

/** Write bytes into WASM memory at the given pointer. */
function writeToWasm(k: KernelExports, bytes: Uint8Array): number {
  // Use the stack area: kernel already manages its own stack, but we can write
  // into scratch space in the linear memory above the stack.  A fixed offset
  // of 1MB is safe for small test data — the Zig stack lives at 1MB top and
  // grows downward, but the actual stack frame is tiny here.
  const offset = 64 * 1024; // 64 KB into linear memory — safe scratch area
  const mem = new Uint8Array(k.memory.buffer);
  mem.set(bytes, offset);
  return offset;
}

// ── Linearity error codes ─────────────────────────────────────────────────────

const LINEARITY_ERROR_CODES = new Set([22, 23, 24, 25]);

function isPermittedByWasm(result: number): boolean {
  return !LINEARITY_ERROR_CODES.has(result);
}

// ── Oracle ────────────────────────────────────────────────────────────────────

function queryOracle(linearity: string, op: string): boolean {
  const input = JSON.stringify({ linearity, op }) + "\n";
  const result = spawnSync([ORACLE_BIN], {
    stdin: Buffer.from(input),
    stdout: "pipe",
    stderr: "pipe",
  });
  if (result.exitCode !== 0) {
    throw new Error(`K1LinearityOracle exited ${result.exitCode}: ${result.stderr.toString()}`);
  }
  const out = JSON.parse(result.stdout.toString().trim());
  if ("error" in out) throw new Error(`Oracle parse error: ${out.error} (input: ${input.trim()})`);
  return out.permitted as boolean;
}

// ── Script builders ───────────────────────────────────────────────────────────

/** Linearity type byte value (LE u32 at offset 16). */
const LINEARITY_VALUE: Record<string, number> = {
  linear: 1,
  affine: 2,
  relevant: 3,
  debug: 4,
};

/**
 * Build a 20-byte test cell for a given linearity type.
 * The cell has zero magic (getLinearity doesn't check magic),
 * linearity type at bytes 16-19 as u32 LE.
 */
function makeTestCell(linearity: string): Uint8Array {
  const cell = new Uint8Array(20);
  const view = new DataView(cell.buffer);
  view.setUint32(16, LINEARITY_VALUE[linearity], true); // little-endian
  return cell;
}

/**
 * Build a BSV script that pushes a cell and then applies stackOp.
 *
 * Push encoding for 20 bytes: direct push opcode 0x14 (20 decimal).
 *
 * StackOp → opcode mapping:
 *   duplicate → OP_DUP     (0x76): enforced linearity check
 *   discard   → OP_DROP    (0x75): enforced linearity check
 *   swap      → OP_TOALTSTACK (0x6B): spop without check
 *   inspect   → OP_DEPTH   (0x74): reads depth without touching top
 *   consume   → OP_EQUAL   (0x87): push cell twice, compare — spop × 2 without check
 */
function buildScript(linearity: string, op: string): Uint8Array {
  const cell = makeTestCell(linearity);
  const PUSH20 = 0x14; // direct push opcode for 20-byte data

  if (op === "consume") {
    // Push cell twice, then OP_EQUAL (pop both, push 1 if equal)
    const script = new Uint8Array(1 + 20 + 1 + 20 + 1);
    script[0] = PUSH20;
    script.set(cell, 1);
    script[21] = PUSH20;
    script.set(cell, 22);
    script[42] = 0x87; // OP_EQUAL
    return script;
  }

  // Single cell + op opcode
  const opcodeMap: Record<string, number> = {
    duplicate: 0x76, // OP_DUP
    discard:   0x75, // OP_DROP
    swap:      0x6B, // OP_TOALTSTACK
    inspect:   0x74, // OP_DEPTH
  };
  const opcode = opcodeMap[op];
  if (opcode === undefined) throw new Error(`Unknown stackOp: ${op}`);

  const script = new Uint8Array(1 + 20 + 1);
  script[0] = PUSH20;
  script.set(cell, 1);
  script[21] = opcode;
  return script;
}

// ── WASM query ────────────────────────────────────────────────────────────────

function queryWasm(linearity: string, op: string): boolean {
  const k = getKernel();
  const script = buildScript(linearity, op);
  const ptr = writeToWasm(k, script);

  k.kernel_reset();
  k.kernel_set_enforcement(1); // enable linearity enforcement
  const loadResult = k.kernel_load_script(ptr, script.length);
  if (loadResult !== 0) throw new Error(`kernel_load_script failed: ${loadResult}`);
  const result = k.kernel_execute();
  return isPermittedByWasm(result);
}

// ── Test cases ────────────────────────────────────────────────────────────────

const LINEARITIES = ["linear", "affine", "relevant", "debug"];
const STACK_OPS = ["duplicate", "discard", "consume", "swap", "inspect"];

// ── Test setup ────────────────────────────────────────────────────────────────

beforeAll(async () => {
  // Build oracle if binary doesn't exist
  if (!existsSync(ORACLE_BIN)) {
    const build = spawnSync([LAKE_BIN, "build", "K1LinearityOracle"], {
      cwd: LEAN4_DIR,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (build.exitCode !== 0) throw new Error("Failed to build K1LinearityOracle");
  }

  // Load WASM kernel
  const wasmBytes = readFileSync(WASM_PATH);
  const hostStubs = {
    host_fetch_cell:  () => 0,
    host_call_by_name: () => 0,
    hostDbOpenCursor: () => 0,
    hostDbCursorPull: () => 0,
    hostDbCursorClose: () => 0,
    host_sha256:      () => {},
    host_hash160:     () => {},
    host_hash256:     () => {},
    host_ripemd160:   () => {},
    host_sha1:        () => {},
    host_checksig:    () => 0,
    host_checkmultisig: () => 0,
    host_sign:        () => 0,
    host_get_blocktime: () => 0,
    host_get_sequence:  () => 0,
    host_log:         () => {},
    host_derive_leaf: () => 0,
    host_state_next_index: () => 0,
    host_unlock_tier: () => 0,
    host_persist_cell: () => 0,
  };
  const { instance } = await WebAssembly.instantiate(wasmBytes, { host: hostStubs });
  const e = instance.exports as unknown as KernelExports;
  const initResult = e.kernel_init();
  if (initResult !== 0) throw new Error(`kernel_init failed: ${initResult}`);
  kernel = e;
}, 120_000);

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("K1 Linearity — L3 Oracle vs WASM (exhaustive 4×5)", () => {
  describe("oracle sanity — known forbidden pairs", () => {
    it("linear + duplicate = false (K1a)", () => {
      expect(queryOracle("linear", "duplicate")).toBe(false);
    });
    it("linear + discard = false (K1b)", () => {
      expect(queryOracle("linear", "discard")).toBe(false);
    });
    it("affine + duplicate = false", () => {
      expect(queryOracle("affine", "duplicate")).toBe(false);
    });
    it("relevant + discard = false", () => {
      expect(queryOracle("relevant", "discard")).toBe(false);
    });
  });

  describe("oracle sanity — always-true cases", () => {
    it("debug + duplicate = true", () => {
      expect(queryOracle("debug", "duplicate")).toBe(true);
    });
    it("debug + discard = true", () => {
      expect(queryOracle("debug", "discard")).toBe(true);
    });
    it("linear + consume = true", () => {
      expect(queryOracle("linear", "consume")).toBe(true);
    });
    it("linear + swap = true", () => {
      expect(queryOracle("linear", "swap")).toBe(true);
    });
    it("linear + inspect = true", () => {
      expect(queryOracle("linear", "inspect")).toBe(true);
    });
  });

  describe("oracle vs WASM — full 4×5 table (20 differential assertions)", () => {
    for (const lin of LINEARITIES) {
      for (const op of STACK_OPS) {
        it(`${lin} + ${op}`, () => {
          const oracleResult = queryOracle(lin, op);
          const wasmResult   = queryWasm(lin, op);
          expect(wasmResult).toBe(oracleResult);
        });
      }
    }
  });
});

```
